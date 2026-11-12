#!/usr/bin/env python3
"""Run production alpha4 stage preparation/toolbar checks in real Simulator UIKit.
Display-record and plain UIView content are fixtures; not private Scene/touch proof.
"""
from pathlib import Path
import hashlib,json,os,platform,plistlib,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build-evidence'; OUT.mkdir(exist_ok=True)
commands=[]
PRODUCTION=[
 'Sources/Core/DXGeometry.swift','Sources/Presentation/DXPresentationGeometry.swift',
 'Sources/Presentation/DXRoundedPane.swift','Sources/Presentation/DXStageChrome.swift',
 'Sources/Presentation/DXOverlayWindow.swift','Sources/Presentation/DXStageViewController.swift',
 'Sources/Presentation/DXApplicationPickerViewController.swift']
FIXTURES=['Tests/Presentation/Alpha4PickerRecordFixture.swift','Tests/Presentation/DXStageAlpha4Checks.swift',
          'Tests/Presentation/Alpha4StageSmokeApp.swift']
def run(command,timeout=180,allowed=(0,)):
 p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
 commands.append({'command':command,'returncode':p.returncode,'stdout':p.stdout[-12000:],'stderr':p.stderr[-12000:]})
 (OUT/'stage-smoke-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 if p.returncode not in allowed:
  print(p.stdout[-6000:]+p.stderr[-6000:]); raise RuntimeError('Stage smoke command failed: '+' '.join(command))
 return p.stdout.strip()
def version(text): return tuple(int(x) for x in text.split('.') if x.isdigit())
sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path'])
arch=platform.machine(); assert arch in ('arm64','x86_64')
triple=arch+'-apple-ios15.0-simulator'
runtime_list=json.loads(run(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtimes=[x for x in runtime_list if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and version(x['version'])<=version(run(['xcrun','--sdk','iphonesimulator','--show-sdk-version']))]
assert runtimes,'No compatible simulator: test NOT RUN'
runtime=max(runtimes,key=lambda x:version(x['version']))
types=json.loads(run(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
device_type=next(x for x in types if x['identifier']=='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro')
sources={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in PRODUCTION}
device=None
summary={'scope':'real simulator UIKit; ordinary UIView hosts and display-record fixtures; not private Scene or physical-device verification',
 'runtime':runtime['version'],'architecture':arch,'target':'iOS15.0','production_sources':sources,'physical_device_actions':False,'passed':False}
try:
 device=run(['xcrun','simctl','create','DXStage-alpha4',device_type['identifier'],runtime['identifier']])
 run(['xcrun','simctl','boot',device]); run(['xcrun','simctl','bootstatus',device,'-b'],timeout=300)
 with tempfile.TemporaryDirectory(prefix='dxstage-',dir=os.environ.get('RUNNER_TEMP')) as temporary:
  work=Path(temporary); app=work/'StageSmoke.app'; app.mkdir(); binary=app/'StageSmoke'
  run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-sdk',sdk,'-target',triple,
       *[str(ROOT/x) for x in PRODUCTION+FIXTURES],'-framework','UIKit','-framework','Foundation',
       '-framework','QuartzCore','-o',str(binary)],timeout=240)
  bundle='com.tsangbaby.dynamicstagex.stage-smoke'
  info={'CFBundleIdentifier':bundle,'CFBundleExecutable':'StageSmoke','CFBundleName':'StageSmoke',
        'CFBundlePackageType':'APPL','CFBundleVersion':'4','CFBundleShortVersionString':'0.1.0',
        'MinimumOSVersion':'15.0','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},
        'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{
          'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'StageSmoke','UISceneDelegateClassName':'StageSmoke.DXStageAlpha4SmokeScene'}]}}}
  (app/'Info.plist').write_bytes(plistlib.dumps(info)); run(['codesign','--force','--sign','-',str(app)])
  run(['xcrun','simctl','install',device,str(app)])
  run(['xcrun','simctl','launch','--console','--terminate-running-process',device,bundle],allowed=(0,1),timeout=120)
  container=Path(run(['xcrun','simctl','get_app_container',device,bundle,'data']))
  result=json.loads((container/'Documents/result.json').read_text())
  (OUT/'stage-smoke-result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
  summary['result']=result
  assert result['passed'],result
  assert result['checks']>=50,'Incomplete stage smoke'
  assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in sources.items())
  summary['passed']=True
finally:
 if device:
  run(['xcrun','simctl','shutdown',device],allowed=(0,149)); run(['xcrun','simctl','delete',device]); summary['simulator_deleted']=True
 (OUT/'stage-smoke-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
 print(json.dumps(summary,indent=2,ensure_ascii=False))
