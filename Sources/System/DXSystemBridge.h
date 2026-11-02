#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const DXSystemBridgeErrorDomain;
/// Main queue, object is the invalidated DXSystemSceneHandle (or nil for context loss).
FOUNDATION_EXPORT NSNotificationName const DXSystemSceneInvalidatedNotification;
/// Main queue; authoritative focus identity changed. No keyboard text/frame is included.
FOUNDATION_EXPORT NSNotificationName const DXSystemKeyboardFocusChangedNotification;

typedef NS_ERROR_ENUM(DXSystemBridgeErrorDomain, DXSystemBridgeError) {
    DXSystemBridgeErrorUnavailable = 1,
    DXSystemBridgeErrorABI = 2,
    DXSystemBridgeErrorLocked = 3,
    DXSystemBridgeErrorNoScene = 4,
    DXSystemBridgeErrorAmbiguousScene = 5,
    DXSystemBridgeErrorStaleHandle = 6,
    DXSystemBridgeErrorOwnership = 7,
    DXSystemBridgeErrorTimeout = 8,
    DXSystemBridgeErrorInvalidGeometry = 9,
    DXSystemBridgeErrorSystemRejected = 10,
    DXSystemBridgeErrorEventDelivery = 11,
    DXSystemBridgeErrorCancelled = 12,
};

@interface DXApplicationRecord : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, nullable) UIImage *icon;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface DXSystemSceneHandle : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *sceneIdentifier;
@property (nonatomic, readonly) pid_t processIdentifier;
/// Own real native remote-scene presentation; insert this view without reparenting native views.
@property (nonatomic, readonly) UIView *hostView;
/// Main-thread query: checks scene identity, process, presenter and registry ownership again.
@property (nonatomic, readonly, getter=isValid) BOOL valid;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// SpringBoard only. Private ABI candidates, not an assertion of device/runtime verification.
/// Async API finishes once on main when the main queue is runnable; no hard realtime guarantee.
/// Queued expired mutations are refused; expired release still attempts best-effort cleanup.
/// Synchronous queries are main-thread-only (off-main returns nil/[]/0/locked).
@interface DXSystemBridge : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)sharedBridge NS_SWIFT_NAME(shared());
- (NSDictionary<NSString *, id> *)capabilityReport;
- (nullable NSString *)frontmostApplicationIdentifier;
- (NSArray<DXApplicationRecord *> *)applications;
/// Only one eligible main-display application scene is accepted; no arbitrary first-scene choice.
/// Existing live scene required. Use activateNative first to launch one through the OS.
- (void)acquireSceneForBundleIdentifier:(NSString *)identifier
                           completion:(void (^)(DXSystemSceneHandle * _Nullable, NSError * _Nullable))completion
    NS_SWIFT_NAME(acquireScene(bundleIdentifier:completion:));
/// Global main-display coordinates, in points. Apply after hostView is attached to a window.
/// Acknowledges read-back settings + native remote hit-test binding, not observed user touches.
- (void)applyFrame:(CGRect)frame toHandle:(DXSystemSceneHandle *)handle
       completion:(void (^)(NSError * _Nullable))completion
    NS_SWIFT_NAME(apply(frame:to:completion:));
/// Requests the native workspace focus path and confirms scene identity (not just PID).
- (void)focusHandle:(DXSystemSceneHandle *)handle completion:(void (^)(NSError * _Nullable))completion
    NS_SWIFT_NAME(focus(_:completion:));
/// Idempotent for already released own handles. Restores only still-owned changed fields.
- (void)releaseHandle:(DXSystemSceneHandle *)handle completion:(void (^)(NSError * _Nullable))completion
    NS_SWIFT_NAME(release(_:completion:));
/// Refuses while any own scene lease is active; release both handles before full-screen fallback.
- (void)activateNativeApplication:(NSString *)identifier completion:(void (^)(NSError * _Nullable))completion
    NS_SWIFT_NAME(activateNative(bundleIdentifier:completion:));
- (pid_t)keyboardFocusProcessIdentifier;
/// Capability unavailable, non-SpringBoard or off-main -> YES. Never tries to unlock.
- (BOOL)isLocked;
@end

NS_ASSUME_NONNULL_END
