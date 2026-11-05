// Included inside DXSystemBridge's implementation; all ownership transitions run on main.
#include "DXSceneRestore.inc"

- (NSError *)tearDown:(DXSystemSceneHandle *)h {
    NSError *failure=nil;
    h.released=YES; h.interactive=NO;
    [self.recovery addObject:h]; // The same bounded lease, never extra acquisition capacity.
    @try {
        @try {
            DXBridgeOperation *pending=h.operation; h.operation=nil;
            if (pending && !pending.finished) [pending finish:[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorCancelled userInfo:@{NSLocalizedDescriptionKey:@"Handle released during operation"}]];
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"cancel-operation")); }
        @try {
            if (!h.hostDetached) {
                h.hostView.userInteractionEnabled=NO;
                DXCheckpoint(@"release.detach",h);
                [h.hostView removeFromSuperview];
                h.hostDetached=(h.hostView.superview==nil);
            }
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"detach-host")); }
        // Never invalidate a presenter while its native host is still attached.
        @try {
            if (h.hostDetached && !h.presenterDeactivated) {
                DXCheckpoint(@"release.deactivate",h);
                if (h.presenter) DXVoid(h.presenter,@selector(deactivate));
                h.presenterDeactivated=YES;
            }
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"deactivate-presenter")); }
        @try {
            if (h.hostDetached && h.presenterDeactivated && !h.presenterInvalidated) {
                DXCheckpoint(@"release.invalidate",h);
                if (h.presenter) DXVoid(h.presenter,@selector(invalidate));
                h.presenterInvalidated=YES;
            }
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"invalidate-presenter")); }
        @try {
            DXCheckpoint(@"release.focus",h);
            failure=DXErrorWithCleanup(failure,[self restoreFocusIfOwnedBy:h]);
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"restore-focus")); }
        @try {
            DXCheckpoint(@"release.settings",h);
            failure=DXErrorWithCleanup(failure,[self restoreSettingsForHandle:h]);
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"restore-settings")); }
        @try {
            if (h.observed) {
                DXCheckpoint(@"release.observer",h);
                DXVoid1(h.scene,@selector(removeObserver:),h); h.observed=NO;
            }
        } @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"remove-scene-observer")); }
        @try {
            if (!h.referencesDropped && h.hostDetached && h.presenterDeactivated && h.presenterInvalidated && !h.observed) {
                DXCheckpoint(@"release.references",h);
                h.presenter=nil; h.presentationManager=nil;
                h.referencesDropped=YES; h.referenceFailure=nil;
            }
        } @catch (NSException *e) {
            h.referenceFailure=DXCleanupCaught(e,@"drop-references");
            failure=DXErrorWithCleanup(failure,h.referenceFailure);
        }
    } @finally {
        // No native/observer/host failure may leave a released entry in the active registry.
        if (h.sceneIdentifier && self.handles[h.sceneIdentifier]==h) [self.handles removeObjectForKey:h.sceneIdentifier];
    }
    if (self.focusOwner==nil && self.focusOperation) {
        DXBridgeOperation *focus=self.focusOperation; self.focusOperation=nil; self.focusPending=NO;
        @try { [focus finish:[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorCancelled userInfo:@{NSLocalizedDescriptionKey:@"Focus lease released"}]]; }
        @catch (NSException *e) { failure=DXErrorWithCleanup(failure,DXCleanupCaught(e,@"cancel-focus")); }
    }
    if (!self.handles.count) failure=DXErrorWithCleanup(failure,[self endObserving]);
    return failure;
}

