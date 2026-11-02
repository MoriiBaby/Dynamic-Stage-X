#!/usr/bin/env python3
"""Preferences source contracts only. Native UIKit smoke is a separate CI test."""
from pathlib import Path
import plistlib,re,subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]
BASE='8dc8c101a93f5adc0387a93ca80077125cba3449'

class PreferencesContract(unittest.TestCase):
    def setUp(self):
        self.source=(ROOT/'Preferences/DXPreferencesController.swift').read_text()
        self.container,self.child=self.source.split('private final class DXSettingsListController:',1)
        self.container=re.sub(r'//[^\n]*','',self.container)
    def test_non_list_preferences_container(self):
        self.assertIn('public final class DXPreferencesController: PSViewController',self.container)
        self.assertNotIn('PSListController',self.container)
        for name in ['numberOfSections','func tableView','UITableViewDataSource','UITableViewDelegate']:
            self.assertNotIn(name,self.container)
        self.assertIn('super.viewDidLoad()',self.container)
    def test_single_child_owns_all_table_callbacks(self):
        self.assertTrue(self.child.lstrip().startswith('UITableViewController'))
        self.assertIn('private var table: UITableView { tableView }',self.child)
        self.assertNotIn('UITableView(frame:',self.source)
        self.assertIn('override func numberOfSections',self.child)
        self.assertIn('section == 0 ? keys.count : 1',self.child)
    def test_containment_order(self):
        add=self.container.index('addChild(contents)')
        view=self.container.index('view.addSubview(contentView)')
        move=self.container.index('contents.didMove(toParent: self)')
        self.assertLess(add,view); self.assertLess(view,move)
        self.assertIn('let contents = DXSettingsListController',self.container)
        self.assertNotIn('private let contents',self.container)
    def test_public_objc_identity_and_bridge(self):
        header=(ROOT/'Preferences/DynamicStageXPrefs-Bridging-Header.h').read_text()
        self.assertIn('@interface PSViewController : UIViewController',header)
        self.assertNotIn('@interface PSListController',header)
        self.assertIn('@objc(DXPreferencesController)',self.container)
        info=plistlib.loads((ROOT/'Preferences/Info.plist').read_bytes())
        self.assertEqual(info['NSPrincipalClass'],'DXPreferencesController')
        self.assertEqual(info['CFBundleVersion'],'2')
        self.assertEqual(info['CFBundleShortVersionString'],'0.1.0-alpha2')
        self.assertEqual(info['MinimumOSVersion'],'15.0')
    def test_keys_and_write_notifications_unchanged(self):
        old=subprocess.check_output(['git','show',BASE+':Preferences/DXPreferencesController.swift'],cwd=ROOT,text=True)
        for prefix in ['    private let keys =','    private let titles =']:
            self.assertEqual(next(x for x in old.splitlines() if x.startswith(prefix)),
                             next(x for x in self.source.splitlines() if x.startswith(prefix)))
        self.assertEqual(old.split('    @objc private func toggleChanged',1)[1],
                         self.source.split('    @objc private func toggleChanged',1)[1])
    def test_no_test_shim_in_production_recipe(self):
        make=(ROOT/'Makefile').read_text()
        self.assertIn('DynamicStageXPrefs_FILES = Preferences/DXPreferencesController.swift',make)
        self.assertNotIn('Tests/Preferences',make)
        self.assertIn('DynamicStageXPrefs_PRIVATE_FRAMEWORKS = Preferences',make)
    def test_only_version_and_preferences_production_changes(self):
        changed=subprocess.check_output(['git','diff',BASE,'--name-only'],cwd=ROOT,text=True).splitlines()
        self.assertFalse(any(x.startswith('Sources/') for x in changed),changed)
        self.assertFalse(any(x.startswith(('Tests/Core/','Tests/Presentation/')) for x in changed),changed)
    def test_no_skip_super_or_dummy_specifiers(self):
        self.assertNotRegex(self.source,r'func specifiers|override.*heightForHeader')
        self.assertNotIn('catch',self.source)
        self.assertNotIn('NSClassFromString',self.source)

if __name__=='__main__':
    print('SOURCE CONTRACT ONLY: real Preferences runtime and UIKit smoke are separate.',flush=True)
    unittest.main(verbosity=2)
