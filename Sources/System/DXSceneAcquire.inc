- (void)acquireSceneForBundleIdentifier:(NSString *)identifier completion:(void (^)(DXSystemSceneHandle *, NSError *))completion {
    NSString *bid=[identifier copy];
    __block NSUInteger epoch=0; __block BOOL blocked=NO;
    __block DXSystemSceneHandle *result=nil;
    __block DXBridgeOperation *op;
    op=[[DXBridgeOperation alloc] initWithTimeout:2 completion:^(NSError *error) {
        void (^deliver)(NSError *)=^(NSError *finalError) {
            DXBridgeOperation *finished=op;
            @synchronized(self) { [self.acquisitions removeObject:finished]; }
            op=nil;
            @try { completion(finalError ? nil : result,finalError); }
            @finally { [self maybeFinishReleaseAll]; }
        };
        if (error && result) [self releaseHandle:result completion:^(NSError *cleanup) { deliver(DXErrorWithCleanup(error,cleanup)); }];
        else deliver(error);
    }];
    op.name=@"acquire";
    @synchronized(self) { epoch=self.epoch; blocked=self.barriersRequested>0; [self.acquisitions addObject:op]; }
    __weak DXBridgeOperation *weakOp=op;
    [op start:^{
        [weakOp enterStage:@"eligibility"];
        @synchronized(self) { DXRequire(epoch==self.epoch && !blocked && !self.barriersRequested,DXSystemBridgeErrorCancelled,@"Acquisition cancelled by recovery epoch"); }
        DXRequire(DXSpringBoard() && !self.isLocked,DXSystemBridgeErrorLocked,@"Acquire refused while locked or outside SpringBoard");
        DXRequire(!self.nativePending && !self.contextLost && !self.restorations && !self.recovery.count && !self.observationError,DXSystemBridgeErrorOwnership,@"Native activation or unconfirmed recovery in progress");
        DXRequire(DXString(bid)!=nil && ![bid isEqualToString:@"com.apple.springboard"],DXSystemBridgeErrorNoScene,@"Invalid application identifier");
        DXRequire([self ownedResourceCount]<3,DXSystemBridgeErrorOwnership,@"At most three total own resources, including quarantined recovery, may be owned");
        for (DXSystemSceneHandle *h in self.handles.allValues)
            DXRequire(![h.bundleIdentifier isEqualToString:bid],DXSystemBridgeErrorOwnership,@"Application is already leased");
        [weakOp enterStage:@"scene-discovery"];
        id scene=[self uniqueSceneForIdentifier:bid];
        result=[[DXSystemSceneHandle alloc] initWithOwner:self scene:scene];
        DXRequire(result.sceneIdentifier.length && !self.handles[result.sceneIdentifier],DXSystemBridgeErrorOwnership,@"Scene already owned or has no stable identifier");
        // Register BEFORE creating private resources: even a partial nonnil handle has an owner.
        self.handles[result.sceneIdentifier]=result;
        DXRequire(DXProtocolABI(@"FBSceneObserver",@selector(sceneDidInvalidate:),"v@:@",NO),DXSystemBridgeErrorABI,@"FBSceneObserver invalidation callback ABI unavailable");
        DXCheckedIMP(scene,@selector(addObserver:),"v","@"); DXCheckedIMP(scene,@selector(removeObserver:),"v","@");
        Protocol *observer=DXRuntimeProtocol(@"FBSceneObserver"); if (observer) class_addProtocol(DXSystemSceneHandle.class,observer);
        [weakOp enterStage:@"presentation-manager"];
        Class cls=DXRuntimeClass(@"UIScenePresentationManager");
        DXRequire(cls!=nil,DXSystemBridgeErrorUnavailable,@"UIScenePresentationManager unavailable; raw pixel-host fallback is not interactive");
        result.presentationManager=DXInitializeObject(cls,@selector(_initWithScene:),scene);
        DXRequire(result.presentationManager!=nil,DXSystemBridgeErrorSystemRejected,@"Native presentation manager rejected scene");
        DXCheckpoint(@"acquire.manager",result);
        [weakOp enterStage:@"presenter-creation"];
        result.presenter=DXObject1(result.presentationManager,@selector(createPresenterWithIdentifier:),
                                  [@"com.tsangbaby.dynamicstagex/" stringByAppendingString:NSUUID.UUID.UUIDString]);
        DXRequire(result.presenter!=nil,DXSystemBridgeErrorSystemRejected,@"Native presenter was not created");
        DXCheckedIMP(result.presenter,@selector(invalidate),"v","");
        DXCheckedIMP(result.presenter,@selector(deactivate),"v","");
        DXCheckedIMP(result.presenter,@selector(activate),"v","");
        DXCheckedIMP(result.presenter,@selector(isHosting),@encode(bool),"");
        DXCheckedIMP(result.presenter,@selector(isActive),@encode(bool),"");
        DXCheckedIMP(result.presenter,@selector(isInvalidated),@encode(bool),"");
        UIView *view=DXObject(result.presenter,@selector(presentationView));
        DXRequire([view isKindOfClass:DXRuntimeClass(@"_UIScenePresentationView")] && !view.superview,
                  DXSystemBridgeErrorOwnership,@"Presenter did not return a fresh own native presentation view");
        result.hostView=view;
        DXRequire(DXObject(result.presenter,@selector(scene))==scene,DXSystemBridgeErrorOwnership,@"Presenter resolved a different scene");
        [weakOp enterStage:@"scene-observation"];
        result.observed=YES; DXVoid1(scene,@selector(addObserver:),result);
        [self beginObserving];
        DXCheckpoint(@"acquire.pending",weakOp);
    }];
}
