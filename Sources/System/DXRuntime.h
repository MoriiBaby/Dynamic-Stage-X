#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdbool.h>

NS_ASSUME_NONNULL_BEGIN
/// Only bridge-owned exception; caught before crossing any public API/native observer.
FOUNDATION_EXPORT void DXThrow(NSInteger code, NSString *message);
FOUNDATION_EXPORT NSError *DXCaught(NSException *exception);
FOUNDATION_EXPORT NSError *DXErrorWithCleanup(NSError * _Nullable primary, NSError * _Nullable cleanup);
FOUNDATION_EXPORT Class _Nullable DXRuntimeClass(NSString *name);
FOUNDATION_EXPORT Protocol * _Nullable DXRuntimeProtocol(NSString *name);
#if DX_SCENE_BRIDGE_TESTING
FOUNDATION_EXPORT Class _Nullable DXSceneBridgeTestingClass(NSString *name);
FOUNDATION_EXPORT Protocol * _Nullable DXSceneBridgeTestingProtocol(NSString *name);
FOUNDATION_EXPORT void DXSceneBridgeTestingCheckpoint(NSString *stage, id _Nullable object);
FOUNDATION_EXPORT BOOL DXSceneBridgeTestingSpringBoard(void);
#endif
FOUNDATION_EXPORT IMP DXCheckedIMP(id receiver, SEL selector, const char *result, const char *arguments);
FOUNDATION_EXPORT BOOL DXHasABI(id _Nullable receiver, SEL selector, const char *result, const char *arguments);
FOUNDATION_EXPORT BOOL DXProtocolABI(NSString *protocol, SEL selector, const char *signature, BOOL required);
FOUNDATION_EXPORT id _Nullable DXInitializeObject(Class cls, SEL selector, id argument);
FOUNDATION_EXPORT id _Nullable DXObject(id receiver, SEL selector);
FOUNDATION_EXPORT id _Nullable DXObject1(id receiver, SEL selector, id _Nullable argument);
FOUNDATION_EXPORT void DXVoid(id receiver, SEL selector);
FOUNDATION_EXPORT void DXVoid1(id receiver, SEL selector, id _Nullable argument);
FOUNDATION_EXPORT bool DXBool(id receiver, SEL selector);
FOUNDATION_EXPORT uint64_t DXUInt64(id receiver, SEL selector);
FOUNDATION_EXPORT unsigned int DXUInt32(id receiver, SEL selector);
FOUNDATION_EXPORT int DXPID(id receiver, SEL selector);
FOUNDATION_EXPORT CGRect DXFrame(id receiver);
FOUNDATION_EXPORT void DXSetBool(id receiver, SEL selector, bool value);
FOUNDATION_EXPORT void DXSetFrame(id receiver, CGRect frame);

/// All callbacks and progress main-only; never uses dispatch_sync, semaphore or run-loop spin.
@interface DXBridgeOperation : NSObject
@property (nonatomic, readonly) BOOL finished;
@property (nonatomic, readonly) CFTimeInterval deadline;
@property (nonatomic, copy, nullable) BOOL (^progress)(void);
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *stage;
@property (nonatomic, copy) NSDictionary<NSString *, id> *diagnostics;
- (NSError *)diagnose:(NSError *)error;
- (void)enterStage:(NSString *)stage;
- (instancetype)initWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSError * _Nullable))completion;
- (void)start:(void (^)(void))start;
- (void)finish:(nullable NSError *)error;
@end
NS_ASSUME_NONNULL_END
