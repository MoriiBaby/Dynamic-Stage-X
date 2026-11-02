#import "DXRuntime.h"
#import "DXSystemBridge.h"
#import "DXABIEncoding.h"
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

void DXThrow(NSInteger code, NSString *message) {
    NSError *error = [NSError errorWithDomain:DXSystemBridgeErrorDomain code:code
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
    @throw [NSException exceptionWithName:@"DXBridgeFault" reason:@"Private-system operation rejected"
                                userInfo:@{@"error": error}];
}
NSError *DXCaught(NSException *exception) {
    if ([exception.name isEqualToString:@"DXBridgeFault"] &&
        [exception.userInfo[@"error"] isKindOfClass:NSError.class]) return exception.userInfo[@"error"];
    return [NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorSystemRejected
                          userInfo:@{NSLocalizedDescriptionKey: @"Native system method raised an exception; no exception payload retained"}];
}
static Method DXMethod(id receiver, SEL selector) {
    return receiver ? class_getInstanceMethod(object_getClass(receiver), selector) : NULL;
}
BOOL DXHasABI(id receiver, SEL selector, const char *result, const char *arguments) {
    Method method = DXMethod(receiver, selector);
    char expected[1024];
    int n = snprintf(expected, sizeof(expected), "%s@:%s", result, arguments);
    return method && n > 0 && (size_t)n < sizeof(expected) &&
        DXABIEncodingMatches(method_getTypeEncoding(method), expected);
}
IMP DXCheckedIMP(id receiver, SEL selector, const char *result, const char *arguments) {
    if (!NSThread.isMainThread) DXThrow(DXSystemBridgeErrorOwnership, @"Private call outside main thread");
    Method method=DXMethod(receiver,selector);
    char expected[1024]; int n=snprintf(expected,sizeof(expected),"%s@:%s",result,arguments);
    if (!method || n<=0 || (size_t)n>=sizeof(expected) || !DXABIEncodingMatches(method_getTypeEncoding(method),expected))
        DXThrow(DXSystemBridgeErrorABI, [NSString stringWithFormat:@"ABI unavailable: %@ %@", receiver ? NSStringFromClass(object_getClass(receiver)) : @"nil", NSStringFromSelector(selector)]);
    return method_getImplementation(method);
}
BOOL DXProtocolABI(NSString *name, SEL selector, const char *signature, BOOL required) {
    Protocol *protocol = NSProtocolFromString(name);
    if (!protocol) return NO;
    struct objc_method_description d = protocol_getMethodDescription(protocol, selector, required, YES);
    return d.name && d.types && DXABIEncodingMatches(d.types, signature);
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
    CFTimeInterval _deadline;
    void (^_completion)(NSError *);
}
- (instancetype)initWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSError *))completion {
    if ((self = [super init])) { _deadline = CACurrentMediaTime() + timeout; _completion = [completion copy]; }
    return self;
}
- (BOOL)finished { return _finished; }
- (CFTimeInterval)deadline { return _deadline; }
- (void)finish:(NSError *)error {
    NSAssert(NSThread.isMainThread, @"Completion must be on main");
    if (_finished) return;
    _finished = YES; self.progress = nil;
    void (^completion)(NSError *) = _completion; _completion = nil;
    if (completion) completion(error);
}
- (void)tick {
    if (_finished) return;
    @try {
        if (CACurrentMediaTime() >= _deadline) DXThrow(DXSystemBridgeErrorTimeout, @"System acknowledgement timed out");
        if (!self.progress || self.progress()) { [self finish:nil]; return; }
    } @catch (NSException *e) { [self finish:DXCaught(e)]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self tick]; });
}
- (void)start:(void (^)(void))start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finished) return;
        @try {
            if (CACurrentMediaTime() >= self.deadline) DXThrow(DXSystemBridgeErrorTimeout, @"Operation expired before starting; no mutation performed");
            start();
        } @catch (NSException *e) { [self finish:DXCaught(e)]; return; }
        [self tick];
    });
}
@end
