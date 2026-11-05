#!/usr/bin/env python3
"""Run production ObjC bridge/runtime cleanup under isolated Simulator fault injection.
The private system classes are ABI-mapped fixtures, not evidence of SpringBoard authority.
"""
from pathlib import Path
import hashlib,json,os,platform,plistlib,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build-evidence'; OUT.mkdir(exist_ok=True)
SOURCES=['Sources/System/DXABIEncoding.c','Sources/System/DXLeasePolicy.c',
         'Sources/System/DXRuntime.m','Sources/System/DXSystemBridge.m',
         'Tests/SceneBridge/DXSceneFixtures.m','Tests/SceneBridge/SceneBridgeSmoke.m']
EVIDENCE=SOURCES+['Sources/System/DXRuntime.h','Sources/System/DXSystemBridge.h']
EVIDENCE += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'Sources/System').glob('*.inc'))]
commands=[]
def run(command, timeout=180, allowed=(0,)):
 p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
 commands.append({'command':command,'returncode':p.returncode,'stdout':p.stdout[-20000:],'stderr':p.stderr[-20000:]})
 (OUT/'scene-bridge-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 if p.returncode not in allowed:
  print(p.stdout[-12000:]+p.stderr[-12000:]); raise RuntimeError('Production bridge regression command failed: '+' '.join(command))
 return p.stdout.strip()
def version(text): return tuple(int(p) for p in text.split('.') if p.isdigit())
assert platform.system()=='Darwin','NOT RUN: this regression requires macOS/Xcode, no phone fallback'
arch=platform.machine(); assert arch in ('arm64','x86_64')
sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path'])
sdk_version=run(['xcrun','--sdk','iphonesimulator','--show-sdk-version'])
runtimes=json.loads(run(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtimes=[x for x in runtimes if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and version(x['version'])<=version(sdk_version)]
assert runtimes,'NOT RUN: no compatible available iOS Simulator runtime'
runtime=max(runtimes,key=lambda x:version(x['version']))
sources={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in EVIDENCE}
summary={'passed':False,'scope':'actual production DXRuntime/DXSystemBridge code with isolated ABI-mapped system fixtures and real simulator UIKit; not a real private Scene/device proof',
         'sdk_version':sdk_version,'runtime':runtime['version'],'architecture':arch,'production_sources':sources,'physical_device_actions':False}
device=None
try:
 device=run(['xcrun','simctl','create','DXScene-alpha4','com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro',runtime['identifier']])
 run(['xcrun','simctl','boot',device]); run(['xcrun','simctl','bootstatus',device,'-b'],timeout=300)
 with tempfile.TemporaryDirectory(prefix='dxscene-',dir=os.environ.get('RUNNER_TEMP')) as temporary:
  app=Path(temporary)/'SceneBridgeSmoke.app'; app.mkdir()
  objects=[]
  for index,source in enumerate(SOURCES):
   output=Path(temporary)/(str(index)+'.o'); objects.append(str(output))
   flags=['-fobjc-arc','-fobjc-exceptions','-fexceptions'] if source.endswith('.m') else ['-std=c11']
   run(['xcrun','clang','-target',arch+'-apple-ios15.0-simulator','-isysroot',sdk,
        '-DDX_SCENE_BRIDGE_TESTING=1','-I'+str(ROOT/'Sources/System'),'-I'+str(ROOT/'Tests/SceneBridge'),
        '-Wall','-Wextra','-Wno-unused-parameter',*flags,'-c',str(ROOT/source),'-o',str(output)],timeout=180)
  run(['xcrun','clang','-target',arch+'-apple-ios15.0-simulator','-isysroot',sdk,*objects,
       '-framework','UIKit','-framework','Foundation','-framework','QuartzCore','-o',str(app/'SceneBridgeSmoke')])
  bundle='com.tsangbaby.dynamicstagex.scene-smoke'
  info={'CFBundleIdentifier':bundle,'CFBundleExecutable':'SceneBridgeSmoke','CFBundleName':'SceneBridgeSmoke',
        'CFBundlePackageType':'APPL','CFBundleVersion':'4','CFBundleShortVersionString':'0.1.0',
        'MinimumOSVersion':'15.0','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},
        'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{
            'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'SceneBridgeTest','UISceneDelegateClassName':'DXSceneDelegate'}]}}}
  (app/'Info.plist').write_bytes(plistlib.dumps(info)); run(['codesign','--force','--sign','-',str(app)])
  run(['xcrun','simctl','install',device,str(app)])
  run(['xcrun','simctl','launch','--console','--terminate-running-process',device,bundle],allowed=(0,1),timeout=240)
  container=Path(run(['xcrun','simctl','get_app_container',device,bundle,'data']))
  result=json.loads((container/'Documents/scene-bridge-result.json').read_text())
  (OUT/'scene-bridge-result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
  summary['result']=result
  assert result['passed'] and not result['failures'],result
  assert result['production_cleanup_cycles']>=100 and len(result['cases'])>=10,'Incomplete fault regression'
  assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in sources.items())
  summary['passed']=True
finally:
 if device:
  run(['xcrun','simctl','shutdown',device],allowed=(0,149)); run(['xcrun','simctl','delete',device]); summary['simulator_deleted']=True
 (OUT/'scene-bridge-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
 print(json.dumps(summary,indent=2,ensure_ascii=False))
