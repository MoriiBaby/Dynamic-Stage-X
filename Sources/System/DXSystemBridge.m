#import "DXSystemBridge.h"
#import "DXRuntime.h"
#import "DXABIEncoding.h"
#import "DXLeasePolicy.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

NSErrorDomain const DXSystemBridgeErrorDomain = @"com.tsangbaby.dynamicstagex.system";
NSNotificationName const DXSystemSceneInvalidatedNotification = @"com.tsangbaby.dynamicstagex/scene-invalidated";
NSNotificationName const DXSystemKeyboardFocusChangedNotification = @"com.tsangbaby.dynamicstagex/keyboard-focus-changed";

/* Minimal declaration solely to make ARC consume alloc/return init ownership correctly.
   No private class reference is linked: lookup is NSClassFromString, ABI checked before send. */
@interface UIScenePresentationManager : NSObject
- (instancetype)_initWithScene:(id)scene __attribute__((objc_method_family(init)));
@end

@interface DXApplicationRecord ()
- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name;
@end
@implementation DXApplicationRecord
- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name {
    if ((self = [super init])) { _bundleIdentifier = [identifier copy]; _displayName = [name copy]; }
    return self;
}
- (UIImage *)icon { return nil; } // Optional; no undocumented icon loading side effects.
@end

@interface DXSystemSceneHandle ()
@property (nonatomic, weak) DXSystemBridge *owner;
@property (nonatomic, strong) id scene;
@property (nonatomic, strong) id process;
@property (nonatomic, strong) id presentationManager;
@property (nonatomic, strong) id presenter;
@property (nonatomic, strong) DXBridgeOperation *operation;
@property (nonatomic, strong) DXBridgeOperation *releaseOperation;
@property (nonatomic, strong) NSError *releaseError;
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *sceneIdentifier;
@property (nonatomic) pid_t processIdentifier;
@property (nonatomic) BOOL released;
@property (nonatomic, copy) NSDictionary<NSString *, id> *readinessSnapshot;
@property (nonatomic) BOOL hostDetached;
@property (nonatomic) BOOL presenterDeactivated;
@property (nonatomic) BOOL presenterInvalidated;
@property (nonatomic) BOOL settingsRestored;
@property (nonatomic) BOOL referencesDropped;
@property (nonatomic, strong) NSError *referenceFailure;
@property (nonatomic, strong) NSMutableArray *releaseWaiters;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL observed;
@property (nonatomic) BOOL interactive;
@property (nonatomic) BOOL changedSettings;
@property (nonatomic) CGRect originalFrame;
@property (nonatomic) CGRect writtenFrame;
@property (nonatomic) bool originalForeground;
@property (nonatomic) bool originalBackgrounded;
@property (nonatomic) BOOL hasForeground;
@property (nonatomic) BOOL activatedScene;
@property (nonatomic) BOOL deactivatedScene;
@property (nonatomic) BOOL activationRelinquished; // Native takeover permanently ends our activation rollback authority.
@property (nonatomic) unsigned restoreMask;
@property (nonatomic, strong) id restoreFocusScene;
@property (nonatomic) uint64_t restoreFocusGeneration;
- (instancetype)initWithOwner:(DXSystemBridge *)owner scene:(id)scene;
- (void)sceneDidInvalidate:(id)scene;
@end

@interface DXSystemBridge ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, DXSystemSceneHandle *> *handles;
@property (nonatomic, strong) NSMutableSet<DXSystemSceneHandle *> *recovery;
@property (nonatomic, strong) NSMutableSet<DXBridgeOperation *> *acquisitions;
@property (nonatomic, strong) NSMutableArray *releaseAllWaiters;
@property (nonatomic, strong) NSError *releaseAllError;
@property (nonatomic, strong) NSError *observationError;
@property (nonatomic) NSUInteger epoch; // Access cross-thread only inside @synchronized(self).
@property (nonatomic) NSUInteger barriersRequested;
@property (nonatomic) NSUInteger releaseAllInFlight;
@property (nonatomic) BOOL releaseAllScheduling;
@property (nonatomic, strong) id processObserverManager;
@property (nonatomic, strong) id focusObserverToken;
@property (nonatomic, strong) id focusObserverController;
@property (nonatomic, strong) id previousFocusScene;
@property (nonatomic, weak) DXSystemSceneHandle *focusOwner;
@property (nonatomic) uint64_t focusGeneration;
@property (nonatomic) BOOL focusPending;
@property (nonatomic) BOOL nativePending;
@property (nonatomic) BOOL contextLost;
@property (nonatomic) NSUInteger restorations;
@property (nonatomic, strong) DXBridgeOperation *focusOperation;
@property (nonatomic, strong) dispatch_source_t watchdog;
- (instancetype)initPrivate;
- (BOOL)ownsLiveHandle:(DXSystemSceneHandle *)handle;
- (NSUInteger)ownedResourceCount;
- (void)invalidateHandle:(DXSystemSceneHandle *)handle;
- (NSError * _Nullable)tearDown:(DXSystemSceneHandle *)handle;
- (void)maybeFinishReleaseAll;
- (NSError * _Nullable)endObserving;
- (BOOL)cleanupConfirmed:(DXSystemSceneHandle *)handle;
@end

