#import <Foundation/Foundation.h>

static NSString *logPath;

static void jb_log(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSLog(@"[probe] %@", msg);
    FILE *f = fopen([logPath UTF8String], "a");
    if (f) { fputs([line UTF8String], f); fclose(f); }
}

static void run_probe() {
    jb_log(@"=== PROBE START ===");
    
    // 1. 探测容器路径
    NSArray *paths = @[
        @"/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Shared/AppGroup",
        @"/var/containers/Data/System",
        @"/var/mobile/Library/ProtectedSystem"
    ];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in paths) {
        BOOL exists = [fm fileExistsAtPath:p];
        if (exists) {
            NSError *err = nil;
            NSArray *c = [fm contentsOfDirectoryAtPath:p error:&err];
            if (err) {
                jb_log([NSString stringWithFormat:@"%@ EXISTS but list FAILED: %@", p, err.localizedDescription]);
            } else {
                jb_log([NSString stringWithFormat:@"%@ EXISTS, items=%lu", p, (unsigned long)c.count]);
                for (int i = 0; i < MIN(5, (int)c.count); i++) {
                    jb_log([NSString stringWithFormat:@"  - %@", c[i]]);
                }
            }
        } else {
            jb_log([NSString stringWithFormat:@"%@ NOT EXISTS", p]);
        }
    }
    
    // 2. 探测 MobileGestalt
    NSString *mg = @"/var/mobile/Library/Preferences/com.apple.MobileGestalt.plist";
    if ([fm fileExistsAtPath:mg]) {
        jb_log(@"MobileGestalt.plist: EXISTS");
    } else {
        jb_log(@"MobileGestalt.plist: NOT FOUND");
    }
    
    // 3. 探测 PosterBoard
    NSString *pb = @"/var/mobile/Library/PosterBoard";
    if ([fm fileExistsAtPath:pb]) {
        jb_log(@"PosterBoard: EXISTS");
    } else {
        jb_log(@"PosterBoard: NOT FOUND");
    }
    
    // 4. 探测自己能读到哪些 App 的 Documents
    NSString *appData = @"/var/mobile/Containers/Data/Application";
    if ([fm fileExistsAtPath:appData]) {
        NSError *err = nil;
        NSArray *uuids = [fm contentsOfDirectoryAtPath:appData error:&err];
        if (!err) {
            jb_log([NSString stringWithFormat:@"total App containers visible: %lu", (unsigned long)uuids.count]);
            int readable = 0;
            for (NSString *uuid in uuids) {
                NSString *doc = [appData stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/Documents", uuid]];
                if ([fm fileExistsAtPath:doc]) {
                    readable++;
                }
            }
            jb_log([NSString stringWithFormat:@"readable Documents: %d / %lu", readable, (unsigned long)uuids.count]);
        }
    }
    
    jb_log(@"=== PROBE END ===");
}

__attribute__((constructor))
static void entry() {
    logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/probe_log.txt"];
    [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    run_probe();
}
