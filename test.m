#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <xpc/xpc.h>
#include <sandbox.h>

static UIWindow *floatWindow;
static UILabel *logLabel;
static BOOL expanded = NO;
static NSMutableString *logs;

static void log(NSString *msg) {
    NSLog(@"[xpc_test] %@", msg);
    [logs appendFormat:@"%@\n", msg];
    [logLabel setText:logs];
    [logs writeToFile:@"/var/mobile/Documents/xpc_log.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void test_xpc() {
    logs = [NSMutableString string];
    log(@"=== XPC Test Start ===");
    
    // 1. 尝试连接 containermanagerd
    xpc_connection_t conn = xpc_connection_create_mach_service(
        "com.apple.containermanagerd",
        NULL,
        XPC_CONNECTION_MACH_SERVICE_PRIVILEGED
    );
    
    if (!conn) {
        log(@"[-] Failed to create XPC connection");
        return;
    }
    log(@"[+] XPC connection created");
    
    // 2. 设置事件处理器
    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) {
            log([NSString stringWithFormat:@"[-] XPC error: %s", xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION)]);
        } else if (xpc_get_type(event) == XPC_TYPE_DICTIONARY) {
            log(@"[+] Got XPC reply!");
            // 打印所有 key
            xpc_dictionary_apply(event, ^bool(const char *key, xpc_object_t value) {
                log([NSString stringWithFormat:@"    key=%s type=%s", key, xpc_type_get_name(xpc_get_type(value))]);
                if (xpc_get_type(value) == XPC_TYPE_STRING) {
                    log([NSString stringWithFormat:@"    value=%s", xpc_string_get_string_ptr(value)]);
                }
                if (xpc_get_type(value) == XPC_TYPE_INT64) {
                    log([NSString stringWithFormat:@"    value=%lld", xpc_int64_get_value(value)]);
                }
                return true;
            });
        }
    });
    
    // 3. 发送查询消息（参考 bad_query 的查询方式）
    xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(msg, "operation", "get_container_extensions");
    xpc_dictionary_set_string(msg, "bundle_id", "com.apple.filza");
    xpc_dictionary_set_string(msg, "container_class", "appData");
    xpc_dictionary_set_bool(msg, "include_sandbox_extensions", true);
    
    log(@"[+] Sending XPC query...");
    xpc_connection_send_message(conn, msg);
    xpc_release(msg);
    xpc_connection_resume(conn);
    log(@"[+] XPC message sent, waiting for reply...");
    
    // 4. 测试容器访问
    NSArray *paths = @[
        @"/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Shared/AppGroup",
        @"/var/containers/Data/System"
    ];
    for (NSString *p in paths) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:p];
        log([NSString stringWithFormat:@"path %@ exists=%d", p, exists]);
        if (exists) {
            NSError *err = nil;
            NSArray *c = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:p error:&err];
            if (err) {
                log([NSString stringWithFormat:@"  list error: %@", err.localizedDescription]);
            } else {
                log([NSString stringWithFormat:@"  items: %lu", (unsigned long)c.count]);
            }
        }
    }
    
    log(@"=== Test End ===");
}

// 悬浮窗
static void create_float_window() {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screen = [UIScreen mainScreen].bounds;
        floatWindow = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - 60, 100, 50, 50)];
        floatWindow.windowLevel = UIWindowLevelAlert + 100;
        floatWindow.backgroundColor = [UIColor clearColor];
        floatWindow.hidden = NO;
        
        UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        ball.backgroundColor = [UIColor redColor];
        ball.layer.cornerRadius = 25;
        ball.layer.borderWidth = 2;
        ball.layer.borderColor = [UIColor whiteColor].CGColor;
        ball.userInteractionEnabled = YES;
        
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        icon.text = @"X";
        icon.textColor = [UIColor whiteColor];
        icon.font = [UIFont boldSystemFontOfSize:20];
        icon.textAlignment = NSTextAlignmentCenter;
        [ball addSubview:icon];
        
        // 日志面板（默认隐藏）
        logLabel = [[UILabel alloc] initWithFrame:CGRectMake(-200, 60, 250, 400)];
        logLabel.backgroundColor = [UIColor blackColor];
        logLabel.textColor = [UIColor greenColor];
        logLabel.font = [UIFont systemFontOfSize:10];
        logLabel.numberOfLines = 0;
        logLabel.layer.cornerRadius = 8;
        logLabel.clipsToBounds = YES;
        logLabel.hidden = YES;
        [ball addSubview:logLabel];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
        [ball addGestureRecognizer:tap];
        
        // 用 block 处理点击
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            [[NSNotificationCenter defaultCenter] addObserverForName:@"tap" object:nil queue:nil usingBlock:^(NSNotification *n){
                expanded = !expanded;
                logLabel.hidden = !expanded;
                ball.frame = expanded ? CGRectMake(-200, 0, 300, 500) : CGRectMake(0, 0, 50, 50);
                floatWindow.frame = expanded ? CGRectMake(screen.size.width - 320, 50, 300, 500) : CGRectMake(screen.size.width - 60, 100, 50, 50);
            }];
        });
        
        tap.addTarget = ^(id target, SEL action){
            [[NSNotificationCenter defaultCenter] postNotificationName:@"tap" object:nil];
        };
        
        [floatWindow addSubview:ball];
        
        // 延迟执行测试（等 UI 起来）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            test_xpc();
        });
    });
}

__attribute__((constructor))
static void entry() {
    NSLog(@"[xpc_test] dylib loaded!");
    create_float_window();
}