- (void)releaseHandle:(DXSystemSceneHandle *)h completion:(void (^)(NSError *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!h || h.owner!=self) {
            completion([NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorStaleHandle userInfo:@{NSLocalizedDescriptionKey:@"Release cannot consume a foreign handle"}]); return;
        }
        if (h.releaseOperation) { [h.releaseWaiters addObject:[completion copy]]; return; }
        if (h.released && ![self.recovery containsObject:h]) { completion(h.releaseError); return; }
        h.releaseWaiters=[NSMutableArray arrayWithObject:[completion copy]];
        self.restorations+=1;
        __block NSError *attemptError=nil;
        __block BOOL attempted=NO;
        __block DXBridgeOperation *op;
        op=[[DXBridgeOperation alloc] initWithTimeout:2 completion:^(NSError *error) {
            // Even a release that expired in the queue MUST attempt physical cleanup once.
            if (!attempted) { attempted=YES; attemptError=[self tearDown:h]; }
            NSError *result=error ? DXErrorWithCleanup(error,attemptError) : (attemptError ? [op diagnose:attemptError] : nil);
            BOOL confirmed=NO;
            @try { confirmed=[self cleanupConfirmed:h]; }
            @catch (NSException *e) { result=DXErrorWithCleanup(result,DXCleanupCaught(e,@"confirm-cleanup")); }
            if (confirmed) [self.recovery removeObject:h];
            else if (!result) result=[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorOwnership userInfo:@{NSLocalizedDescriptionKey:@"Cleanup remains unconfirmed; explicitly retry recovery"}];
            h.releaseError=result;
            // Keep the operation installed until every shared waiter has returned.
            NSArray *waiters=[h.releaseWaiters copy]; [h.releaseWaiters removeAllObjects];
            @try {
                for (void (^waiter)(NSError *) in waiters) {
                    @try { waiter(result); } @catch (__unused NSException *e) { /* A caller cannot skip the remaining waiters. */ }
                }
            } @finally {
                h.releaseOperation=nil; op=nil; self.restorations-=1;
                if (!self.handles.count && !self.recovery.count && !self.observationError) self.contextLost=NO;
                [self maybeFinishReleaseAll];
            }
        }];
        h.releaseOperation=op; op.name=@"release";
        __weak DXBridgeOperation *weakOp=op;
        [op start:^{
            [weakOp enterStage:@"cleanup"];
            attempted=YES; attemptError=[self tearDown:h];
            if (attemptError) { [weakOp finish:nil]; return; }
            [weakOp enterStage:@"restore-acknowledgement"];
            weakOp.progress=^BOOL{ return [self cleanupConfirmed:h]; };
        }];
    });
}

- (void)releaseAllScenesWithCompletion:(void (^)(NSError *))completion {
    // Advance synchronously, including requests whose main-queue acquire has not started yet.
    @synchronized(self) { self.epoch+=1; self.barriersRequested+=1; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.releaseAllWaiters addObject:[completion copy]];
        if (self.releaseAllWaiters.count>1) return; // Concurrent callers share this drain.
        self.releaseAllError=nil; self.releaseAllScheduling=YES;
        NSArray *pending;
        @synchronized(self) { pending=self.acquisitions.allObjects; }
        NSError *cancel=[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorCancelled userInfo:@{NSLocalizedDescriptionKey:@"Acquisition cancelled by releaseAll recovery epoch"}];
        for (DXBridgeOperation *operation in pending) [operation finish:cancel];
        NSMutableSet *owned=[NSMutableSet setWithArray:self.handles.allValues]; [owned unionSet:self.recovery];
        for (DXSystemSceneHandle *handle in owned) {
            self.releaseAllInFlight+=1;
            [self releaseHandle:handle completion:^(NSError *error) {
                self.releaseAllError=DXErrorWithCleanup(self.releaseAllError,error);
                self.releaseAllInFlight-=1; [self maybeFinishReleaseAll];
            }];
        }
        self.releaseAllScheduling=NO;
        [self maybeFinishReleaseAll];
    });
}

- (void)maybeFinishReleaseAll {
    if (!NSThread.isMainThread || !self.releaseAllWaiters.count || self.releaseAllScheduling ||
        self.releaseAllInFlight || self.restorations) return;
    @synchronized(self) { if (self.acquisitions.count) return; }
    if (!self.handles.count) self.releaseAllError=DXErrorWithCleanup(self.releaseAllError,[self endObserving]);
    NSError *result=self.releaseAllError;
    if ((self.handles.count || self.recovery.count || self.observationError) && !result)
        result=[NSError errorWithDomain:DXSystemBridgeErrorDomain code:DXSystemBridgeErrorOwnership userInfo:@{NSLocalizedDescriptionKey:@"Recovery remains quarantined; no new acquisition until an explicit successful retry"}];
    NSArray *waiters=[self.releaseAllWaiters copy]; [self.releaseAllWaiters removeAllObjects];
    self.releaseAllError=nil;
    if (!result && !self.handles.count && !self.recovery.count) self.contextLost=NO;
    @synchronized(self) { self.barriersRequested-=waiters.count; }
    for (void (^waiter)(NSError *) in waiters) {
        @try { waiter(result); } @catch (__unused NSException *e) { }
    }
}