static id DXShared(NSString *className, SEL selector) {
    Class cls = DXRuntimeClass(className);
    if (!cls) DXThrow(DXSystemBridgeErrorUnavailable, [@"Missing class: " stringByAppendingString:className]);
    id object = DXObject(cls, selector);
    if (!object) DXThrow(DXSystemBridgeErrorUnavailable, [@"Missing system singleton: " stringByAppendingString:className]);
    return object;
}
static void DXRequire(BOOL condition, NSInteger code, NSString *message) { if (!condition) DXThrow(code, message); }
static NSString *DXString(id object) { return [object isKindOfClass:NSString.class] && [object length] ? object : nil; }
static NSArray *DXCollection(id object) {
    if ([object isKindOfClass:NSSet.class]) return [object allObjects];
    if ([object isKindOfClass:NSOrderedSet.class]) return [object array];
    if ([object isKindOfClass:NSArray.class]) return object;
    DXThrow(DXSystemBridgeErrorABI, @"System scene/application collection has unexpected class"); return @[];
}
static id DXSceneManager(void) { return DXShared(@"FBSceneManager", @selector(sharedInstance)); }
static id DXMainManager(void) { return DXShared(@"SBSceneManagerCoordinator", @selector(mainDisplaySceneManager)); }
static id DXWorkspace(void) { return DXShared(@"SBMainWorkspace", @selector(sharedInstance)); }
static id DXFocusController(void) { return DXObject(DXWorkspace(), @selector(keyboardFocusController)); }
static id DXSettings(id scene) { id s = DXObject(scene, @selector(settings)); DXRequire(s != nil, DXSystemBridgeErrorUnavailable, @"Scene has no settings"); return s; }
static BOOL DXSpringBoard(void) {
#if DX_SCENE_BRIDGE_TESTING
    return DXSceneBridgeTestingSpringBoard();
#else
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
#endif
}
static void DXCheckpoint(NSString *stage, id object) {
#if DX_SCENE_BRIDGE_TESTING
    DXSceneBridgeTestingCheckpoint(stage,object);
#else
    (void)stage; (void)object;
#endif
}
static NSError *DXCleanupCaught(NSException *e, NSString *stage) {
    NSError *error=DXCaught(e); NSMutableDictionary *info=[error.userInfo mutableCopy];
    info[DXSceneOperationKey]=@"release"; info[DXSceneStageKey]=stage;
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}
static BOOL DXSceneStillRegistered(id scene) {
    if (!scene || !DXBool(scene,@selector(isValid))) return NO;
    NSString *sid = DXString(DXObject(scene,@selector(identifier)));
    return sid && DXObject1(DXSceneManager(),@selector(sceneWithIdentifier:),sid) == scene;
}
static id DXFocusedScene(void) {
    id scene = DXObject(DXFocusController(), @selector(sceneWithFocusIncludingSpringBoard));
    return scene && DXSceneStillRegistered(scene) ? scene : nil;
}
static BOOL DXSettingsEqual(DXSystemSceneHandle *h) {
    id s=DXSettings(h.scene);
    return CGRectEqualToRect(DXFrame(s),h.writtenFrame) && !DXBool(s,@selector(isBackgrounded)) &&
        (!h.hasForeground || DXBool(s,@selector(isForeground)));
}
static void DXWriteSettings(id scene, id settings) {
    SEL s=@selector(updateSettings:withTransitionContext:);
    ((void (*)(id,SEL,id,id))DXCheckedIMP(scene,s,"v","@@"))(scene,s,settings,nil);
}

@implementation DXSystemSceneHandle
- (instancetype)initWithOwner:(DXSystemBridge *)owner scene:(id)scene {
    if ((self=[super init])) {
        _owner=owner; _scene=scene; _process=DXObject(scene,@selector(clientProcess));
        _sceneIdentifier=[DXString(DXObject(scene,@selector(identifier))) copy];
        _bundleIdentifier=[DXString(DXObject(_process,@selector(bundleIdentifier))) copy];
        _processIdentifier=DXPID(_process,@selector(pid));
    }
    return self;
}
- (NSDictionary<NSString *, id> *)readiness {
    if (!NSThread.isMainThread) return @{};
    return self.readinessSnapshot ?: @{@"phase":@"not-applied",@"pending":@[@"settings",@"scene",@"process",@"presenter",@"layers",@"events"],@"checks":@{},@"reasons":@{}};
}
- (BOOL)isValid {
    if (!NSThread.isMainThread) return NO;
    @try { return [self.owner ownsLiveHandle:self]; } @catch (__unused NSException *e) { return NO; }
}
- (void)sceneDidInvalidate:(id)scene {
    dispatch_async(dispatch_get_main_queue(), ^{ if (scene==self.scene) [self.owner invalidateHandle:self]; });
}
@end

#include "DXSceneReadiness.inc"

@implementation DXSystemBridge
- (instancetype)initPrivate {
    if ((self=[super init])) {
        _handles=[NSMutableDictionary dictionary]; _recovery=[NSMutableSet set];
        _acquisitions=[NSMutableSet set]; _releaseAllWaiters=[NSMutableArray array];
    }
    return self;
}
+ (instancetype)sharedBridge {
    static DXSystemBridge *bridge; static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge=[[DXSystemBridge alloc] initPrivate]; });
    return bridge;
}
- (BOOL)isLocked {
    if (!NSThread.isMainThread || !DXSpringBoard()) return YES;
    @try { return DXBool(DXShared(@"SBLockScreenManager",@selector(sharedInstance)),@selector(isUILocked)); }
    @catch (__unused NSException *e) { return YES; }
}
- (NSString *)frontmostApplicationIdentifier {
    if (!NSThread.isMainThread || !DXSpringBoard()) return nil;
    @try {
        id app=DXObject(UIApplication.sharedApplication,@selector(_accessibilityFrontMostApplication));
        return [DXString(DXObject(app,@selector(bundleIdentifier))) copy];
    } @catch (__unused NSException *e) { return nil; }
}
- (NSArray<DXApplicationRecord *> *)applications {
    if (!NSThread.isMainThread || !DXSpringBoard()) return @[];
    @try {
        id controller=DXShared(@"SBApplicationController",@selector(sharedInstance));
        NSMutableDictionary *unique=[NSMutableDictionary dictionary];
        for (id app in DXCollection(DXObject(controller,@selector(allApplications)))) {
            NSString *bid=DXString(DXObject(app,@selector(bundleIdentifier)));
            NSString *name=DXString(DXObject(app,@selector(displayName))) ?: bid;
            if (bid && ![bid isEqualToString:@"com.apple.springboard"])
                unique[bid]=[[DXApplicationRecord alloc] initWithIdentifier:bid name:name];
        }
        return [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(DXApplicationRecord *a, DXApplicationRecord *b) {
            NSComparisonResult r=[a.displayName localizedStandardCompare:b.displayName];
            return r==NSOrderedSame ? [a.bundleIdentifier compare:b.bundleIdentifier] : r;
        }];
    } @catch (__unused NSException *e) { return @[]; }
}
- (pid_t)keyboardFocusProcessIdentifier {
    if (!NSThread.isMainThread || !DXSpringBoard() || self.isLocked) return 0;
    @try {
        id scene=DXFocusedScene(), process=scene ? DXObject(scene,@selector(clientProcess)) : nil;
        return process && DXBool(process,@selector(isRunning)) ? DXPID(process,@selector(pid)) : 0;
    } @catch (__unused NSException *e) { return 0; }
}

