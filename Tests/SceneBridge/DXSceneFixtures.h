#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "DXSystemBridge.h"
#import "DXRuntime.h"

@protocol DXFixtureSettingsProtocol <NSObject> @end
@protocol DXFixtureObserver <NSObject>
@optional
- (void)sceneDidInvalidate:(id)scene;
@end
@protocol DXFixtureProcessObserver <NSObject>
- (void)processManager:(id)manager didAddProcess:(id)process;
- (void)processManager:(id)manager didRemoveProcess:(id)process;
@end
@protocol DXFixtureFocusObserver <NSObject>
- (void)keyboardFocusController:(id)controller externalSceneDidAcquireFocus:(id)scene;
@optional
- (void)keyboardFocusController:(id)controller didUpdateWindowSceneWithFocusFrom:(id)oldScene to:(id)newScene;
@end

@interface DXFixtureControl : NSObject
@property (class, nonatomic, strong) NSString *fault;
@property (class, nonatomic, strong) NSString *oneShotFault;
@property (class, nonatomic, copy) void (^beforeSettingsWrite)(void);
@property (class, nonatomic) BOOL lateContext;
@property (class, nonatomic, strong) NSMutableArray<NSString *> *events;
@property (class, nonatomic, strong) DXBridgeOperation *pending;
@property (class, nonatomic, copy) void (^lateBlock)(id);
@property (class, nonatomic, strong) id lateObject;
@end
@interface DXFixtureSettings : NSObject <NSMutableCopying, DXFixtureSettingsProtocol>
@property (nonatomic) CGRect frame;
@property (nonatomic, getter=isForeground) bool foreground;
@property (nonatomic, getter=isBackgrounded) bool backgrounded;
@end
@interface DXFixtureProcess : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic) int pid;
@property (nonatomic, getter=isRunning) bool running;
@property (nonatomic, getter=isForeground) bool foreground;
@end
@interface DXFixtureScene : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) DXFixtureSettings *settings;
@property (nonatomic, strong) DXFixtureProcess *clientProcess;
@property (nonatomic, getter=isValid) bool valid;
@property (nonatomic, getter=isActive) bool active;
@property (nonatomic, strong) id layerManager;
@property (nonatomic, strong) NSHashTable *observers;
- (void)addObserver:(id)observer;
- (void)removeObserver:(id)observer;
- (void)updateSettings:(id)settings withTransitionContext:(id)context;
- (void)activateWithTransitionContext:(id)context;
- (void)deactivateWithTransitionContext:(id)context;
@end
@interface DXFixtureRegistry : NSObject
@property (nonatomic, strong) NSMutableDictionary *scenes;
+ (instancetype)sharedInstance;
+ (instancetype)mainDisplaySceneManager;
- (id)sceneWithIdentifier:(NSString *)identifier;
- (NSArray *)allScenes;
- (id)existingSceneHandleForScene:(id)scene;
@end
@interface DXFixtureView : UIView
@property (nonatomic, strong) id hostContainerView;
@end
@interface DXFixturePresenter : NSObject
@property (nonatomic, strong) DXFixtureScene *scene;
@property (nonatomic, strong) DXFixtureView *presentationView;
@property (nonatomic, getter=isActive) bool active;
@property (nonatomic, getter=isHosting) bool hosting;
@property (nonatomic, getter=isInvalidated) bool invalidated;
@property (nonatomic) bool visibilityPropagationEnabled;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
- (void)modifyPresentationContext:(void (^)(id))change;
@end
@interface DXFixturePresentationManager : NSObject
@property (nonatomic, strong) DXFixtureScene *scene;
- (instancetype)_initWithScene:(id)scene __attribute__((objc_method_family(init)));
- (id)createPresenterWithIdentifier:(NSString *)identifier;
@end
// Only frontmost identity is substituted. Cleanup, apply, acquire and releaseAll are inherited unchanged.
@interface DXHarnessBridge : DXSystemBridge
@property (nonatomic, copy) NSString *fixtureFrontmost;
@end
@interface DXSystemBridge (DXHarnessPrivateInitializer)
- (instancetype)initPrivate;
@end
FOUNDATION_EXPORT DXFixtureScene *DXFixtureCreateScene(NSUInteger number);
FOUNDATION_EXPORT void DXFixtureReset(void);
FOUNDATION_EXPORT void DXFixtureFault(NSString *stage);
@interface DXFixtureWindow : UIWindow
@property (nonatomic) bool fixtureHitTesting;
- (bool)_usesWindowServerHitTesting;
- (unsigned int)_contextId;
@end
