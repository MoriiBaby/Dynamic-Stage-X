#!/usr/bin/env python3
import concurrent.futures, hashlib, json, pathlib, urllib.request, urllib.error
ROOT=pathlib.Path(__file__).resolve().parent
REPOS={'ios17':('MTACS/iOS-17-Runtime-Headers','d1d960dfaa4107765dd7fcf891e4967c0930d5fd'),'nst':('nst/iOS-Runtime-Headers','fbb634c78269b0169efdead80955ba64eaaa2f21'),'theos':('theos/headers','13c1f17176d7efe6871551cd69a75b71ac4eeaf1')}
SB='SBMainWorkspace SBSceneManagerCoordinator SBWindowSceneManager SBWindowScene SBMainDisplaySceneManager SBSceneManager SBWorkspaceKeyboardFocusController SBLockScreenManager SpringBoard SBWorkspace SBApplicationSceneHandle SBSceneHandle SBSceneLayoutViewController SBKeyboardFocusController'
UI='_UIScenePresenter FBScene UISystemShellApplication UIScenePresentationManager UIScenePresentationContext UIMutableScenePresentationContext _UIScenePresentationView _UISceneLayerHostContainerView UIApplicationSceneSettings UIMutableApplicationSceneSettings _UIContextLayerHostView _UISceneLayerHostView UITransform UITransformer UIMutableTransformer UIWindow'
PROTOCOLS='FBSceneObserver FBSceneManagerObserver FBProcessManagerObserver SBWorkspaceKeyboardFocusControllerObserver UIScenePresenter UIScenePresentation UISceneLayerHostContainerViewDataSource'
def fetch(item):
    key,path=item; repo,sha=REPOS[key]; url=f'https://raw.githubusercontent.com/{repo}/{sha}/{path}'
    try:
        with urllib.request.urlopen(url,timeout=30) as r: data=r.read()
    except urllib.error.HTTPError as e:
        if e.code==404:return
        raise
    dst=ROOT/'evidence'/key/path; dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(data)
def main():
    jobs=[('ios17','Frameworks/QuartzCore.framework/CALayerHost.h'), ('ios17','PrivateFrameworks/FrontBoard.framework/FBSceneLayer.h'), ('ios17','PrivateFrameworks/FrontBoard.framework/FBSceneLayerManager.h'), ('ios17','PrivateFrameworks/BackBoardServices.framework/BKSHIDEventDeliveryManager.h')]
    for key in ['ios17','nst']:
        for name in SB.split(): jobs.append((key,f'PrivateFrameworks/SpringBoard.framework/{name}.h'))
        for name in UI.split(): jobs.append((key,f'PrivateFrameworks/UIKitCore.framework/{name}.h'))
        for name in PROTOCOLS.split(): jobs.append((key,f'protocols/{name}.h'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as p: list(p.map(fetch,jobs))
    manifest=[]
    for key,(repo,sha) in REPOS.items():
        for f in sorted((ROOT/'evidence'/key).rglob('*.h')):
            path=f.relative_to(ROOT/'evidence'/key).as_posix(); data=f.read_bytes()
            manifest.append(dict(repository=repo,revision=sha,path=path,url=f'https://raw.githubusercontent.com/{repo}/{sha}/{path}',sha256=hashlib.sha256(data).hexdigest(),local=f.relative_to(ROOT).as_posix(),bytes=len(data)))
    (ROOT/'evidence'/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Saved',len(manifest),'public headers and SHA256 manifest.')
if __name__=='__main__': main()