- (id)uniqueSceneForIdentifier:(NSString *)identifier {
    NSMutableArray *matches=[NSMutableArray array];
    Protocol *settingsProtocol=DXRuntimeProtocol(@"UIApplicationSceneSettings");
    DXRequire(settingsProtocol!=nil,DXSystemBridgeErrorUnavailable,@"UIApplicationSceneSettings protocol unavailable");
    for (id scene in DXCollection(DXObject(DXMainManager(),@selector(allScenes)))) {
        if (!DXBool(scene,@selector(isValid))) continue;
        id process=DXObject(scene,@selector(clientProcess));
        if (!process || ![DXString(DXObject(process,@selector(bundleIdentifier))) isEqualToString:identifier]) continue;
        id settings=DXSettings(scene);
        if (![settings conformsToProtocol:settingsProtocol] || !DXBool(process,@selector(isRunning))) continue;
        if (!DXObject1(DXMainManager(),@selector(existingSceneHandleForScene:),scene)) continue;
        if (DXPID(process,@selector(pid))>0) [matches addObject:scene];
    }
    DXRequire(matches.count!=0,DXSystemBridgeErrorNoScene,@"No existing live main-display application scene; use native activation after releasing all handles");
    DXRequire(matches.count==1,DXSystemBridgeErrorAmbiguousScene,@"Multiple eligible scenes; explicit scene-selection API is required, no first-scene fallback");
    return matches[0];
}
- (BOOL)ownsLiveHandle:(DXSystemSceneHandle *)h {
    if (!NSThread.isMainThread || !h || h.owner!=self || h.released || h.invalidated ||
        self.handles[h.sceneIdentifier]!=h || !DXSceneStillRegistered(h.scene)) return NO;
    if (DXObject(h.scene,@selector(clientProcess))!=h.process ||
        DXPID(h.process,@selector(pid))!=h.processIdentifier || !DXBool(h.process,@selector(isRunning)) ||
        ![DXString(DXObject(h.process,@selector(bundleIdentifier))) isEqualToString:h.bundleIdentifier]) return NO;
    if (h.presenter && (DXBool(h.presenter,@selector(isInvalidated)) || DXObject(h.presenter,@selector(scene))!=h.scene)) return NO;
    if (h.presentationManager && DXObject(h.presentationManager,@selector(scene))!=h.scene) return NO;
    return DXObject1(DXMainManager(),@selector(existingSceneHandleForScene:),h.scene)!=nil;
}
- (NSUInteger)ownedResourceCount {
    NSMutableSet *owned=[NSMutableSet setWithArray:self.handles.allValues];
    [owned unionSet:self.recovery];
    return owned.count;
}
- (void)requireUsableContext {
    DXRequire(DXSpringBoard() && !self.isLocked,DXSystemBridgeErrorLocked,@"SpringBoard is locked or lock state unavailable");
    DXRequire(!self.contextLost && !self.restorations && !self.recovery.count && !self.observationError,DXSystemBridgeErrorOwnership,@"Native context changed or restoration in progress; finish recovery first");
    NSString *front=self.frontmostApplicationIdentifier;
    BOOL allowed=NO;
    for (DXSystemSceneHandle *h in self.handles.allValues) if (!h.released && [h.bundleIdentifier isEqualToString:front]) allowed=YES;
    DXRequire(allowed,DXSystemBridgeErrorOwnership,@"Frontmost native application is not a leased target (or unknown)");
}
#include "DXSceneAcquire.inc"
- (void)configurePresenter:(DXSystemSceneHandle *)h frame:(CGRect)frame operation:(DXBridgeOperation *)op {
    Class tc=DXRuntimeClass(@"UIMutableTransformer"), transformClass=DXRuntimeClass(@"UITransform");
    DXRequire(tc && transformClass,DXSystemBridgeErrorUnavailable,@"Native host-coordinate transformer unavailable");
    id transformer=[tc new];
    SEL translation=@selector(translation:);
    CGPoint offset=CGPointMake(-frame.origin.x,-frame.origin.y);
    id transform=((id (*)(id,SEL,CGPoint))DXCheckedIMP(transformClass,translation,"@",@encode(CGPoint)))(transformClass,translation,offset);
    SEL add=@selector(addTransform:reason:);
    ((void (*)(id,SEL,id,id))DXCheckedIMP(transformer,add,"v","@@"))(transformer,add,transform,@"Dynamic Stage X local scene origin");
    __block BOOL accepting=YES, invoked=NO; __block NSError *failure=nil;
    __weak DXBridgeOperation *weakOp=op; __weak DXSystemSceneHandle *weakHandle=h;
    void (^change)(id)=^(id context) {
        if (!accepting || !NSThread.isMainThread || !weakOp || weakOp.finished || weakHandle.released) return;
        @try {
            DXRequire([context isKindOfClass:DXRuntimeClass(@"UIMutableScenePresentationContext")],DXSystemBridgeErrorABI,@"Unexpected mutable presentation context");
            DXCheckedIMP(context,@selector(setHostTransformer:),"v","@");
            DXCheckedIMP(context,@selector(setResizesHostedContext:),"v",@encode(bool));
            DXCheckedIMP(context,@selector(setClippingDisabled:),"v",@encode(bool));
            DXCheckedIMP(context,@selector(setInheritsSecurity:),"v",@encode(bool));
            DXVoid1(context,@selector(setHostTransformer:),transformer);
            DXSetBool(context,@selector(setResizesHostedContext:),true);
            DXSetBool(context,@selector(setClippingDisabled:),false);
            DXSetBool(context,@selector(setInheritsSecurity:),true);
            invoked=YES;
        } @catch (NSException *e) { failure=DXCaught(e); }
    };
    SEL modify=@selector(modifyPresentationContext:);
    ((void (*)(id,SEL,void (^)(id)))DXCheckedIMP(h.presenter,modify,"v","@?"))(h.presenter,modify,change);
    accepting=NO; // A delayed/repeated callback cannot change a stale presenter.
    if (failure) @throw [NSException exceptionWithName:@"DXBridgeFault" reason:nil userInfo:@{@"error":failure}];
    DXRequire(invoked,DXSystemBridgeErrorSystemRejected,@"Presentation-context callback was not synchronous; no delayed mutation allowed");
    DXSetBool(h.presenter,@selector(setVisibilityPropagationEnabled:),true);
}
- (BOOL)nativeEventBindingReady:(DXSystemSceneHandle *)h {
    UIWindow *window=h.hostView.window;
    if (!window || window.screen!=UIScreen.mainScreen || !window.windowScene || window.hidden ||
        !DXBool(window,@selector(_usesWindowServerHitTesting)) || !DXUInt32(window,@selector(_contextId))) return NO;
    NSString *hitArguments=[NSString stringWithFormat:@"%s@@",@encode(CGPoint)];
    DXCheckedIMP(h.hostView,@selector(_hitTest:withEvent:windowServerHitTestWindow:),"@",hitArguments.UTF8String);
    id container=DXObject(h.hostView,@selector(hostContainerView));
    DXCheckedIMP(container,@selector(_hitTest:withEvent:windowServerHitTestWindow:),"@",hitArguments.UTF8String);
    return [self nativeLayerBindingReady:h];
}
- (BOOL)nativeLayerBindingReady:(DXSystemSceneHandle *)h {
    id container=DXObject(h.hostView,@selector(hostContainerView));
    if (![container isKindOfClass:DXRuntimeClass(@"_UISceneLayerHostContainerView")] ||
        DXObject(container,@selector(scene))!=h.scene) return NO;
    NSArray *sceneLayers=DXCollection(DXObject(DXObject(h.scene,@selector(layerManager)),@selector(layers)));
    NSArray *hosted=DXCollection(DXObject(container,@selector(hostedLayers)));
    for (UIView *view in DXCollection(DXObject(container,@selector(_hostViews)))) {
        if (![view isKindOfClass:DXRuntimeClass(@"_UISceneLayerHostView")]) continue;
        id layer=DXObject(view,@selector(sceneLayer));
        if ([sceneLayers indexOfObjectIdenticalTo:layer]==NSNotFound || [hosted indexOfObjectIdenticalTo:layer]==NSNotFound ||
            DXBool(layer,@selector(isKeyboardLayer)) || DXBool(layer,@selector(isKeyboardProxyLayer))) continue;
        unsigned int context=DXUInt32(layer,@selector(contextID));
        if (!context || ![view.layer isKindOfClass:DXRuntimeClass(@"CALayerHost")]) continue;
        if (DXUInt32(view.layer,@selector(contextId))==context) return YES;
    }
    return NO;
}
#include "DXSceneReadinessMethods.inc"
- (void)applyFrame:(CGRect)frame toHandle:(DXSystemSceneHandle *)h completion:(void (^)(NSError *))completion {
    __weak DXSystemSceneHandle *weakHandle=h;
    __block BOOL ownsOperation=NO;
    __block DXBridgeOperation *operation;
    operation=[[DXBridgeOperation alloc] initWithTimeout:2 completion:^(NSError *error) {
        DXSystemSceneHandle *handle=weakHandle;
        if (error && handle && ownsOperation) {
            NSDictionary *snapshot=[self readinessForHandle:handle];
            NSMutableDictionary *info=[error.userInfo mutableCopy]; info[DXSceneReadinessKey]=snapshot;
            error=[NSError errorWithDomain:error.domain code:error.code userInfo:info];
        }
        if (handle.operation==operation) handle.operation=nil;
        operation=nil;
        if (error && ownsOperation && handle.owner==self && !handle.released) {
            [self releaseHandle:handle completion:^(NSError *cleanupError) { completion(DXErrorWithCleanup(error,cleanupError)); }];
        } else completion(error);
    }];
    operation.name=@"apply";
    operation.diagnostics=h.readiness;
    __weak DXBridgeOperation *weakOp=operation;
    [operation start:^{
        [weakOp enterStage:@"eligibility"];
        DXRequire([self ownsLiveHandle:h],DXSystemBridgeErrorStaleHandle,@"Frame update has stale scene/process/owner");
        DXRequire(!h.operation && !self.focusPending,DXSystemBridgeErrorOwnership,@"Handle or input focus is busy");
        [self requireUsableContext];
        DXRequire(isfinite(frame.origin.x) && isfinite(frame.origin.y) && isfinite(frame.size.width) && isfinite(frame.size.height) &&
                  frame.size.width>0 && frame.size.height>0 && CGRectContainsRect(UIScreen.mainScreen.bounds,frame),
                  DXSystemBridgeErrorInvalidGeometry,@"Frame must be finite, nonempty and within main display");
        DXRequire(h.hostView.superview && h.hostView.window && h.hostView.window.screen==UIScreen.mainScreen,
                  DXSystemBridgeErrorEventDelivery,@"Attach own live host to a main-display window before applying geometry");
        h.operation=weakOp; ownsOperation=YES;
        if (h.changedSettings) DXRequire(DXSettingsEqual(h),DXSystemBridgeErrorOwnership,@"Native settings changed since last owned update");
        id settings=DXSettings(h.scene);
        DXCheckedIMP(settings,@selector(mutableCopy),"@",""); id mutable=[settings mutableCopy];
        DXRequire(mutable && mutable!=settings,DXSystemBridgeErrorOwnership,@"Mutable settings copy is not independent");
        DXCheckedIMP(mutable,@selector(setFrame:),"v",@encode(CGRect));
        DXCheckedIMP(mutable,@selector(setBackgrounded:),"v",@encode(bool));
        BOOL hasForeground=DXHasABI(settings,@selector(isForeground),@encode(bool),"");
        if (hasForeground) DXCheckedIMP(mutable,@selector(setForeground:),"v",@encode(bool));
        DXCheckedIMP(h.scene,@selector(updateSettings:withTransitionContext:),"v","@@");
        bool wasActive=DXBool(h.scene,@selector(isActive));
        if (!wasActive) {
            DXCheckedIMP(h.scene,@selector(activateWithTransitionContext:),"v","@");
            DXCheckedIMP(h.scene,@selector(deactivateWithTransitionContext:),"v","@");
        }
        [weakOp enterStage:@"presentation-context"];
        [self configurePresenter:h frame:frame operation:weakOp];
        if (!h.changedSettings) {
            h.originalFrame=DXFrame(settings); h.originalBackgrounded=DXBool(settings,@selector(isBackgrounded));
            h.hasForeground=hasForeground; h.originalForeground=hasForeground ? DXBool(settings,@selector(isForeground)) : false;
        }
        DXSetFrame(mutable,frame); DXSetBool(mutable,@selector(setBackgrounded:),false);
        if (hasForeground) DXSetBool(mutable,@selector(setForeground:),true);
        h.writtenFrame=frame; h.changedSettings=YES; h.interactive=NO;
        [weakOp enterStage:@"settings-submit"];
        if (!wasActive) { h.activatedScene=YES; DXVoid1(h.scene,@selector(activateWithTransitionContext:),nil); }
        DXWriteSettings(h.scene,mutable);
        [weakOp enterStage:@"presenter-activate"];
        DXVoid(h.presenter,@selector(activate));
        [weakOp enterStage:@"readiness"];
        weakOp.progress=^BOOL{
            UIWindow *window=h.hostView.window;
            if (window && h.hostView.superview)
                h.hostView.frame=[h.hostView.superview convertRect:[window convertRect:frame fromWindow:nil] fromView:window];
            weakOp.diagnostics=[self readinessForHandle:h];
            DXRequire([self ownsLiveHandle:h],DXSystemBridgeErrorStaleHandle,@"Scene invalidated during geometry acknowledgement");
            [self requireUsableContext];
            if ([weakOp.diagnostics[@"pending"] count]) return NO;
            h.interactive=YES; return YES;
        };
    }];
}

