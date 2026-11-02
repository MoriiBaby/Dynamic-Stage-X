#!/usr/bin/env python3
"""Local integrity/source-candidate checks, NOT native ABI or behavior verification."""
import argparse,hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--require-evidence',action='store_true',help='Fail if raw downloaded headers are absent')
parser.add_argument('--evidence-root',type=pathlib.Path,default=root/'evidence',help='Alternate local raw-header directory')
args=parser.parse_args()
if not args.evidence_root.is_dir():
    print('NOT RUN: raw public headers are absent (intentionally excluded from source archives); no evidence/hash/declaration PASS claimed')
    raise SystemExit(2 if args.require_evidence else 0)
manifest=json.loads((root/'evidence-manifest.json').read_text())
def local(item):
    return args.evidence_root/pathlib.PurePosixPath(item['local']).relative_to('evidence')
assert manifest
for item in manifest:
    data=local(item).read_bytes()
    assert hashlib.sha256(data).hexdigest()==item['sha256'],item['local']
    assert len(data)==item['bytes']
    assert item['revision'] in item['url']
    assert item['url'].startswith('https://raw.githubusercontent.com/')
required={
 'FBScene.h':['updateSettings:', 'withTransitionContext:', 'isValid'],
 'SBSceneManagerCoordinator.h':['mainDisplaySceneManager'],
 'SBSceneManager.h':['allScenes','existingSceneHandleForScene:'],
 'UIScenePresentationManager.h':['_initWithScene:', 'createPresenterWithIdentifier:'],
 '_UIScenePresenter.h':['modifyPresentationContext:', 'isHosting', 'invalidate'],
 '_UISceneLayerHostContainerView.h':['_hitTest:', '_hostViews','hostedLayers'],
 'SBWorkspaceKeyboardFocusController.h':['sceneWithFocusIncludingSpringBoard','userFocusRequestForScene:','userFocusRequestGeneration','addKeyboardFocusObserver:'],
 'SBMainWorkspace.h':['createRequestForApplicationActivation:', 'executeTransitionRequest:'],
 'FBSceneObserver.h':['sceneDidInvalidate:'],
 'FBProcessManagerObserver.h':['didRemoveProcess:'],
 'SBWorkspaceKeyboardFocusControllerObserver.h':['externalSceneDidAcquireFocus:'],
 'FBSceneLayer.h':['contextID','isKeyboardLayer'],
 'CALayerHost.h':['contextId'],
 'UIWindow.h':['_usesWindowServerHitTesting','_contextId'],
}
for name,terms in required.items():
    files=[local(i) for i in manifest if i['repository']=='MTACS/iOS-17-Runtime-Headers' and i['path'].endswith('/'+name)]
    assert files,name
    text='\n'.join(f.read_text() for f in files)
    assert all(t in text for t in terms),(name,terms)
print(f'PASS: {len(manifest)} pinned public-header SHA256 checks; {len(required)} source-candidate declarations (not runtime verification)')
