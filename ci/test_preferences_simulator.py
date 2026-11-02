#!/usr/bin/env python3
"""Ephemeral iOS Simulator test of production Preferences Swift + real UIKit.
Preferences.framework is replaced only in the test app, so results are not on-device proof.
No user device connection, installation, signing trust change or respring is performed.
"""
from pathlib import Path
import hashlib,json,os,plistlib,platform,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'build-evidence'
REPORTS.mkdir(exist_ok=True)
BASE='8dc8c101a93f5adc0387a93ca80077125cba3449'
log=[]

def run(command, timeout=180, allowed=(0,)):
    p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    log.append({'command':command,'returncode':p.returncode,'stdout':p.stdout[-12000:],'stderr':p.stderr[-12000:]})
    (REPORTS/'preferences-smoke-commands.json').write_text(json.dumps(log,indent=2)+'\n')
    if p.returncode not in allowed:
        print(p.stdout[-6000:]+p.stderr[-6000:])
        raise RuntimeError('Simulator smoke command failed: '+' '.join(command))
    return p.stdout.strip()

def version(text):
    return tuple(int(part) for part in text.split('.') if part.isdigit())

sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path'])
sdk_version=run(['xcrun','--sdk','iphonesimulator','--show-sdk-version'])
arch=platform.machine()
if arch not in ('arm64','x86_64'):
    raise RuntimeError('Unsupported cloud simulator architecture: '+arch)
triple=arch+'-apple-ios15.0-simulator'
runtimes=json.loads(run(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtimes=[r for r in runtimes if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
          and version(r['version'])<=version(sdk_version)]
if not runtimes:
    raise RuntimeError('No available iOS Simulator runtime compatible with selected SDK; smoke NOT RUN')
runtime=max(runtimes,key=lambda r:version(r['version']))
types=json.loads(run(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
types=[t for t in types if t['name'].startswith('iPhone')]
preferred=next((t for t in types if t['identifier']=='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'),None)
if preferred is None:
    preferred=types[-1] if types else None
if preferred is None:
    raise RuntimeError('No iPhone Simulator device type')
device=None
summary={'scope':'real UIKit simulator regression; Preferences parent is a test double, not device Preferences.framework',
         'sdk_version':sdk_version,'runtime':runtime['version'],'device_type':preferred['name'],
         'target':'iOS15.0 simulator','architecture':arch,'device_actions':False,'tests':[]}
try:
    device=run(['xcrun','simctl','create','DynamicStageX-Prefs-alpha2',preferred['identifier'],runtime['identifier']])
    run(['xcrun','simctl','boot',device])
    run(['xcrun','simctl','bootstatus',device,'-b'],timeout=240)
    with tempfile.TemporaryDirectory(prefix='dxprefs-smoke-',dir=os.environ.get('RUNNER_TEMP')) as temporary:
        work=Path(temporary)
        header=ROOT/'Tests/Preferences/PSViewControllerTestShim.h'
        shim=ROOT/'Tests/Preferences/PSViewControllerTestShim.m'
        runner=ROOT/'Tests/Preferences/SmokeApp.swift'
        shim_object=work/'preferences-shim.o'
        run(['xcrun','clang','-target',triple,'-isysroot',sdk,'-fobjc-arc','-c',str(shim),'-o',str(shim_object)])
        baseline=work/'BaselinePreferences.swift'
        baseline.write_text(run(['git','show',BASE+':Preferences/DXPreferencesController.swift'])+'\n')
        for variant,source in [('baseline',baseline),('fixed',ROOT/'Preferences/DXPreferencesController.swift')]:
            bundle_id='com.tsangbaby.dynamicstagex.smoke.'+variant
            app=work/(variant+'.app'); app.mkdir()
            binary=app/'PreferencesSmoke'
            run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-sdk',sdk,'-target',triple,
                 '-import-objc-header',str(header),str(source),str(runner),str(shim_object),
                 '-framework','UIKit','-framework','Foundation','-framework','CoreFoundation','-o',str(binary)])
            info={'CFBundleIdentifier':bundle_id,'CFBundleExecutable':'PreferencesSmoke','CFBundleName':'PreferencesSmoke',
                  'CFBundlePackageType':'APPL','CFBundleVersion':'2','CFBundleShortVersionString':'0.1.0',
                  'MinimumOSVersion':'15.0','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{}}
            (app/'Info.plist').write_bytes(plistlib.dumps(info))
            run(['codesign','--force','--sign','-',str(app)])
            run(['xcrun','simctl','install',device,str(app)])
            command=['xcrun','simctl','launch','--console','--terminate-running-process',device,bundle_id]
            if variant=='baseline': command.append('--baseline')
            run(command,timeout=120,allowed=(0,1))
            container=Path(run(['xcrun','simctl','get_app_container',device,bundle_id,'data']))
            result_path=container/'Documents/result.json'
            if not result_path.is_file():
                raise RuntimeError('Smoke process exited without a result; not accepted')
            result=json.loads(result_path.read_text())
            result['source_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
            result['variant']=variant
            (REPORTS/('preferences-smoke-'+variant+'.json')).write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
            summary['tests'].append(result)
            if not result['passed'] or (variant=='baseline' and result['captured_exception']!='NSRangeException'):
                raise RuntimeError('Preferences simulator regression failed: '+json.dumps(result,ensure_ascii=False))
    summary['passed']=True
    print(json.dumps(summary,indent=2,ensure_ascii=False))
finally:
    if device:
        run(['xcrun','simctl','shutdown',device],allowed=(0,149))
        run(['xcrun','simctl','delete',device])
    (REPORTS/'preferences-smoke-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