- (void)requestFocusForScene:(id)scene controller:(id)controller {
    SEL s=@selector(userFocusRequestForScene:reason:completion:);
    /* Callback invoke ABI is not in the dump; pass nil and verify native state instead. */
    ((void (*)(id,SEL,id,id,void (^)(void)))DXCheckedIMP(controller,s,"v","@@@?"))
        (controller,s,scene,@"Dynamic Stage X explicit pane input",nil);
}
- (void)focusHandle:(DXSystemSceneHandle *)h completion:(void (^)(NSError *))completion {
    __block BOOL ownsRequest=NO;
    __block DXBridgeOperation *operation;
    operation=[[DXBridgeOperation alloc] initWithTimeout:1.5 completion:^(NSError *error) {
        if (self.focusOperation==operation) { self.focusOperation=nil; self.focusPending=NO; }
        operation=nil;
        if (error && ownsRequest && h.owner==self && !h.released) {
            [self releaseHandle:h completion:^(NSError *cleanupError) { completion(DXErrorWithCleanup(error,cleanupError)); }];
        } else completion(error);
    }];
    __weak DXBridgeOperation *weakOp=operation;
    [operation start:^{
        DXRequire([self ownsLiveHandle:h] && h.interactive,DXSystemBridgeErrorStaleHandle,@"Focus requires an acknowledged interactive live handle");
        DXRequire(!h.operation && !self.focusPending && !self.nativePending,DXSystemBridgeErrorOwnership,@"Focus/geometry/native transition already in progress");
        for (DXSystemSceneHandle *other in self.handles.allValues)
            DXRequire(!other.operation,DXSystemBridgeErrorOwnership,@"Wait for all scene geometry acknowledgements before focus handoff");
        [self requireUsableContext];
        DXRequire(DXSettingsEqual(h) && DXBool(h.process,@selector(isForeground)) && [self nativeEventBindingReady:h],
                  DXSystemBridgeErrorEventDelivery,@"Native event/foreground authority is no longer held");
        id controller=DXFocusController();
        uint64_t before=DXUInt64(controller,@selector(userFocusRequestGeneration));
        id previous=DXFocusedScene();
        DXRequire(previous!=nil,DXSystemBridgeErrorUnavailable,@"Cannot snapshot authoritative previous focus scene");
        if (self.focusOwner) {
            DXRequire(self.focusObserverController==controller && before==self.focusGeneration &&
                      (previous==self.focusOwner.scene || previous==self.previousFocusScene),
                      DXSystemBridgeErrorOwnership,@"Another native focus request superseded this focus lease");
        } else {
            if (previous==h.scene && self.keyboardFocusProcessIdentifier==h.processIdentifier) return; // No lease/mutation needed.
            self.previousFocusScene=previous;
            self.focusObserverController=controller;
        }
        if (self.focusOwner==h && previous==h.scene) return;
        self.focusPending=YES; self.focusOperation=weakOp; self.focusOwner=h; ownsRequest=YES;
        self.focusGeneration=before;
        @try { [self requestFocusForScene:h.scene controller:controller]; }
        @finally { self.focusGeneration=DXUInt64(controller,@selector(userFocusRequestGeneration)); }
        DXRequire(self.focusGeneration!=before,DXSystemBridgeErrorSystemRejected,@"Native focus request did not advance its generation");
        weakOp.progress=^BOOL{
            DXRequire([self ownsLiveHandle:h],DXSystemBridgeErrorStaleHandle,@"Scene/process invalidated during focus handoff");
            [self requireUsableContext];
            DXRequire(DXFocusController()==controller && DXUInt64(controller,@selector(userFocusRequestGeneration))==self.focusGeneration,
                      DXSystemBridgeErrorOwnership,@"Native user/system focus superseded pending request");
            return DXFocusedScene()==h.scene && self.keyboardFocusProcessIdentifier==h.processIdentifier &&
                DXSettingsEqual(h) && DXBool(h.process,@selector(isForeground)) && [self nativeEventBindingReady:h];
        };
    }];
}
- (NSError *)restoreFocusIfOwnedBy:(DXSystemSceneHandle *)h {
    if (self.focusOwner!=h) return nil;
    @try {
        if (self.isLocked) { self.focusOwner=nil; self.previousFocusScene=nil; return nil; }
        id controller=DXFocusController();
        id current=DXFocusedScene();
        BOOL owned=controller==self.focusObserverController &&
            DXUInt64(controller,@selector(userFocusRequestGeneration))==self.focusGeneration &&
            (current==h.scene || current==self.previousFocusScene);
        if (owned && DXSceneStillRegistered(self.previousFocusScene)) {
            /* A new native request supersedes even a still-pending own focus request. */
            [self requestFocusForScene:self.previousFocusScene controller:controller];
            h.restoreFocusScene=self.previousFocusScene;
            h.restoreFocusGeneration=DXUInt64(controller,@selector(userFocusRequestGeneration));
        } else if (owned) {
            DXThrow(DXSystemBridgeErrorOwnership,@"Previous focus scene expired; no guessed PID or force-focus cleanup");
        }
    } @catch (NSException *e) {
        // Keep the exact lease/previous scene for an explicit retry; do not forget a failed native request.
        return DXCaught(e);
    }
    self.focusOwner=nil; self.previousFocusScene=nil; return nil;
}

