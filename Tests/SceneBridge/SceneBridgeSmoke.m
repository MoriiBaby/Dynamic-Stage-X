#import "DXSceneFixtures.h"
#include <stdlib.h>

@interface DXSceneSuite : NSObject
@property (nonatomic, strong) DXFixtureWindow *window;
@property (nonatomic, strong) DXHarnessBridge *bridge;
@property (nonatomic, strong) DXFixtureScene *scene;
@property (nonatomic, strong) NSMutableArray *failures;
@property (nonatomic, strong) NSMutableArray *cases;
@property (nonatomic) NSUInteger index;
@property (nonatomic) NSUInteger assertions;
@property (nonatomic) NSUInteger cycles;
- (void)run;
@end
@implementation DXSceneSuite
- (void)check:(BOOL)value message:(NSString *)message {
    self.assertions+=1; if (!value) [self.failures addObject:message];
}
- (NSUInteger)count:(NSString *)key { return [[self.bridge valueForKey:key] count]; }
- (NSUInteger)eventCount:(NSString *)event { return [[DXFixtureControl.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == %@",event]] count]; }
- (void)setup {
    DXFixtureReset(); self.bridge=[[DXHarnessBridge alloc] initPrivate]; self.scene=DXFixtureCreateScene(1);
    self.bridge.fixtureFrontmost=self.scene.clientProcess.bundleIdentifier;
    self.window.fixtureHitTesting=true;
}
- (void)acquire:(void (^)(DXSystemSceneHandle *))next {
    [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *handle,NSError *error) {
        [self check:handle && !error message:@"production acquisition must succeed against ABI-checked doubles"];
        if (!handle) { [self finishCase]; return; }
        next(handle);
    }];
}
- (void)finishCase {
    [self check:[self count:@"handles"]==0 && [self count:@"recovery"]==0 message:@"case must finish with no own active/recovery resources"];
    dispatch_async(dispatch_get_main_queue(),^{ [self runNext]; });
}
- (void)stress:(NSUInteger)cycle {
    if (cycle==100) { [self finishCase]; return; }
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        NSArray *faults=@[@"host.remove",@"presenter.deactivate",@"presenter.invalidate",@"scene.removeObserver",@"release.references",@"release.settings"];
        DXFixtureControl.fault=faults[cycle % faults.count];
        [self.bridge releaseHandle:handle completion:^(NSError *error) {
            [self check:error!=nil message:@"injected cleanup failure must be reported"];
            [self check:[self count:@"handles"]==0 message:@"finally must delete active registration after each cleanup failure"];
            [self check:[self count:@"recovery"]==1 message:@"unconfirmed resource must stay in bounded recovery"];
            [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *unexpected,NSError *blocked) {
                [self check:!unexpected && blocked.code==DXSystemBridgeErrorOwnership message:@"recovery must block acquisition, not create capacity"];
                DXFixtureControl.fault=nil;
                [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) {
                    [self check:retry==nil message:@"explicit retry must recover transient failure"];
                    [self check:[self count:@"handles"]==0 && [self count:@"recovery"]==0 message:@"no registry growth across 100 actual production cleanup cycles"];
                    [self check:self.scene.valid && self.scene.clientProcess.running message:@"system scene/process must survive cleanup"];
                    self.cycles=cycle+1;
                    dispatch_async(dispatch_get_main_queue(),^{ [self stress:cycle+1]; });
                }];
            }];
        }];
    }];
}
- (void)duplicateRelease {
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        DXFixtureControl.fault=@"presenter.invalidate";
        __block NSUInteger calls=0; __block NSError *first;
        void (^completion)(NSError *)=^(NSError *error) {
            if (!calls) first=error; calls+=1;
            [self check:error==first && error!=nil message:@"duplicate release must share exactly one cleanup result"];
            if (calls!=2) return;
            [self check:[self eventCount:@"presenter.invalidate"]==1 message:@"duplicate release must not repeat native teardown"];
            DXFixtureControl.fault=nil;
            [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) {
                [self check:!retry message:@"duplicate failed release must remain retryable"];
                NSUInteger invalidates=[self eventCount:@"presenter.invalidate"];
                [self.bridge releaseHandle:handle completion:^(NSError *again) {
                    [self check:!again && [self eventCount:@"presenter.invalidate"]==invalidates message:@"successful release must be idempotent"];
                    [self finishCase];
                }];
            }];
        };
        [self.bridge releaseHandle:handle completion:completion];
        [self.bridge releaseHandle:handle completion:completion];
    }];
}
- (void)queuedCancellation {
    __block BOOL acquiredCallback=NO; __block NSUInteger barriers=0;
    [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *handle,NSError *error) {
        acquiredCallback=YES; [self check:!handle && error.code==DXSystemBridgeErrorCancelled message:@"epoch must cancel queued own acquisition"];
    }];
    for (NSUInteger i=0;i<2;i++) [self.bridge releaseAllScenesWithCompletion:^(NSError *error) {
        [self check:acquiredCallback && !error message:@"releaseAll must await cancelled acquisition delivery"];
        barriers+=1; if (barriers==2) [self finishCase];
    }];
}
- (void)pendingCancellation {
    DXFixtureControl.pending=[[DXBridgeOperation alloc] initWithTimeout:20 completion:^(__unused NSError *error) { }];
    __block NSUInteger calls=0;
    [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *handle,NSError *error) {
        calls+=1; [self check:!handle && error.code==DXSystemBridgeErrorCancelled message:@"pending own acquisition must complete cancelled after cleanup"];
    }];
    dispatch_async(dispatch_get_main_queue(),^{
        DXBridgeOperation *pending=DXFixtureControl.pending;
        [self check:[self count:@"handles"]==1 message:@"pending fixture must have created an actual production owned handle"];
        [self.bridge releaseAllScenesWithCompletion:^(NSError *error) {
            [self check:!error && calls==1 message:@"barrier must await pending acquisition cleanup and callback"];
            [pending finish:nil];
            [self check:calls==1 message:@"late duplicate completion must not resurrect a cancelled handle"];
            [self finishCase];
        }];
    });
}
- (void)partialAcquisition:(NSUInteger)index {
    NSArray *faults=@[@"acquire.manager",@"manager.createPresenter",@"scene.addObserver"];
    if (index==faults.count) { [self finishCase]; return; }
    DXFixtureControl.fault=faults[index];
    [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *handle,NSError *error) {
        [self check:!handle && error!=nil message:@"partial acquisition must return its primary error, not a handle"];
        [self check:[error.userInfo[DXSceneOperationKey] isEqual:@"acquire"] message:@"partial acquisition must preserve operation diagnosis"];
        [self check:[self count:@"handles"]==0 && [self count:@"recovery"]==0 message:@"partial native manager/observer must be cleaned by production release"];
        DXFixtureControl.fault=nil;
        [self.bridge releaseAllScenesWithCompletion:^(NSError *cleanup) {
            [self check:!cleanup message:@"partial acquisition must leave a drainable bridge"];
            [self partialAcquisition:index+1];
        }];
    }];
}
- (void)latePresentationCallback {
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView]; DXFixtureControl.lateContext=YES;
        [self.bridge applyFrame:CGRectInset(UIScreen.mainScreen.bounds,20,20) toHandle:handle completion:^(NSError *error) {
            [self check:error.code==DXSystemBridgeErrorSystemRejected message:@"non-synchronous context callback must fail closed"];
            NSUInteger writes=[self eventCount:@"context.setTransformer"];
            void (^late)(id)=DXFixtureControl.lateBlock; if (late) { late(DXFixtureControl.lateObject); late(DXFixtureControl.lateObject); }
            [self check:late!=nil && [self eventCount:@"context.setTransformer"]==writes message:@"late/repeated context callback cannot mutate a released presenter"];
            [self.bridge releaseAllScenesWithCompletion:^(NSError *cleanup) { [self check:!cleanup message:@"late context failure must drain"]; [self finishCase]; }];
        }];
    }];
}
- (void)readinessTimeout {
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        self.scene.clientProcess.foreground=false; self.window.fixtureHitTesting=false;
        [self.bridge applyFrame:CGRectInset(UIScreen.mainScreen.bounds,20,20) toHandle:handle completion:^(NSError *error) {
            NSDictionary *snapshot=error.userInfo[DXSceneReadinessKey]; NSArray *pending=snapshot[@"pending"];
            [self check:error.code==DXSystemBridgeErrorTimeout && [error.userInfo[DXSceneOperationKey] isEqual:@"apply"] && [error.userInfo[DXSceneStageKey] isEqual:@"readiness"] message:@"timeout must retain apply name, readiness stage and primary error"];
            [self check:[snapshot[@"checks"] count]==6 && [snapshot[@"reasons"] count]>=2 message:@"all independent readiness groups must survive timeout"];
            [self check:[pending containsObject:@"process"] && [pending containsObject:@"events"] && ![pending containsObject:@"settings"] message:@"false process foreground cannot hide separate event or successful settings checks"];
            [self check:![snapshot[@"checks"][@"process"][@"checks"][@"foreground"] boolValue] message:@"process foreground gate must remain mandatory"];
            [self check:[handle.readiness isEqual:snapshot] message:@"handle and timeout must expose the same readiness snapshot"];
            [self check:CGRectEqualToRect(self.scene.settings.frame,UIScreen.mainScreen.bounds) && self.scene.settings.backgrounded message:@"owned settings must actually restore through production cleanup"];
            [self.bridge releaseAllScenesWithCompletion:^(NSError *cleanup) { [self check:!cleanup message:@"timed out apply must drain"]; [self finishCase]; }];
        }];
    }];
}
- (void)primaryAndCleanupError {
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        DXFixtureControl.fault=@"presenter.activate,release.invalidate";
        [self.bridge applyFrame:CGRectInset(UIScreen.mainScreen.bounds,20,20) toHandle:handle completion:^(NSError *error) {
            [self check:[error.userInfo[DXSceneOperationKey] isEqual:@"apply"] && [error.userInfo[DXSceneStageKey] isEqual:@"presenter-activate"] message:@"cleanup cannot replace original apply-stage diagnosis"];
            [self check:[error.userInfo[DXSceneCleanupErrorsKey] count]>0 && [self count:@"handles"]==0 && [self count:@"recovery"]==1 message:@"combined error must retain cleanup failure and bounded recovery"];
            DXFixtureControl.fault=nil;
            [self.bridge releaseAllScenesWithCompletion:^(NSError *cleanup) { [self check:!cleanup message:@"combined failure must explicitly recover"]; [self finishCase]; }];
        }];
    }];
}
- (void)capacityAndPersistentFailure {
    DXFixtureCreateScene(2); DXFixtureCreateScene(3); DXFixtureScene *fourth=DXFixtureCreateScene(4);
    [self acquire:^(DXSystemSceneHandle *first) {
        [self.bridge acquireSceneForBundleIdentifier:@"fixture.app.2" completion:^(DXSystemSceneHandle *second,NSError *e2) {
            [self check:second && !e2 message:@"second owned scene must acquire"];
            [self.bridge acquireSceneForBundleIdentifier:@"fixture.app.3" completion:^(DXSystemSceneHandle *third,NSError *e3) {
                [self check:third && !e3 message:@"third staging scene must acquire"];
                [self.bridge acquireSceneForBundleIdentifier:fourth.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *excess,NSError *limit) {
                    [self check:!excess && limit.code==DXSystemBridgeErrorOwnership && [self count:@"handles"]==3 message:@"fourth total own resource must be refused"];
                    DXFixtureControl.fault=@"presenter.invalidate";
                    [self.bridge releaseAllScenesWithCompletion:^(NSError *failed) {
                        [self check:failed && [self count:@"handles"]==0 && [self count:@"recovery"]==3 message:@"moving all three resources to recovery must not grant capacity"];
                        [self.bridge releaseAllScenesWithCompletion:^(NSError *stillFailed) {
                            [self check:stillFailed && [self count:@"recovery"]==3 message:@"persistent recovery must remain bounded and report failure"];
                            DXFixtureControl.fault=nil;
                            [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) { [self check:!retry message:@"explicit successful retry reopens bridge"]; [self finishCase]; }];
                        }];
                    }];
                }];
            }];
        }];
    }];
}
- (void)globalObserverRetry {
    [self acquire:^(DXSystemSceneHandle *handle) {
        DXFixtureControl.fault=@"process.removeObserver,focusToken.invalidate";
        [self.bridge releaseAllScenesWithCompletion:^(NSError *error) {
            [self check:error && [[self.bridge valueForKey:@"observationError"] isKindOfClass:NSError.class] message:@"failed global observer removal cannot be silently forgotten"];
            [self.bridge acquireSceneForBundleIdentifier:self.scene.clientProcess.bundleIdentifier completion:^(DXSystemSceneHandle *unexpected,NSError *blocked) {
                [self check:!unexpected && blocked.code==DXSystemBridgeErrorOwnership message:@"unremoved observer must block new acquisition"];
                DXFixtureControl.fault=nil;
                [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) { [self check:!retry && ![self.bridge valueForKey:@"observationError"] message:@"global observer retry must consume exact retained targets"]; [self finishCase]; }];
            }];
        }];
    }];
}
// All cases drive production apply/release; no synthetic handle cleanup flags.
- (void)activationRollback:(NSUInteger)mode {
    self.scene.active=false;
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        DXFixtureSettings *original=self.scene.settings;
        if (mode==1) {
            // Throw before the apply write, after production has activated the scene.
            __weak DXHarnessBridge *bridge=self.bridge;
            DXFixtureControl.beforeSettingsWrite=^{ bridge.fixtureFrontmost=@"fixture.other"; };
            DXFixtureControl.oneShotFault=@"scene.updateSettings,scene.deactivate";
        }
        [self.bridge applyFrame:CGRectInset(UIScreen.mainScreen.bounds,20,20) toHandle:handle completion:^(NSError *applyError) {
            DXFixtureControl.beforeSettingsWrite=nil;
            [self check:[self eventCount:@"scene.activate"]==1 && self.scene.active message:@"production apply must activate the originally inactive scene"];
            void (^verifyRetry)(NSError *)=^(NSError *error) {
                [self check:error && [self count:@"handles"]==0 && [self count:@"recovery"]==1 message:@"failed independent rollback must retain exactly one recovery lease"];
                if (mode==2) {
                    [self check:!self.scene.active && !CGRectEqualToRect(self.scene.settings.frame,original.frame) message:@"restore-write exception must not skip independent scene deactivation"];
                } else {
                    [self check:self.scene.active && CGRectEqualToRect(self.scene.settings.frame,original.frame) && self.scene.settings.backgrounded==original.backgrounded && self.scene.settings.foreground==original.foreground message:@"deactivate failure must retain active scene even when settings are already original"];
                }
                [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) {
                    [self check:!retry && !self.scene.active && [self count:@"handles"]==0 && [self count:@"recovery"]==0 message:@"explicit recovery may reach zero resources only after own activation is inactive"];
                    [self check:[self eventCount:@"scene.deactivate"]==(mode==2 ? 1u : 2u) message:@"one-shot deactivate failure must retry despite restored or never-written settings"];
                    [self check:CGRectEqualToRect(self.scene.settings.frame,original.frame) && self.scene.settings.backgrounded==original.backgrounded && self.scene.settings.foreground==original.foreground message:@"retry must acknowledge all original settings"];
                    [self finishCase];
                }];
            };
            if (mode==1) {
                [self check:applyError && [applyError.userInfo[DXSceneStageKey] isEqual:@"settings-submit"] && self.scene.settings==original message:@"before-write apply exception must preserve primary stage and untouched settings"];
                verifyRetry(applyError);
            } else {
                [self check:!applyError message:@"inactive-scene apply must pass production readiness before rollback injection"];
                self.bridge.fixtureFrontmost=@"fixture.other";
                DXFixtureControl.oneShotFault=mode==2 ? @"scene.updateSettings" : @"scene.deactivate";
                [self.bridge releaseHandle:handle completion:verifyRetry];
            }
        }];
    }];
}
- (void)activationNativeTakeover:(BOOL)settingsConflict {
    self.scene.active=false;
    [self acquire:^(DXSystemSceneHandle *handle) {
        [self.window.rootViewController.view addSubview:handle.hostView];
        DXFixtureSettings *original=self.scene.settings;
        [self.bridge applyFrame:CGRectInset(UIScreen.mainScreen.bounds,20,20) toHandle:handle completion:^(NSError *applyError) {
            [self check:!applyError && self.scene.active message:@"native takeover case requires successful production activation"];
            if (settingsConflict) {
                self.bridge.fixtureFrontmost=@"fixture.other";
                self.scene.settings.frame=CGRectInset(UIScreen.mainScreen.bounds,40,40);
            }
            DXFixtureControl.oneShotFault=@"release.references";
            [self.bridge releaseHandle:handle completion:^(NSError *error) {
                [self check:error && self.scene.active && [self eventCount:@"scene.deactivate"]==0 && [self count:@"recovery"]==1 message:@"native frontmost or settings takeover must never deactivate and must retain unrelated failed cleanup"];
                if (settingsConflict) [self check:CGRectEqualToRect(self.scene.settings.frame,CGRectInset(UIScreen.mainScreen.bounds,40,40)) message:@"native conflicting frame must not be overwritten"];
                // Even if values later look original, rollback authority must not be reclaimed.
                self.scene.settings=original; self.bridge.fixtureFrontmost=@"fixture.other";
                [self.bridge releaseAllScenesWithCompletion:^(NSError *retry) {
                    [self check:!retry && self.scene.active && [self eventCount:@"scene.deactivate"]==0 message:@"recovery retry must preserve native activation after takeover"];
                    [self finishCase];
                }];
            }];
        }];
    }];
}
- (void)writeResult {
    NSDictionary *result=@{@"passed":@(self.failures.count==0),@"assertions":@(self.assertions),@"production_cleanup_cycles":@(self.cycles),@"cases":self.cases,@"failures":self.failures,
        @"scope":@"Production DXRuntime.m and DXSystemBridge.m; real simulator UIWindowScene/UIView/CALayer; private system classes and event authority are ABI-mapped doubles, NOT SpringBoard or device proof"};
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    [data writeToFile:[documents stringByAppendingPathComponent:@"scene-bridge-result.json"] atomically:YES];
    NSLog(@"SCENE_BRIDGE_RESULT %@",result); exit(self.failures.count ? 1 : 0);
}
- (void)runNext {
    NSArray *names=@[@"100_cleanup_failure_cycles",@"duplicate_release",@"queued_epoch_cancel",@"pending_cancel_late_completion",@"partial_acquisition",@"late_context_callback",@"independent_readiness_timeout",@"primary_plus_cleanup",@"max3_persistent_recovery",@"global_observer_retry",@"activation_deactivate_retry",@"activation_apply_write_failure",@"activation_restore_write_failure",@"activation_native_frontmost",@"activation_native_settings_conflict"];
    if (self.index==names.count) { [self writeResult]; return; }
    [self.cases addObject:names[self.index]]; [self setup];
    switch (self.index++) {
        case 0: [self stress:0]; break;
        case 1: [self duplicateRelease]; break;
        case 2: [self queuedCancellation]; break;
        case 3: [self pendingCancellation]; break;
        case 4: [self partialAcquisition:0]; break;
        case 5: [self latePresentationCallback]; break;
        case 6: [self readinessTimeout]; break;
        case 7: [self primaryAndCleanupError]; break;
        case 8: [self capacityAndPersistentFailure]; break;
        case 9: [self globalObserverRetry]; break;
        case 10: [self activationRollback:0]; break;
        case 11: [self activationRollback:1]; break;
        case 12: [self activationRollback:2]; break;
        case 13: [self activationNativeTakeover:NO]; break;
        case 14: [self activationNativeTakeover:YES]; break;
    }
}
- (void)run { self.failures=[NSMutableArray array]; self.cases=[NSMutableArray array]; [self runNext]; }
@end

@interface DXSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) DXSceneSuite *suite;
@end
@implementation DXSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    DXFixtureWindow *window=[[DXFixtureWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController=[UIViewController new]; [window makeKeyAndVisible]; self.window=window;
    self.suite=[DXSceneSuite new]; self.suite.window=window;
    dispatch_async(dispatch_get_main_queue(),^{ [self.suite run]; });
}
@end
@interface DXSceneAppDelegate : UIResponder <UIApplicationDelegate> @end
@implementation DXSceneAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"SceneBridgeTest" sessionRole:session.role];
    config.delegateClass=DXSceneDelegate.class; return config;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(DXSceneAppDelegate.class)); } }
