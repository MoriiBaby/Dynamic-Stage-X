#!/usr/bin/env python3
"""Generate a dependency-free Xcode app + public XCUI test project in a scratch directory."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = (
    "Sources/Presentation/DXEdgeTriggerWindow.swift",
    "Sources/Presentation/DXPresentationGeometry.swift",
)
BUNDLE_ID = "com.dynamicstagex.triggerharness"
SCHEME = "TriggerHarness"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def generate(destination, production=None):
    """Copy byte-identical sources, record hashes, and emit an ordinary PBX project."""
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    source_dir = destination / "Sources"
    source_dir.mkdir()
    manifest = {}
    for relative in PRODUCTION:
        original = Path(production[relative]) if production else ROOT / relative
        copied = source_dir / Path(relative).name
        shutil.copyfile(original, copied)
        assert sha256(original) == sha256(copied)
        manifest[relative] = {"sha256": sha256(original), "copy_sha256": sha256(copied)}
    harness = ROOT / "Tests/TriggerHarness"
    for name in ("TriggerHarnessApp.swift", "TriggerHarnessUITests.swift"):
        shutil.copyfile(harness / name, source_dir / name)
        manifest["Tests/TriggerHarness/" + name] = {"sha256": sha256(source_dir / name)}

    info = {
        "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.3",
        "LSRequiresIPhoneOS": True, "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                "UISceneConfigurationName": "TriggerHarness",
                "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).TriggerHarnessScene"
            }]}
        }
    }
    (destination / "App-Info.plist").write_bytes(plistlib.dumps(info))
    objects = {}

    def ident(name):
        return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

    def add(name, isa, fields):
        key = ident(name)
        objects[key] = "{ isa = " + isa + "; " + fields + " };"
        return key

    def q(value):
        return json.dumps(str(value))

    def listing(values):
        return "(" + ", ".join(values) + ("," if values else "") + ")"

    def config_list(name, settings):
        configs = []
        for mode in ("Debug",):
            values = dict(settings)
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
            fields = " ".join(q(k) + " = " + q(v) + ";" for k, v in values.items())
            configs.append(add(name + mode, "XCBuildConfiguration",
                               "buildSettings = { " + fields + " }; name = " + mode + ";"))
        return add(name + "config-list", "XCConfigurationList",
                   "buildConfigurations = " + listing(configs) +
                   "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;")

    files = {}
    builds = {}
    for name in ("DXEdgeTriggerWindow.swift", "DXPresentationGeometry.swift",
                 "TriggerHarnessApp.swift", "TriggerHarnessUITests.swift"):
        files[name] = add(name, "PBXFileReference", "lastKnownFileType = sourcecode.swift; path = " +
                          q("Sources/" + name) + "; sourceTree = \"<group>\";")
        builds[name] = add(name + "build", "PBXBuildFile", "fileRef = " + files[name] + ";")
    app_product = add("app-product", "PBXFileReference",
                      'explicitFileType = wrapper.application; path = TriggerHarness.app; sourceTree = BUILT_PRODUCTS_DIR;')
    test_product = add("test-product", "PBXFileReference",
                       'explicitFileType = wrapper.cfbundle; path = TriggerHarnessUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", "PBXGroup", "children = " + listing([app_product, test_product]) +
                   '; name = Products; sourceTree = "<group>";')
    main = add("main", "PBXGroup", "children = " + listing(list(files.values()) + [products]) +
               '; sourceTree = "<group>";')
    common = {
        "SDKROOT": "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "15.0", "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphonesimulator",
        "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO",
        "CLANG_ENABLE_MODULES": "YES", "ENABLE_TESTABILITY": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"
    }
    project_configs = config_list("project", common)
    app_configs = config_list("app", {
        "PRODUCT_NAME": "TriggerHarness", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "INFOPLIST_FILE": "App-Info.plist", "GENERATE_INFOPLIST_FILE": "NO"
    })
    test_configs = config_list("test", {
        "PRODUCT_NAME": "TriggerHarnessUITests", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".uitests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "TriggerHarness"
    })
    app_id, test_id = ident("app-target"), ident("test-target")
    proxy = add("proxy", "PBXContainerItemProxy", "containerPortal = " + ident("project") +
                "; proxyType = 1; remoteGlobalIDString = " + app_id + "; remoteInfo = TriggerHarness;")
    dependency = add("dependency", "PBXTargetDependency", "target = " + app_id + "; targetProxy = " + proxy + ";")
    for name, target_id, product, configs, sources, kind in (
        ("TriggerHarness", app_id, app_product, app_configs,
         [builds[n] for n in builds if n != "TriggerHarnessUITests.swift"], "application"),
        ("TriggerHarnessUITests", test_id, test_product, test_configs,
         [builds["TriggerHarnessUITests.swift"]], "bundle.ui-testing")
    ):
        phases = []
        for suffix, isa, members in (("sources", "PBXSourcesBuildPhase", sources),
                                     ("frameworks", "PBXFrameworksBuildPhase", []),
                                     ("resources", "PBXResourcesBuildPhase", [])):
            phases.append(add(name + suffix, isa, "buildActionMask = 2147483647; files = " +
                              listing(members) + "; runOnlyForDeploymentPostprocessing = 0;"))
        add("app-target" if target_id == app_id else "test-target", "PBXNativeTarget",
            "buildConfigurationList = " + configs + "; buildPhases = " + listing(phases) +
            "; buildRules = (); dependencies = " + listing([dependency] if target_id == test_id else []) +
            "; name = " + name + "; productName = " + name + "; productReference = " + product +
            '; productType = "com.apple.product-type.' + kind + '";')
    project = add("project", "PBXProject", "attributes = { LastUpgradeCheck = 1640; TargetAttributes = { " +
                  app_id + " = { CreatedOnToolsVersion = 16.4; }; " + test_id +
                  " = { CreatedOnToolsVersion = 16.4; TestTargetID = " + app_id + "; }; }; }; " +
                  "buildConfigurationList = " + project_configs +
                  '; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); ' +
                  "mainGroup = " + main + "; productRefGroup = " + products +
                  '; projectDirPath = ""; projectRoot = ""; targets = ' + listing([app_id, test_id]) + ";")
    xcodeproj = destination / (SCHEME + ".xcodeproj")
    xcodeproj.mkdir()
    body = "\n".join(key + " = " + value for key, value in objects.items())
    (xcodeproj / "project.pbxproj").write_text(
        "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" +
        body + "\n}; rootObject = " + project + "; }\n")

    def reference(parent, target, product_name, name):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName=product_name, BlueprintName=name, ReferencedContainer="container:" + xcodeproj.name)

    scheme = ET.Element("Scheme", LastUpgradeVersion="1640", version="1.3")
    action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="NO", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    for target, product_name, name in ((app_id, "TriggerHarness.app", SCHEME),
                                        (test_id, "TriggerHarnessUITests.xctest", "TriggerHarnessUITests")):
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="NO",
                              buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="YES")
        reference(entry, target, product_name, name)
    tests = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug",
                          selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                          selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB",
                          shouldUseLaunchSchemeArgsEnv="YES")
    testable = ET.SubElement(ET.SubElement(tests, "Testables"), "TestableReference", skipped="NO", parallelizable="NO")
    reference(testable, test_id, "TriggerHarnessUITests.xctest", "TriggerHarnessUITests")
    shared = xcodeproj / "xcshareddata/xcschemes"
    shared.mkdir(parents=True)
    ET.ElementTree(scheme).write(shared / (SCHEME + ".xcscheme"), encoding="utf-8", xml_declaration=True)
    (destination / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return {"project": str(xcodeproj), "scheme": SCHEME, "sources": manifest}