- (void)activateNativeApplication:(NSString *)identifier completion:(void (^)(NSError *))completion {
    NSString *bid=[identifier copy]; __block BOOL began=NO;
    DXBridgeOperation *op=[[DXBridgeOperation alloc] initWithTimeout:4 completion:^(NSError *error) {
        if (began) self.nativePending=NO;
        completion(error);
    }];
    __weak DXBridgeOperation *weakOp=op;
    [op start:^{
        DXRequire(DXSpringBoard() && !self.isLocked,DXSystemBridgeErrorLocked,@"Native activation refused while locked");
        DXRequire(!self.handles.count && !self.recovery.count && !self.observationError && !self.nativePending && !self.focusPending && !self.restorations,DXSystemBridgeErrorOwnership,@"Release all scene/focus leases and await restoration before native activation");
        DXRequire(DXString(bid)!=nil && ![bid isEqualToString:@"com.apple.springboard"],DXSystemBridgeErrorNoScene,@"Invalid native application identifier");
        id app=DXObject1(DXShared(@"SBApplicationController",@selector(sharedInstance)),@selector(applicationWithBundleIdentifier:),bid);
        DXRequire(app!=nil,DXSystemBridgeErrorNoScene,@"Application is not registered with SpringBoard");
        id workspace=DXWorkspace();
        SEL create=@selector(createRequestForApplicationActivation:options:);
        DXCheckedIMP(workspace,@selector(executeTransitionRequest:),@encode(bool),"@");
        id request=((id (*)(id,SEL,id,unsigned long long))DXCheckedIMP(workspace,create,"@","@Q"))(workspace,create,app,0);
        DXRequire(request!=nil,DXSystemBridgeErrorSystemRejected,@"Native workspace did not create activation request");
        self.nativePending=YES; began=YES;
        SEL execute=@selector(executeTransitionRequest:);
        DXRequire(((bool (*)(id,SEL,id))DXCheckedIMP(workspace,execute,@encode(bool),"@"))(workspace,execute,request),
                  DXSystemBridgeErrorSystemRejected,@"Native workspace rejected activation request");
        weakOp.progress=^BOOL{
            DXRequire(!self.isLocked,DXSystemBridgeErrorLocked,@"Locked during native activation");
            if (![self.frontmostApplicationIdentifier isEqualToString:bid]) return NO;
            id scene=nil;
            @try { scene=[self uniqueSceneForIdentifier:bid]; }
            @catch (NSException *e) {
                NSError *error=DXCaught(e);
                if (error.code==DXSystemBridgeErrorNoScene) return NO;
                @throw;
            }
            id process=DXObject(scene,@selector(clientProcess));
            return DXSceneStillRegistered(scene) && DXBool(scene,@selector(isActive)) &&
                DXBool(process,@selector(isRunning)) && DXBool(process,@selector(isForeground)) &&
                !DXBool(DXSettings(scene),@selector(isBackgrounded));
        };
    }];
}

