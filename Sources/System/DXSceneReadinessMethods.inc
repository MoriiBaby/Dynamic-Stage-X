- (NSDictionary *)readinessForHandle:(DXSystemSceneHandle *)h {
    return DXReadinessSnapshot(h,@{
        @"settings":@{
            @"frame":^BOOL{ return CGRectEqualToRect(DXFrame(DXSettings(h.scene)),h.writtenFrame); },
            @"foreground":^BOOL{ return !h.hasForeground || DXBool(DXSettings(h.scene),@selector(isForeground)); },
            @"notBackgrounded":^BOOL{ return !DXBool(DXSettings(h.scene),@selector(isBackgrounded)); }},
        @"scene":@{
            @"registered":^BOOL{ return DXSceneStillRegistered(h.scene); },
            @"active":^BOOL{ return DXBool(h.scene,@selector(isActive)); },
            @"processIdentity":^BOOL{ return DXObject(h.scene,@selector(clientProcess))==h.process; }},
        @"process":@{
            @"pid":^BOOL{ return DXPID(h.process,@selector(pid))==h.processIdentifier; },
            @"running":^BOOL{ return DXBool(h.process,@selector(isRunning)); },
            @"foreground":^BOOL{ return DXBool(h.process,@selector(isForeground)); }},
        @"presenter":@{
            @"sceneIdentity":^BOOL{ return DXObject(h.presenter,@selector(scene))==h.scene; },
            @"managerIdentity":^BOOL{ return DXObject(h.presentationManager,@selector(scene))==h.scene; },
            @"active":^BOOL{ return DXBool(h.presenter,@selector(isActive)); },
            @"hosting":^BOOL{ return DXBool(h.presenter,@selector(isHosting)); },
            @"valid":^BOOL{ return !DXBool(h.presenter,@selector(isInvalidated)); }},
        @"layers":@{@"nativeContextBinding":^BOOL{ return [self nativeLayerBindingReady:h]; }},
        @"events":@{
            @"attached":^BOOL{ return h.hostView.superview!=nil && h.hostView.window!=nil; },
            @"mainScreen":^BOOL{ return h.hostView.window && h.hostView.window.screen==UIScreen.mainScreen; },
            @"windowScene":^BOOL{ return h.hostView.window.windowScene!=nil; },
            @"visible":^BOOL{ return h.hostView.window && !h.hostView.window.hidden; },
            @"windowServerHitTesting":^BOOL{ return DXBool(h.hostView.window,@selector(_usesWindowServerHitTesting)); },
            @"windowContext":^BOOL{ return DXUInt32(h.hostView.window,@selector(_contextId))!=0; },
            @"nativeHitTestBinding":^BOOL{ return [self nativeEventBindingReady:h]; }}
    });
}
