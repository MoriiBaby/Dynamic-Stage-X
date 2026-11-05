// Included inside DXSystemBridge implementation; production restoration, not a test model.
- (NSError *)restoreSettingsForHandle:(DXSystemSceneHandle *)h {
    NSError *failure=nil;
    if (!h.changedSettings) { h.settingsRestored=YES; h.restoreMask=0; return nil; }
    @try {
        BOOL sceneOwned=DXSceneStillRegistered(h.scene) && DXObject(h.scene,@selector(clientProcess))==h.process &&
            DXPID(h.process,@selector(pid))==h.processIdentifier && DXBool(h.process,@selector(isRunning));
        // Quarantine retains the SAME own lease; no new scene/process ownership is invented.
        BOOL owner=[self.recovery containsObject:h] && (!self.handles[h.sceneIdentifier] || self.handles[h.sceneIdentifier]==h);
        if (!h.changedSettings || !sceneOwned || !owner) { h.settingsRestored=YES; h.restoreMask=0; return nil; }
        id current=DXSettings(h.scene);
        CGRect currentFrame=DXFrame(current);
        bool currentBackground=DXBool(current,@selector(isBackgrounded));
        bool currentForeground=h.hasForeground ? DXBool(current,@selector(isForeground)) : false;
        unsigned changed=(!CGRectEqualToRect(h.originalFrame,h.writtenFrame) ? DXLeaseFrame : 0) |
            (h.hasForeground && !h.originalForeground ? DXLeaseForeground : 0) | (h.originalBackgrounded ? DXLeaseBackgrounded : 0);
        unsigned equal=(CGRectEqualToRect(currentFrame,h.writtenFrame) ? DXLeaseFrame : 0) |
            (h.hasForeground && currentForeground ? DXLeaseForeground : 0) | (!currentBackground ? DXLeaseBackgrounded : 0);
        unsigned original=(CGRectEqualToRect(currentFrame,h.originalFrame) ? DXLeaseFrame : 0) |
            (h.hasForeground && currentForeground==h.originalForeground ? DXLeaseForeground : 0) |
            (currentBackground==h.originalBackgrounded ? DXLeaseBackgrounded : 0);
        unsigned mask=DXLeaseRestoreMask(changed,equal,sceneOwned,owner);
        BOOL conflict=(changed & ~(equal | original))!=0;
        h.restoreMask=mask;
        if (mask) {
            DXCheckedIMP(current,@selector(mutableCopy),"@",""); id mutable=[current mutableCopy];
            DXRequire(mutable && mutable!=current,DXSystemBridgeErrorOwnership,@"Restoration requires an independent mutable copy");
            if (mask & DXLeaseFrame) DXSetFrame(mutable,h.originalFrame);
            if (mask & DXLeaseForeground) DXSetBool(mutable,@selector(setForeground:),h.originalForeground);
            if (mask & DXLeaseBackgrounded) DXSetBool(mutable,@selector(setBackgrounded:),h.originalBackgrounded);
            DXWriteSettings(h.scene,mutable);
        }
        if (h.activatedScene && !h.deactivatedScene && (equal & 7u)==(h.hasForeground ? 7u : 5u) &&
            ![self.frontmostApplicationIdentifier isEqualToString:h.bundleIdentifier] && DXBool(h.scene,@selector(isActive))) {
            DXVoid1(h.scene,@selector(deactivateWithTransitionContext:),nil); h.deactivatedScene=YES;
        }
        h.settingsRestored=YES; // Submission only; cleanupConfirmed independently acknowledges it.
        if (conflict) DXThrow(DXSystemBridgeErrorOwnership,@"Native owner superseded leased settings; conflicting fields were not overwritten");
    } @catch (NSException *e) { failure=DXCleanupCaught(e,@"restore-settings"); }
    return failure;
}
- (BOOL)cleanupConfirmed:(DXSystemSceneHandle *)h {
    if (h.referenceFailure || !h.hostDetached || !h.presenterDeactivated || !h.presenterInvalidated ||
        h.observed || !h.settingsRestored || !h.referencesDropped) return NO;
    if (self.focusOwner==h) return NO;
    if (!h.changedSettings && !h.restoreFocusScene) return YES;
    if (!DXSceneStillRegistered(h.scene) || DXObject(h.scene,@selector(clientProcess))!=h.process ||
        DXPID(h.process,@selector(pid))!=h.processIdentifier || !DXBool(h.process,@selector(isRunning))) return YES;
    id settings=DXSettings(h.scene);
    if ((h.restoreMask & DXLeaseFrame) && !CGRectEqualToRect(DXFrame(settings),h.originalFrame)) return NO;
    if ((h.restoreMask & DXLeaseForeground) && DXBool(settings,@selector(isForeground))!=h.originalForeground) return NO;
    if ((h.restoreMask & DXLeaseBackgrounded) && DXBool(settings,@selector(isBackgrounded))!=h.originalBackgrounded) return NO;
    if (h.deactivatedScene && DXBool(h.scene,@selector(isActive))) return NO;
    if (h.restoreFocusScene && !self.isLocked && DXSceneStillRegistered(h.restoreFocusScene)) {
        id controller=DXFocusController();
        if (DXUInt64(controller,@selector(userFocusRequestGeneration))==h.restoreFocusGeneration && DXFocusedScene()!=h.restoreFocusScene) return NO;
    }
    return YES;
}