#include "DXSceneRecovery.inc"

- (void)postFocusChange {
    if (!self.handles.count) return;
    @try {
        id scene=DXFocusedScene();
        DXSystemSceneHandle *handle=nil;
        for (DXSystemSceneHandle *candidate in self.handles.allValues) if (candidate.scene==scene && candidate.valid) handle=candidate;
        NSMutableDictionary *info=[NSMutableDictionary dictionary];
        if (scene) {
            NSString *sid=DXString(DXObject(scene,@selector(identifier)));
            id process=DXObject(scene,@selector(clientProcess));
            NSString *bid=DXString(DXObject(process,@selector(bundleIdentifier)));
            if (sid) info[@"sceneIdentifier"]=sid;
            if (bid) info[@"bundleIdentifier"]=bid;
            info[@"processIdentifier"]=@(DXPID(process,@selector(pid)));
        }
        [NSNotificationCenter.defaultCenter postNotificationName:DXSystemKeyboardFocusChangedNotification object:handle userInfo:info];
    } @catch (__unused NSException *e) {
        [NSNotificationCenter.defaultCenter postNotificationName:DXSystemKeyboardFocusChangedNotification object:nil];
    }
}
- (void)keyboardFocusController:(id)controller externalSceneDidAcquireFocus:(id)scene {
    (void)scene;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { if (controller==DXFocusController()) [self postFocusChange]; } @catch (__unused NSException *e) { }
    });
}
- (void)keyboardFocusController:(id)controller didUpdateWindowSceneWithFocusFrom:(id)oldScene to:(id)newScene {
    (void)oldScene; (void)newScene;
    [self keyboardFocusController:controller externalSceneDidAcquireFocus:nil];
}
- (void)processManager:(id)manager didAddProcess:(id)process { (void)manager; (void)process; }
- (void)processManager:(id)manager didRemoveProcess:(id)process {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (manager!=self.processObserverManager) return;
        for (DXSystemSceneHandle *h in [self.handles.allValues copy]) if (h.process==process) [self invalidateHandle:h];
    });
}
- (void)invalidateHandle:(DXSystemSceneHandle *)h {
    if (!NSThread.isMainThread || h.owner!=self || h.released || h.invalidated || self.handles[h.sceneIdentifier]!=h) return;
    h.invalidated=YES; h.interactive=NO; h.hostView.userInteractionEnabled=NO;
    [NSNotificationCenter.defaultCenter postNotificationName:DXSystemSceneInvalidatedNotification object:h];
    [self releaseHandle:h completion:^(__unused NSError *error) { }];
}
- (void)loseContext {
    if (self.contextLost || !self.handles.count) return;
    self.contextLost=YES;
    NSArray *handles=[self.handles.allValues copy];
    for (DXSystemSceneHandle *h in handles) { h.invalidated=YES; h.interactive=NO; h.hostView.userInteractionEnabled=NO; }
    [NSNotificationCenter.defaultCenter postNotificationName:DXSystemSceneInvalidatedNotification object:nil];
    for (DXSystemSceneHandle *h in handles) [self releaseHandle:h completion:^(__unused NSError *error) { }];
}
- (void)beginObserving {
    if (!self.processObserverManager) {
        @try {
            DXRequire(DXProtocolABI(@"FBProcessManagerObserver",@selector(processManager:didAddProcess:),"v@:@@",YES) &&
                      DXProtocolABI(@"FBProcessManagerObserver",@selector(processManager:didRemoveProcess:),"v@:@@",YES),
                      DXSystemBridgeErrorABI,@"FBProcessManagerObserver callback ABI unavailable");
            id manager=DXShared(@"FBProcessManager",@selector(sharedInstance));
            DXCheckedIMP(manager,@selector(removeObserver:),"v","@");
            class_addProtocol(DXSystemBridge.class,DXRuntimeProtocol(@"FBProcessManagerObserver"));
            self.processObserverManager=manager; DXVoid1(manager,@selector(addObserver:),self);
        } @catch (__unused NSException *e) { /* Active watchdog checks exact process object/PID as fallback. */ }
    }
    if (!self.focusObserverToken) {
        @try {
            DXRequire(DXProtocolABI(@"SBWorkspaceKeyboardFocusControllerObserver",@selector(keyboardFocusController:externalSceneDidAcquireFocus:),"v@:@@",YES) &&
                      DXProtocolABI(@"SBWorkspaceKeyboardFocusControllerObserver",@selector(keyboardFocusController:didUpdateWindowSceneWithFocusFrom:to:),"v@:@@@",NO),
                      DXSystemBridgeErrorABI,@"Native keyboard-focus observer callback ABI unavailable");
            id controller=DXFocusController();
            class_addProtocol(DXSystemBridge.class,DXRuntimeProtocol(@"SBWorkspaceKeyboardFocusControllerObserver"));
            id token=DXObject1(controller,@selector(addKeyboardFocusObserver:),self);
            // Retain even an unknown token once: never repeatedly register or guess its teardown.
            if (token) { self.focusObserverToken=token; self.focusObserverController=controller; }
        } @catch (__unused NSException *e) { /* Query remains authoritative; no fabricated keyboard notifications. */ }
    }
    if (self.watchdog) return;
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    self.watchdog=timer;
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,40*NSEC_PER_MSEC);
    __weak DXSystemBridge *weakSelf=self;
    __block NSString *lastFocus=nil;
    dispatch_source_set_event_handler(timer, ^{
        DXSystemBridge *bridge=weakSelf; if (!bridge || !bridge.handles.count) return;
        @try {
            NSString *front=bridge.frontmostApplicationIdentifier;
            BOOL allowed=NO;
            for (DXSystemSceneHandle *h in bridge.handles.allValues) if ([h.bundleIdentifier isEqualToString:front]) allowed=YES;
            // Preparation may discover both scenes before applying; context is required once interactive.
            BOOL anyInteractive=NO;
            for (DXSystemSceneHandle *h in bridge.handles.allValues) if (h.interactive) anyInteractive=YES;
            if (bridge.isLocked || (anyInteractive && !allowed)) { [bridge loseContext]; return; }
            for (DXSystemSceneHandle *h in [bridge.handles.allValues copy]) {
                if (![bridge ownsLiveHandle:h]) { [bridge invalidateHandle:h]; continue; }
                if (h.interactive && !h.operation && !bridge.focusPending &&
                    (!DXSettingsEqual(h) || !DXBool(h.process,@selector(isForeground)) || ![bridge nativeEventBindingReady:h])) [bridge invalidateHandle:h];
            }
            id focus=DXFocusedScene(); NSString *identity=focus ? DXString(DXObject(focus,@selector(identifier))) : @"";
            if (![lastFocus isEqualToString:identity]) { lastFocus=[identity copy]; [bridge postFocusChange]; }
        } @catch (__unused NSException *e) { [bridge loseContext]; }
    });
    dispatch_resume(timer);
}
- (NSError *)endObserving {
    NSError *failure=nil;
    @try {
        if (self.watchdog) { dispatch_source_cancel(self.watchdog); self.watchdog=nil; }
    } @catch (NSException *e) { failure=DXCleanupCaught(e,@"stop-watchdog"); }
    @try {
        if (self.focusObserverToken) {
            DXCheckpoint(@"release.focus-observer",self.focusObserverToken);
            DXVoid(self.focusObserverToken,@selector(invalidate)); self.focusObserverToken=nil;
        }
    } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"remove-focus-observer")); }
    if (!self.focusObserverToken && !self.focusOwner) self.focusObserverController=nil;
    @try {
        if (self.processObserverManager) {
            DXCheckpoint(@"release.process-observer",self.processObserverManager);
            DXVoid1(self.processObserverManager,@selector(removeObserver:),self); self.processObserverManager=nil;
        }
    } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"remove-process-observer")); }
    // Retain exact failed removal targets (one each), block acquisition until explicit retry.
    self.observationError=failure;
    return failure;
}

