#!/usr/bin/env python3
"""Source-only alpha4 contracts; native simulator/build results are separate."""
from pathlib import Path
import re,subprocess,unittest
ROOT=Path(__file__).resolve().parents[1]
BASE='e0b9f8ae40db61987ccd5b1d6f0a036e77da8b3e'
ALLOWED={'Sources/Coordinator/DXCoordinator.swift','Sources/Coordinator/DXFailureNotice.swift',
 'Sources/Core/DXLayoutPolicy.swift','Sources/Presentation/DXStageChrome.swift',
 'Sources/Presentation/DXStageViewController.swift','Sources/Presentation/DXRoundedPane.swift','Sources/System/DXRuntime.h',
 'Sources/System/DXRuntime.m','Sources/System/DXSystemBridge.h','Sources/System/DXSystemBridge.m'}
NEW={'Sources/Core/DXFailurePolicy.swift','Sources/System/DXSceneAcquire.inc',
 'Sources/System/DXSceneReadiness.inc','Sources/System/DXSceneReadinessMethods.inc',
 'Sources/System/DXSceneRecovery.inc','Sources/System/DXSceneRestore.inc'}
class Scope(unittest.TestCase):
 def read(self,path): return (ROOT/path).read_text()
 def test_unrelated_production_files_byte_identical(self):
  names=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
  for name in names:
   if name.startswith('Sources/') and name not in ALLOWED:
    self.assertEqual((ROOT/name).read_bytes(),subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT),name)
 def test_all_system_includes_resolve_and_no_hidden_extra_source(self):
  system=ROOT/'Sources/System'
  for path in system.iterdir():
   if path.suffix not in ('.m','.h','.c','.inc'): continue
   for name in re.findall(r'^#(?:include|import) "([^"]+)"',path.read_text(),re.M):
    self.assertTrue((path.parent/name).is_file(),(path,name))
  for path in (ROOT/'Sources').glob('*/*'):
   if path.suffix in ('.m','.c','.swift','.inc','.h'):
    text=path.read_text(); self.assertNotRegex(text,r'\b(?:TODO|FIXME|fatalError)\b')
 def test_cleanup_contract(self):
  recovery=self.read('Sources/System/DXSceneRecovery.inc')
  self.assertIn('@finally',recovery)
  self.assertIn('removeObjectForKey:h.sceneIdentifier',recovery)
  self.assertIn('releaseAllScenesWithCompletion:',recovery)
  self.assertIn('self.epoch+=1',recovery)
  self.assertIn('[self.recovery removeObject:h]',recovery)
  acquire=self.read('Sources/System/DXSceneAcquire.inc')
  self.assertIn('[self ownedResourceCount]<3',acquire)
  self.assertIn('!self.recovery.count',acquire)
  self.assertIn('DXInitializeObject',acquire)
 def test_readiness_and_error_contract(self):
  bridge=self.read('Sources/System/DXSystemBridge.m')
  readiness=self.read('Sources/System/DXSceneReadinessMethods.inc')
  for group in ['settings','scene','process','presenter','layers','events']:
   self.assertIn('@"'+group+'"',readiness)
  self.assertIn('@selector(isForeground)',readiness)
  self.assertIn('nativeEventBindingReady',readiness)
  runtime=self.read('Sources/System/DXRuntime.m')
  self.assertIn('ns_returns_retained',runtime); self.assertIn('ns_consumed',runtime)
  self.assertIn('DXSceneReadinessKey',runtime); self.assertIn('DXSceneCleanupErrorsKey',runtime)
 def test_preparation_and_ownership_call_sites(self):
  source=self.read('Sources/Coordinator/DXCoordinator.swift')
  self.assertNotIn('window.isUserInteractionEnabled = false',source)
  self.assertIn('bridge.releaseAll',source)
  self.assertIn('DXLayoutPolicy.stage',source)
  self.assertIn('originalFailure',source)
  self.assertIn('DXFailurePolicy.description(primary:',source)
  self.assertIn('self.releaseDetached(handle)',source)
  self.assertIn('self.releaseDetached(lower)',source)
  self.assertNotIn('staging.alpha = 0',source)
 def test_testing_fixtures_excluded_from_production_build(self):
  make=self.read('Makefile')
  self.assertNotIn('Tests/SceneBridge',make)
  self.assertNotIn('DX_SCENE_BRIDGE_TESTING=1',make)
  self.assertNotIn('Tests/Presentation',make)
if __name__=='__main__':
 print('SOURCE CONTRACT ONLY; not actual Scene or UIKit proof.',flush=True)
 unittest.main(verbosity=2)
