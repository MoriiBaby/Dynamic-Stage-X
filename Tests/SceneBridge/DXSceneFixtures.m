#import "DXSceneFixtures.h"

static NSString *DXFault;
static NSString *DXOneShotFault;
static void (^DXBeforeSettingsWrite)(void);
static BOOL DXLate;
static NSMutableArray *DXEvents;
static DXBridgeOperation *DXPending;
static void (^DXLateBlock)(id);
static id DXLateObject;
@implementation DXFixtureControl
+ (NSString *)fault { return DXFault; }
+ (void)setFault:(NSString *)value { DXFault=value; }
+ (NSString *)oneShotFault { return DXOneShotFault; }
+ (void)setOneShotFault:(NSString *)value { DXOneShotFault=value; }
+ (void (^)(void))beforeSettingsWrite { return DXBeforeSettingsWrite; }
+ (void)setBeforeSettingsWrite:(void (^)(void))value { DXBeforeSettingsWrite=[value copy]; }
+ (BOOL)lateContext { return DXLate; }
+ (void)setLateContext:(BOOL)value { DXLate=value; }
+ (NSMutableArray *)events { if (!DXEvents) DXEvents=[NSMutableArray array]; return DXEvents; }
+ (void)setEvents:(NSMutableArray *)value { DXEvents=value; }
+ (DXBridgeOperation *)pending { return DXPending; }
+ (void)setPending:(DXBridgeOperation *)value { DXPending=value; }
+ (void (^)(id))lateBlock { return DXLateBlock; }
+ (void)setLateBlock:(void (^)(id))value { DXLateBlock=[value copy]; }
+ (id)lateObject { return DXLateObject; }
+ (void)setLateObject:(id)value { DXLateObject=value; }
@end
void DXFixtureFault(NSString *stage) {
    [DXFixtureControl.events addObject:stage];
    NSMutableArray *once=[[DXFixtureControl.oneShotFault componentsSeparatedByString:@","] mutableCopy];
    BOOL consume=[once containsObject:stage];
    if (consume) {
        [once removeObject:stage]; DXFixtureControl.oneShotFault=[once componentsJoinedByString:@","];
    }
    if (consume || [[DXFixtureControl.fault componentsSeparatedByString:@","] containsObject:stage])
        @throw [NSException exceptionWithName:@"DXInjectedFault" reason:@"discarded fixture exception payload" userInfo:nil];
}
void DXSceneBridgeTestingCheckpoint(NSString *stage, id object) {
    DXFixtureFault(stage);
    if ([stage isEqualToString:@"acquire.pending"] && DXFixtureControl.pending) {
        DXBridgeOperation *op=object;
        op.progress=^BOOL{ return NO; };
        DXFixtureControl.pending=op;
    }
}
BOOL DXSceneBridgeTestingSpringBoard(void) { return YES; }
@implementation DXFixtureSettings
- (id)mutableCopyWithZone:(NSZone *)zone {
    DXFixtureSettings *copy=[[DXFixtureSettings allocWithZone:zone] init];
    copy.frame=self.frame; copy.foreground=self.foreground; copy.backgrounded=self.backgrounded; return copy;
}
@end
@implementation DXFixtureProcess @end
@implementation DXFixtureScene
- (void)addObserver:(id)observer { DXFixtureFault(@"scene.addObserver"); [self.observers addObject:observer]; }
- (void)removeObserver:(id)observer { DXFixtureFault(@"scene.removeObserver"); [self.observers removeObject:observer]; }
- (void)updateSettings:(id)settings withTransitionContext:(id)context {
    if (DXFixtureControl.beforeSettingsWrite) DXFixtureControl.beforeSettingsWrite();
    DXFixtureFault(@"scene.updateSettings"); self.settings=settings;
}
- (void)activateWithTransitionContext:(id)context { DXFixtureFault(@"scene.activate"); self.active=true; }
- (void)deactivateWithTransitionContext:(id)context { DXFixtureFault(@"scene.deactivate"); self.active=false; }
@end
@implementation DXFixtureRegistry
+ (instancetype)sharedInstance { static id value; static dispatch_once_t once; dispatch_once(&once,^{ value=[self new]; [value setScenes:[NSMutableDictionary dictionary]]; }); return value; }
+ (instancetype)mainDisplaySceneManager { return [self sharedInstance]; }
- (id)sceneWithIdentifier:(NSString *)identifier { return self.scenes[identifier]; }
- (NSArray *)allScenes { return self.scenes.allValues; }
- (id)existingSceneHandleForScene:(id)scene { return [self.scenes.allValues containsObject:scene] ? scene : nil; }
@end
@interface DXFixtureLayer : NSObject
- (bool)isKeyboardLayer;
- (bool)isKeyboardProxyLayer;
- (unsigned int)contextID;
@end
@implementation DXFixtureLayer
- (bool)isKeyboardLayer { return false; }
- (bool)isKeyboardProxyLayer { return false; }
- (unsigned int)contextID { return 91; }
@end
@interface DXFixtureCAHost : CALayer
- (unsigned int)contextId;
@end
@implementation DXFixtureCAHost
- (unsigned int)contextId { return 91; }
@end
@interface DXFixtureLayerHost : UIView
@property (nonatomic, strong) id sceneLayer;
@end
@implementation DXFixtureLayerHost
+ (Class)layerClass { return DXFixtureCAHost.class; }
@end
@interface DXFixtureLayers : NSObject
@property (nonatomic, strong) NSArray *layers;
@end
@implementation DXFixtureLayers @end
@interface DXFixtureContainer : UIView
@property (nonatomic, strong) id scene;
@property (nonatomic, strong) NSArray *hostedLayers;
@property (nonatomic, strong) NSArray *fixtureViews;
- (NSArray *)_hostViews;
- (id)_hitTest:(CGPoint)point withEvent:(id)event windowServerHitTestWindow:(id)window;
@end
@implementation DXFixtureContainer
- (NSArray *)_hostViews { return self.fixtureViews; }
- (id)_hitTest:(CGPoint)point withEvent:(id)event windowServerHitTestWindow:(id)window { return self; }
@end
@implementation DXFixtureView
- (id)_hitTest:(CGPoint)point withEvent:(id)event windowServerHitTestWindow:(id)window { return self; }
- (void)removeFromSuperview { DXFixtureFault(@"host.remove"); [super removeFromSuperview]; }
@end
@interface DXFixtureContext : NSObject
@property (nonatomic, strong) id hostTransformer;
@property (nonatomic) bool resizesHostedContext;
@property (nonatomic) bool clippingDisabled;
@property (nonatomic) bool inheritsSecurity;
@end
@implementation DXFixtureContext
- (void)setHostTransformer:(id)value { DXFixtureFault(@"context.setTransformer"); _hostTransformer=value; }
@end
@implementation DXFixturePresenter
- (void)activate { DXFixtureFault(@"presenter.activate"); self.active=true; self.hosting=true; }
- (void)deactivate { DXFixtureFault(@"presenter.deactivate"); NSAssert(!self.presentationView.superview,@"Host must detach first"); self.active=false; self.hosting=false; }
- (void)invalidate { DXFixtureFault(@"presenter.invalidate"); NSAssert(!self.presentationView.superview,@"Host must detach first"); self.invalidated=true; }
- (void)modifyPresentationContext:(void (^)(id))change {
    DXFixtureContext *context=[DXFixtureContext new];
    if (DXFixtureControl.lateContext) { DXFixtureControl.lateBlock=change; DXFixtureControl.lateObject=context; }
    else change(context);
}
@end
@implementation DXFixturePresentationManager
- (instancetype)_initWithScene:(id)scene { if ((self=[super init])) _scene=scene; return self; }
- (id)createPresenterWithIdentifier:(NSString *)identifier {
    DXFixtureFault(@"manager.createPresenter");
    DXFixturePresenter *p=[DXFixturePresenter new]; p.scene=self.scene; p.presentationView=[DXFixtureView new];
    DXFixtureContainer *container=[DXFixtureContainer new]; container.scene=self.scene;
    DXFixtureLayer *layer=[DXFixtureLayer new]; DXFixtureLayerHost *host=[DXFixtureLayerHost new]; host.sceneLayer=layer;
    container.hostedLayers=@[layer]; container.fixtureViews=@[host];
    DXFixtureLayers *layers=[DXFixtureLayers new]; layers.layers=@[layer]; self.scene.layerManager=layers;
    p.presentationView.hostContainerView=container; return p;
}
@end
@interface DXFixtureTransformer : NSObject
- (void)addTransform:(id)transform reason:(id)reason;
+ (id)translation:(CGPoint)point;
@end
@implementation DXFixtureTransformer
- (void)addTransform:(id)transform reason:(id)reason { }
+ (id)translation:(CGPoint)point { return [self new]; }
@end
@implementation DXFixtureWindow
- (bool)_usesWindowServerHitTesting { return self.fixtureHitTesting; }
- (unsigned int)_contextId { return 17; }
@end
@implementation DXHarnessBridge
- (NSString *)frontmostApplicationIdentifier { return self.fixtureFrontmost; }
@end

