#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <xpc/xpc.h>
#include <dlfcn.h>

static UIWindow *floatWindow = nil;
static UILabel *logLabel = nil;
static BOOL expanded = NO;

static void log(NSString *line) {
    static FILE *f = NULL;
    if (!f) {
        f = fopen("/var/mobile/Documents/xpc_log.txt", "a");
    }
    NSString *l = [line stringByAppendingString:@"\n"];
    fputs([l UTF8String], stderr);
    if (f) { fputs([l UTF8String], f); fflush(f); }
    if (logLabel) {
        dispatch_async(dispatch_get_main_queue(), ^{
            logLabel.text = [logLabel.text stringByAppendingString:l];
        });
    }
}

static void test_xpc() {
    log(@"=== XPC Test Start ===");
    // 使用 dlopen 动态加载 XPC，避免编译期链接报错
    void *handle = dlopen("/usr/lib/system/libxpc.dylib", RTLX_NOW);
    if (!handle) {
        log([NSString stringWithFormat:@"dlopen xpc failed: %s", dlerror()]);
    }
    
    typedef xpc_connection_t (*conn_fn)(const char *, dispatch_queue_t, uint64_t);
    conn_fn xpc_conn = (conn_fn)dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
    
    if (!xpc_conn) {
        log(@"xpc symbol not found");
        log(@"=== Test End ===");
        return;
    }
    
    xpc_connection_t conn = xpc_conn("com.apple.containermanagerd", NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    if (!conn) { log(@"xpc connect null"); log(@"=== Test End ==="); return; }
    
    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        log([NSString stringWithFormat:@"xpc event: %@", event]);
    });
    xpc_connection_resume(conn);
    
    xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(msg, "command", "query");
    xpc_dictionary_set_string(msg, "key", "sandbox_extensions");
    
    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(conn, msg);
    if (reply) {
        log([NSString stringWithFormat:@"xpc reply: %@", reply]);
        const char *token = xpc_dictionary_get_string(reply, "token");
        if (token) log([NSString stringWithFormat:@"got token: %s", token]);
    } else {
        log(@"xpc no reply");
    }
    
    NSArray *paths = @[@"/var/mobile/Containers/Data/Application", @"/var/mobile/Containers/Shared/AppGroup", @"/var/containers/Data/System"];
    for (NSString *p in paths) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:p];
        log([NSString stringWithFormat:@"path %@ exists=%d", p, exists]);
    }
    log(@"=== Test End ===");
}

@interface FloatBallView : UIView
@end
@implementation FloatBallView
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    expanded = !expanded;
    logLabel.hidden = !expanded;
    CGRect screen = [UIScreen mainScreen].bounds;
    if (expanded) {
        self.frame = CGRectMake(0, 0, 300, 400);
        floatWindow.frame = CGRectMake(screen.size.width - 320, 50, 300, 400);
    } else {
        self.frame = CGRectMake(0, 0, 50, 50);
        floatWindow.frame = CGRectMake(screen.size.width - 60, 100, 50, 50);
    }
}
@end

static void create_float_window() {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screen = [UIScreen mainScreen].bounds;
        floatWindow = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - 60, 100, 50, 50)];
        floatWindow.windowLevel = UIWindowLevelAlert + 100;
        floatWindow.backgroundColor = [UIColor clearColor];
        floatWindow.hidden = NO;
        
        FloatBallView *ball = [[FloatBallView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        ball.backgroundColor = [UIColor redColor];
        ball.layer.cornerRadius = 25;
        ball.layer.borderWidth = 2;
        ball.layer.borderColor = [UIColor whiteColor].CGColor;
        
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        icon.text = @"X"; icon.textColor = [UIColor whiteColor];
        icon.font = [UIFont boldSystemFontOfSize:20]; icon.textAlignment = NSTextAlignmentCenter;
        [ball addSubview:icon];
        
        logLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, 300, 340)];
        logLabel.backgroundColor = [UIColor blackColor];
        logLabel.textColor = [UIColor greenColor];
        logLabel.font = [UIFont systemFontOfSize:10];
        logLabel.numberOfLines = 0;
        logLabel.layer.cornerRadius = 8;
        logLabel.clipsToBounds = YES;
        logLabel.hidden = YES;
        [ball addSubview:logLabel];
        
        [floatWindow addSubview:ball];
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
