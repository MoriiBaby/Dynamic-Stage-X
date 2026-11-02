#!/usr/bin/env python3
"""Generate only URLs/hashes in the documentation, never redistribute header bodies."""
import json,pathlib
root=pathlib.Path(__file__).resolve().parents[2]
manifest=json.loads((root/'Tests/Bridge/evidence-manifest.json').read_text())
names=set('FBScene.h FBSceneManager.h FBSceneLayer.h FBSceneLayerManager.h FBProcess.h SBSceneManagerCoordinator.h SBMainDisplaySceneManager.h SBSceneManager.h UIScenePresentationManager.h _UIScenePresenter.h _UIScenePresentationView.h _UISceneLayerHostContainerView.h _UISceneLayerHostView.h UIMutableScenePresentationContext.h UITransform.h UIMutableTransformer.h UIWindow.h CALayerHost.h SBMainWorkspace.h SBWorkspaceKeyboardFocusController.h FBSceneObserver.h FBProcessManagerObserver.h SBWorkspaceKeyboardFocusControllerObserver.h BKSHIDEventDeliveryManager.h FBSMutableSceneSettings.h'.split())
selected=[v for v in manifest if v['repository']=='MTACS/iOS-17-Runtime-Headers' and pathlib.PurePosixPath(v['path']).name in names]
selected += [v for v in manifest if v['repository']=='nst/iOS-Runtime-Headers' and v['path'].endswith('/FBSceneHostManager.h')]
marker='<!-- PINNED-EVIDENCE-TABLE -->'
doc=root/'Docs/SYSTEM-API.md'
text=doc.read_text().split(marker)[0].rstrip()+'\n\n'+marker+'\n\n'
text+='| Public header / pinned raw URL | SHA256 |\n|---|---|\n'
for v in selected:
    name=pathlib.PurePosixPath(v['path']).name
    text+=f"| [{name}]({v['url']}) | `{v['sha256']}` |\n"
doc.write_text(text)
print(f'Documented {len(selected)} relevant pinned URLs/full SHA256 values; header bodies not copied into Docs or Sources.')
