#import <Foundation/Foundation.h>

__attribute__((constructor))
static void entry() {
    NSLog(@"[SandboxTest] loaded in %@", [[NSBundle mainBundle] bundleIdentifier]);
    NSLog(@"[SandboxTest] home=%@", NSHomeDirectory());

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = @"/var/mobile/Containers/Data/Application";
    NSError *err = nil;
    NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:&err];
    if (err) {
        NSLog(@"[SandboxTest] list failed: %@", err);
    } else {
        NSLog(@"[SandboxTest] container count=%lu", (unsigned long)uuids.count);
        for (NSString *u in uuids) {
            NSString *doc = [base stringByAppendingPathComponent:u];
            doc = [doc stringByAppendingPathComponent:@"Documents"];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:doc isDirectory:&isDir] && isDir) {
                NSArray *files = [fm contentsOfDirectoryAtPath:doc error:nil];
                NSLog(@"[SandboxTest] %@ -> Documents: %@", u, files);
            }
        }
    }
}
