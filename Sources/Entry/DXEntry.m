#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <stdatomic.h>

extern void DXSwiftStart(void);
extern void DXSwiftPreferencesChanged(void);
extern void DXSwiftContextChanged(void);

static BOOL DXStarted;
static int DXPreferencesToken = NOTIFY_TOKEN_INVALID;
static int DXLockToken = NOTIFY_TOKEN_INVALID;
static int DXDisplayToken = NOTIFY_TOKEN_INVALID;

static void DXStartWhenReady(void) {
    NSCAssert(NSThread.isMainThread, @"Dynamic Stage X startup requires main thread");
    if (DXStarted) return;
    UIApplication *application = UIApplication.sharedApplication;
    if (!application || application.applicationState == UIApplicationStateBackground) return;
    DXStarted = YES;
    DXSwiftStart();
    notify_register_dispatch("com.tsangbaby.dynamicstagex/preferences-changed", &DXPreferencesToken,
        dispatch_get_main_queue(), ^(int token) { (void)token; DXSwiftPreferencesChanged(); });
    // Notifications only request reevaluation; they are not trusted lock-state payloads.
    notify_register_dispatch("com.apple.springboard.lockstate", &DXLockToken,
        dispatch_get_main_queue(), ^(int token) { (void)token; DXSwiftContextChanged(); });
    notify_register_dispatch("com.apple.iokit.hid.displayStatus", &DXDisplayToken,
        dispatch_get_main_queue(), ^(int token) { (void)token; DXSwiftContextChanged(); });
}

__attribute__((constructor)) static void DXLoad(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    DXStartWhenReady();
                }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    DXStartWhenReady();
                }];
            DXStartWhenReady();
        });
    }
}