@interface DXFixtureLock : NSObject
+ (instancetype)sharedInstance;
- (bool)isUILocked;
@end
@implementation DXFixtureLock
+ (instancetype)sharedInstance { static id value; static dispatch_once_t once; dispatch_once(&once,^{ value=[self new]; }); return value; }
- (bool)isUILocked { return false; }
@end
@interface DXFixtureToken : NSObject
- (void)invalidate;
@end
@implementation DXFixtureToken
- (void)invalidate { DXFixtureFault(@"focusToken.invalidate"); }
@end
@interface DXFixtureFocus : NSObject
@property (nonatomic, strong) id sceneWithFocusIncludingSpringBoard;
@property (nonatomic) unsigned long long userFocusRequestGeneration;
- (id)addKeyboardFocusObserver:(id)observer;
- (void)userFocusRequestForScene:(id)scene reason:(id)reason completion:(void (^)(void))completion;
@end
@implementation DXFixtureFocus
- (id)addKeyboardFocusObserver:(id)observer { return [DXFixtureToken new]; }
- (void)userFocusRequestForScene:(id)scene reason:(id)reason completion:(void (^)(void))completion { self.userFocusRequestGeneration+=1; self.sceneWithFocusIncludingSpringBoard=scene; }
@end
@interface DXFixtureWorkspace : NSObject
@property (nonatomic, strong) DXFixtureFocus *keyboardFocusController;
+ (instancetype)sharedInstance;
@end
@implementation DXFixtureWorkspace
+ (instancetype)sharedInstance { static id value; static dispatch_once_t once; dispatch_once(&once,^{ value=[self new]; [value setKeyboardFocusController:[DXFixtureFocus new]]; }); return value; }
@end
@interface DXFixtureProcessManager : NSObject
+ (instancetype)sharedInstance;
- (void)addObserver:(id)observer;
- (void)removeObserver:(id)observer;
@end
@implementation DXFixtureProcessManager
+ (instancetype)sharedInstance { static id value; static dispatch_once_t once; dispatch_once(&once,^{ value=[self new]; }); return value; }
- (void)addObserver:(id)observer { }
- (void)removeObserver:(id)observer { DXFixtureFault(@"process.removeObserver"); }
@end
Class DXSceneBridgeTestingClass(NSString *name) {
    return @{@"FBSceneManager":DXFixtureRegistry.class,@"SBSceneManagerCoordinator":DXFixtureRegistry.class,
             @"SBLockScreenManager":DXFixtureLock.class,@"SBMainWorkspace":DXFixtureWorkspace.class,
             @"FBProcessManager":DXFixtureProcessManager.class,
             @"UIScenePresentationManager":DXFixturePresentationManager.class,
             @"_UIScenePresentationView":DXFixtureView.class,@"_UISceneLayerHostContainerView":DXFixtureContainer.class,
             @"_UISceneLayerHostView":DXFixtureLayerHost.class,@"CALayerHost":DXFixtureCAHost.class,
             @"UITransform":DXFixtureTransformer.class,@"UIMutableTransformer":DXFixtureTransformer.class,
             @"UIMutableScenePresentationContext":DXFixtureContext.class}[name];
}
Protocol *DXSceneBridgeTestingProtocol(NSString *name) {
    if ([name isEqualToString:@"UIApplicationSceneSettings"]) return @protocol(DXFixtureSettingsProtocol);
    if ([name isEqualToString:@"FBSceneObserver"]) return @protocol(DXFixtureObserver);
    if ([name isEqualToString:@"FBProcessManagerObserver"]) return @protocol(DXFixtureProcessObserver);
    if ([name isEqualToString:@"SBWorkspaceKeyboardFocusControllerObserver"]) return @protocol(DXFixtureFocusObserver);
    return nil;
}
DXFixtureScene *DXFixtureCreateScene(NSUInteger number) {
    DXFixtureScene *scene=[DXFixtureScene new]; scene.identifier=[NSString stringWithFormat:@"fixture.scene.%lu",(unsigned long)number];
    scene.valid=true; scene.active=true; scene.observers=[NSHashTable weakObjectsHashTable];
    scene.clientProcess=[DXFixtureProcess new]; scene.clientProcess.bundleIdentifier=[NSString stringWithFormat:@"fixture.app.%lu",(unsigned long)number];
    scene.clientProcess.pid=(int)(100+number); scene.clientProcess.running=true; scene.clientProcess.foreground=true;
    scene.settings=[DXFixtureSettings new]; scene.settings.frame=UIScreen.mainScreen.bounds; scene.settings.backgrounded=true;
    [DXFixtureRegistry sharedInstance].scenes[scene.identifier]=scene; return scene;
}
void DXFixtureReset(void) {
    DXFixtureControl.fault=nil; DXFixtureControl.oneShotFault=nil; DXFixtureControl.beforeSettingsWrite=nil; DXFixtureControl.pending=nil; DXFixtureControl.lateContext=NO;
    DXFixtureControl.lateBlock=nil; DXFixtureControl.lateObject=nil; DXFixtureControl.events=[NSMutableArray array];
    [[DXFixtureRegistry sharedInstance].scenes removeAllObjects];
    [DXFixtureWorkspace sharedInstance].keyboardFocusController.sceneWithFocusIncludingSpringBoard=nil;
}
