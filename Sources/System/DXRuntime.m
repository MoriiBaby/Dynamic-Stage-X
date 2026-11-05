#import "DXRuntime.h"
#import "DXSystemBridge.h"
#import "DXABIEncoding.h"
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

NSString * const DXSceneOperationKey=@"DXSceneOperation";
NSString * const DXSceneStageKey=@"DXSceneStage";
NSString * const DXSceneClassKey=@"DXSceneClass";
NSString * const DXSceneSelectorKey=@"DXSceneSelector";
NSString * const DXSceneExceptionNameKey=@"DXSceneExceptionName";
NSString * const DXSceneReadinessKey=@"DXSceneReadiness";
NSString * const DXSceneCleanupErrorsKey=@"DXSceneCleanupErrors";
static __weak DXBridgeOperation *DXCurrentOperation; // Main-thread-only scoped context.
static NSString *DXLastClass, *DXLastSelector;
static NSString *DXIdentifier(NSString *s) {
    if (!s.length || s.length>96) return @"unclassified";
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:.+-"] invertedSet];
    return [s rangeOfCharacterFromSet:bad].location==NSNotFound ? s : @"unclassified";
}
Class DXRuntimeClass(NSString *name) {
#if DX_SCENE_BRIDGE_TESTING
    Class fixture=DXSceneBridgeTestingClass(name); if (fixture) return fixture;
#endif
    return NSClassFromString(name);
}
Protocol *DXRuntimeProtocol(NSString *name) {
#if DX_SCENE_BRIDGE_TESTING
    Protocol *fixture=DXSceneBridgeTestingProtocol(name); if (fixture) return fixture;
#endif
    return NSProtocolFromString(name);
}
NSError *DXErrorWithCleanup(NSError *primary, NSError *cleanup) {
    if (!primary) return cleanup;
    if (!cleanup || cleanup==primary) return primary;
    NSMutableDictionary *info=[primary.userInfo mutableCopy];
    NSMutableArray *chain=[info[DXSceneCleanupErrorsKey] mutableCopy] ?: [NSMutableArray array];
    if (chain.count<12) [chain addObject:cleanup];
    info[DXSceneCleanupErrorsKey]=chain;
    if (!info[NSUnderlyingErrorKey]) info[NSUnderlyingErrorKey]=cleanup;
    return [NSError errorWithDomain:primary.domain code:primary.code userInfo:info];
}
void DXThrow(NSInteger code, NSString *message) {
    NSError *error=[NSError errorWithDomain:DXSystemBridgeErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    @throw [NSException exceptionWithName:@"DXBridgeFault" reason:@"Private-system operation rejected" userInfo:@{@"error":error}];
}
NSError *DXCaught(NSException *exception) {
    NSError *error=nil;
    if ([exception.name isEqualToString:@"DXBridgeFault"] && [exception.userInfo[@"error"] isKindOfClass:NSError.class]) error=exception.userInfo[@"error"];
    else error=[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorSystemRejected userInfo:@{NSLocalizedDescriptionKey:@"Native operation raised an exception; payload discarded", DXSceneExceptionNameKey:DXIdentifier(exception.name)}];
    NSMutableDictionary *info=[error.userInfo mutableCopy];
    if (DXLastClass) info[DXSceneClassKey]=DXLastClass;
    if (DXLastSelector) info[DXSceneSelectorKey]=DXLastSelector;
    error=[NSError errorWithDomain:error.domain code:error.code userInfo:info];
    return DXCurrentOperation ? [DXCurrentOperation diagnose:error] : error;
}
static Method DXMethod(id receiver, SEL selector) { return receiver ? class_getInstanceMethod(object_getClass(receiver),selector) : NULL; }
BOOL DXHasABI(id receiver, SEL selector, const char *result, const char *arguments) {
    Method method=DXMethod(receiver,selector); char expected[1024];
    int n=snprintf(expected,sizeof(expected),"%s@:%s",result,arguments);
    return method && n>0 && (size_t)n<sizeof(expected) && DXABIEncodingMatches(method_getTypeEncoding(method),expected);
}
IMP DXCheckedIMP(id receiver, SEL selector, const char *result, const char *arguments) {
    if (!NSThread.isMainThread) DXThrow(DXSystemBridgeErrorOwnership,@"Private call outside main thread");
    DXLastClass=DXIdentifier(receiver ? NSStringFromClass(object_getClass(receiver)) : @"nil");
    DXLastSelector=DXIdentifier(NSStringFromSelector(selector));
    Method method=DXMethod(receiver,selector); char expected[1024];
    int n=snprintf(expected,sizeof(expected),"%s@:%s",result,arguments);
    if (!method || n<=0 || (size_t)n>=sizeof(expected) || !DXABIEncodingMatches(method_getTypeEncoding(method),expected))
        DXThrow(DXSystemBridgeErrorABI,@"Required native method ABI unavailable");
    return method_getImplementation(method);
}
BOOL DXProtocolABI(NSString *name, SEL selector, const char *signature, BOOL required) {
    Protocol *protocol=DXRuntimeProtocol(name);
    if (!protocol) return NO;
    struct objc_method_description d=protocol_getMethodDescription(protocol,selector,required,YES);
    return d.name && d.types && DXABIEncodingMatches(d.types,signature);
}
// A generic id-returning IMP has +0 semantics to ARC and is NOT valid for init.
// Keep the alloc receiver alive through ABI validation, then consume exactly one +1.
typedef id __attribute__((ns_returns_retained)) (*DXInitIMP)(id __attribute__((ns_consumed)), SEL, id);
id DXInitializeObject(Class cls, SEL selector, id argument) {
    id allocated=[cls alloc];
    DXInitIMP initializer=(DXInitIMP)DXCheckedIMP(allocated,selector,"@","@");
    return initializer(allocated,selector,argument);
}
id DXObject(id o, SEL s) { return ((id (*)(id,SEL))DXCheckedIMP(o,s,"@",""))(o,s); }
id DXObject1(id o, SEL s, id a) { return ((id (*)(id,SEL,id))DXCheckedIMP(o,s,"@","@"))(o,s,a); }
void DXVoid(id o, SEL s) { ((void (*)(id,SEL))DXCheckedIMP(o,s,"v",""))(o,s); }
void DXVoid1(id o, SEL s, id a) { ((void (*)(id,SEL,id))DXCheckedIMP(o,s,"v","@"))(o,s,a); }
bool DXBool(id o, SEL s) { return ((bool (*)(id,SEL))DXCheckedIMP(o,s,@encode(bool),""))(o,s); }
uint64_t DXUInt64(id o, SEL s) { return ((unsigned long long (*)(id,SEL))DXCheckedIMP(o,s,"Q",""))(o,s); }
unsigned int DXUInt32(id o, SEL s) { return ((unsigned int (*)(id,SEL))DXCheckedIMP(o,s,"I",""))(o,s); }
int DXPID(id o, SEL s) { return ((int (*)(id,SEL))DXCheckedIMP(o,s,"i",""))(o,s); }
CGRect DXFrame(id o) { return ((CGRect (*)(id,SEL))DXCheckedIMP(o,@selector(frame),@encode(CGRect),""))(o,@selector(frame)); }
void DXSetFrame(id o, CGRect r) { ((void (*)(id,SEL,CGRect))DXCheckedIMP(o,@selector(setFrame:),"v",@encode(CGRect)))(o,@selector(setFrame:),r); }
void DXSetBool(id o, SEL s, bool b) { ((void (*)(id,SEL,bool))DXCheckedIMP(o,s,"v",@encode(bool)))(o,s,b); }

@implementation DXBridgeOperation {
    BOOL _finished;
    CFTimeInterval _deadline, _started, _stageStarted;
    void (^_completion)(NSError *);
}
- (instancetype)initWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSError *))completion {
    if ((self=[super init])) {
        _started=_stageStarted=CACurrentMediaTime(); _deadline=_started+timeout;
        _completion=[completion copy]; _name=@"operation"; _stage=@"queued"; _diagnostics=@{};
    }
    return self;
}
- (BOOL)finished { return _finished; }
- (CFTimeInterval)deadline { return _deadline; }
- (void)enterStage:(NSString *)stage {
    _stage=DXIdentifier(stage); _stageStarted=CACurrentMediaTime(); DXLastClass=nil; DXLastSelector=nil;
}
- (NSError *)diagnose:(NSError *)error {
    NSMutableDictionary *info=[error.userInfo mutableCopy];
    if (!info[DXSceneOperationKey]) info[DXSceneOperationKey]=self.name;
    if (!info[DXSceneStageKey]) info[DXSceneStageKey]=self.stage;
    info[@"DXSceneElapsedMS"]=@((NSInteger)((CACurrentMediaTime()-_started)*1000));
    info[@"DXSceneStageElapsedMS"]=@((NSInteger)((CACurrentMediaTime()-_stageStarted)*1000));
    if (self.diagnostics.count && !info[DXSceneReadinessKey]) info[DXSceneReadinessKey]=self.diagnostics;
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}
- (void)finish:(NSError *)error {
    NSAssert(NSThread.isMainThread,@"Completion must be on main");
    if (_finished) return;
    _finished=YES; self.progress=nil;
    void (^completion)(NSError *)=_completion; _completion=nil;
    if (completion) completion(error ? [self diagnose:error] : nil);
}
- (void)tick {
    if (_finished) return;
    DXBridgeOperation *previous=DXCurrentOperation; DXCurrentOperation=self;
    NSError *failure=nil; BOOL ready=NO;
    @try {
        if (CACurrentMediaTime()>=_deadline) DXThrow(DXSystemBridgeErrorTimeout,@"System acknowledgement timed out; see per-condition readiness");
        ready=!self.progress || self.progress();
    } @catch (NSException *e) { failure=DXCaught(e); }
    @finally { DXCurrentOperation=previous; }
    if (failure || ready) { [self finish:failure]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self tick]; });
}
- (void)start:(void (^)(void))start {
    dispatch_async(dispatch_get_main_queue(),^{
        if (self.finished) return;
        DXBridgeOperation *previous=DXCurrentOperation; DXCurrentOperation=self;
        DXLastClass=nil; DXLastSelector=nil;
        NSError *failure=nil;
        @try {
            if (CACurrentMediaTime()>=self.deadline) DXThrow(DXSystemBridgeErrorTimeout,@"Operation expired in queue; no mutation performed");
            start();
        } @catch (NSException *e) { failure=DXCaught(e); }
        @finally { DXCurrentOperation=previous; }
        if (failure) { [self finish:failure]; return; }
        [self tick];
    });
}
@end