- (NSDictionary<NSString *,id> *)capabilityReport {
    if (!NSThread.isMainThread) return @{@"status":@"off-main",@"runtimeVerified":@NO};
    struct { const char *cls, *selector, *result, *args; BOOL classMethod; } entries[]={
        {"SBApplicationController","sharedInstance","@","",YES},
        {"SBApplicationController","allApplications","@","",NO},
        {"SpringBoard","_accessibilityFrontMostApplication","@","",NO},
        {"FBSceneManager","sharedInstance","@","",YES},
        {"FBSceneManager","sceneWithIdentifier:","@","@",NO},
        {"SBSceneManagerCoordinator","mainDisplaySceneManager","@","",YES},
        {"SBSceneManager","allScenes","@","",NO},
        {"SBSceneManager","existingSceneHandleForScene:","@","@",NO},
        {"UIScenePresentationManager","_initWithScene:","@","@",NO},
        {"UIScenePresentationManager","createPresenterWithIdentifier:","@","@",NO},
        {"_UIScenePresenter","activate","v","",NO},
        {"_UIScenePresenter","deactivate","v","",NO},
        {"_UIScenePresenter","invalidate","v","",NO},
        {"_UIScenePresenter","isHosting","B","",NO},
        {"_UIScenePresenter","modifyPresentationContext:","v","@?",NO},
        {"_UIScenePresentationView","hostContainerView","@","",NO},
        {"_UISceneLayerHostContainerView","_hostViews","@","",NO},
        {"FBScene","updateSettings:withTransitionContext:","v","@@",NO},
        {"FBScene","isActive","B","",NO},
        {"FBScene","isValid","B","",NO},
        {"FBProcess","isForeground","B","",NO},
        {"SBMainWorkspace","keyboardFocusController","@","",NO},
        {"SBWorkspaceKeyboardFocusController","sceneWithFocusIncludingSpringBoard","@","",NO},
        {"SBWorkspaceKeyboardFocusController","userFocusRequestForScene:reason:completion:","v","@@@?",NO},
        {"SBWorkspaceKeyboardFocusController","userFocusRequestGeneration","Q","",NO},
        {"SBMainWorkspace","createRequestForApplicationActivation:options:","@","@Q",NO},
        {"SBMainWorkspace","executeTransitionRequest:","B","@",NO},
        {"SBLockScreenManager","sharedInstance","@","",YES},
        {"SBLockScreenManager","isUILocked","B","",NO},
        {"UIWindow","_usesWindowServerHitTesting","B","",NO},
        {"UIWindow","_contextId","I","",NO},
        {"CALayerHost","contextId","I","",NO},
    };
    NSMutableArray *checks=[NSMutableArray array]; BOOL matches=DXSpringBoard();
    for (NSUInteger i=0;i<sizeof(entries)/sizeof(entries[0]);i++) {
        Class cls=objc_getClass(entries[i].cls); if (entries[i].classMethod && cls) cls=object_getClass(cls);
        Method method=cls ? class_getInstanceMethod(cls,sel_registerName(entries[i].selector)) : NULL;
        NSString *expected=[NSString stringWithFormat:@"%s@:%s",entries[i].result,entries[i].args];
        const char *actual=method ? method_getTypeEncoding(method) : NULL;
        BOOL equal=actual && DXABIEncodingMatches(actual,expected.UTF8String); matches=matches && equal;
        [checks addObject:@{@"class":@(entries[i].cls),@"selector":@(entries[i].selector),@"classMethod":@(entries[i].classMethod),
                           @"expected":expected,@"actual":actual ? @(actual) : @"missing",@"abiMatches":@(equal)}];
    }
    NSUInteger interactive=0;
    for (DXSystemSceneHandle *h in self.handles.allValues) if (h.interactive && h.valid) interactive++;
    return @{@"adapter":@"native UIKit scene presenter + FrontBoard settings + workspace focus (source candidate)",
             @"minimumDeployment":@"15.0",@"maximumOSGate":@NO,@"runtimeVerified":@NO,
             @"abiCandidatesReady":@(matches),@"abiChecks":checks,@"activeLeases":@(self.handles.count),
             @"stagingLeaseLimit":@3,@"recoveryLeases":@(self.recovery.count),
             @"totalOwnedResources":@(self.handles.count+self.recovery.count),
             @"observationRecoveryPending":@(self.observationError!=nil),
             @"acknowledgedInteractiveHandles":@(interactive),@"restorationsPending":@(self.restorations),
             @"eventDelivery":@"Requires visible window-server-hit-testing context, matching native live host/layers and foreground process; touch receipt is NOT proven by this report",
             @"keyboardFocusObserverRegistered":@(self.focusObserverToken!=nil),@"processObserverRegistered":@(self.processObserverManager!=nil),
             @"sceneInvalidationObserver":@"Per-scene addObserver with runtime protocol encoding check; native delegate is never replaced",
             @"keyboardFrameAuthority":@"No verified global cross-process keyboard geometry subscription in this adapter; SB UIKit keyboard frames alone are insufficient evidence",
             @"noScenePolicy":@"Release all -> native activate/await actual scene -> acquire both -> attach -> apply -> focus"};
}
@end
