// Every condition is sampled independently: a false/throwing settings getter cannot hide process/event failures.
static NSDictionary *DXReadinessSnapshot(DXSystemSceneHandle *h, NSDictionary<NSString *, id> *groups) {
    NSMutableDictionary *checks=[NSMutableDictionary dictionary], *reasons=[NSMutableDictionary dictionary];
    NSMutableArray *pending=[NSMutableArray array];
    for (NSString *group in @[@"settings",@"scene",@"process",@"presenter",@"layers",@"events"]) {
        NSDictionary *tests=groups[group]; NSMutableDictionary *values=[NSMutableDictionary dictionary]; BOOL ready=YES;
        for (NSString *key in [[tests allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            BOOL value=NO;
            @try { BOOL (^test)(void)=tests[key]; value=test(); }
            @catch (NSException *e) {
                NSError *error=DXCaught(e);
                reasons[[group stringByAppendingFormat:@".%@",key]]=error.userInfo[DXSceneSelectorKey] ?: @"native-check-exception";
            }
            values[key]=@(value); ready=ready && value;
            NSString *path=[group stringByAppendingFormat:@".%@",key];
            if (!value && !reasons[path]) reasons[path]=@"not-acknowledged";
        }
        checks[group]=@{@"ready":@(ready),@"checks":values};
        if (!ready) [pending addObject:group];
    }
    NSDictionary *snapshot=@{@"phase":pending.count ? @"awaiting-acknowledgement" : @"ready",@"pending":pending,@"checks":checks,@"reasons":reasons};
    h.readinessSnapshot=snapshot; return snapshot;
}
