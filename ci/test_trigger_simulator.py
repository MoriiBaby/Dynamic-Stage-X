#!/usr/bin/env python3
"""Real foreground UIKit + XCUI regression. Simulator only; no physical-device actions."""
from pathlib import Path
import argparse
import datetime as dt
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("trigger_project", ROOT / "Tests/TriggerHarness/generate_project.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)
MIN_TESTS = 14


def version(text):
    return tuple(int(n) for n in re.findall(r"\d+", text))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


class Evidence:
    def __init__(self, directory):
        self.directory = directory
        self.commands = []
        self.summary = {"status": "not-run", "passed": False, "simulator_only": True,
                        "physical_device_actions": False,
                        "scope": "public XCUI coordinate touches in a foreground UIKit UIWindowScene; "
                                 "not SpringBoard, scene bridge, remote HID/touch delivery or permission proof",
                        "variants": []}

    def flush(self):
        write_json(self.directory / "trigger-summary.json", self.summary)
        write_json(self.directory / "trigger-commands.json", self.commands)

    def run(self, command, *, label=None, timeout=180, allowed=(0,)):
        label = label or "command-%03d" % (len(self.commands) + 1)
        log_path = self.directory / ("trigger-" + label + ".log")
        record = {"command": [str(x) for x in command], "log": log_path.name,
                  "started_utc": dt.datetime.now(dt.timezone.utc).isoformat()}
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
            text = result.stdout + "\n--- stderr ---\n" + result.stderr
            record["returncode"] = result.returncode
        except subprocess.TimeoutExpired as error:
            out = error.stdout or b""
            err = error.stderr or b""
            text = (out.decode(errors="replace") if isinstance(out, bytes) else out) + "\n" + (
                err.decode(errors="replace") if isinstance(err, bytes) else err)
            record["timeout_seconds"] = timeout
            log_path.write_text(text)
            self.commands.append(record)
            self.flush()
            raise RuntimeError("Timed out: " + label) from error
        log_path.write_text(text)
        self.commands.append(record)
        self.flush()
        if result.returncode not in allowed:
            raise RuntimeError("Command failed (%s): %s; see %s" % (result.returncode, label, log_path))
        return result


def choose_device(evidence, args):
    sdk = evidence.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], label="sdk").stdout.strip()
    runtimes = json.loads(evidence.run(["xcrun", "simctl", "list", "runtimes", "--json"]).stdout)["runtimes"]
    candidates = [r for r in runtimes if r.get("isAvailable") and
                  r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and
                  version(r["version"]) <= version(sdk)]
    if args.runtime:
        candidates = [r for r in candidates if args.runtime in (r["identifier"], r["version"], r["name"])]
    if not candidates:
        raise RuntimeError("No compatible available iOS Simulator runtime; no tests executed")
    runtime = max(candidates, key=lambda r: version(r["version"]))
    types = json.loads(evidence.run(["xcrun", "simctl", "list", "devicetypes", "--json"]).stdout)["devicetypes"]
    runtime_parts = (version(runtime["version"]) + (0, 0))[:3]
    runtime_number = (runtime_parts[0] << 16) + (runtime_parts[1] << 8) + runtime_parts[2]
    types = [t for t in types if t["name"].startswith("iPhone") and
             t.get("minRuntimeVersion", 0) <= runtime_number <= t.get("maxRuntimeVersion", 0xFFFFFFFF)]
    if args.device_type:
        types = [t for t in types if args.device_type in (t["identifier"], t["name"])]
    if not types:
        raise RuntimeError("No iPhone device type compatible with selected runtime")
    preferred = next((t for t in types if t["identifier"].endswith(".iPhone-16-Pro")), types[-1])
    evidence.summary.update(sdk_version=sdk, runtime=runtime, device_type=preferred)
    return runtime, preferred


def snapshot_baseline(work, reference, evidence):
    # git show is read-only: never checkout/reset/change the working tree or either branch.
    commit = evidence.run(["git", "rev-parse", "--verify", reference + "^{commit}"], label="baseline-ref").stdout.strip()
    sources = {}
    folder = work / "baseline-snapshot"
    folder.mkdir()
    for relative in GENERATOR.PRODUCTION:
        source = evidence.run(["git", "show", commit + ":" + relative]).stdout
        target = folder / Path(relative).name
        target.write_text(source)
        sources[relative] = target
    return commit, sources


def execute_variant(work, variant, device, evidence, production=None, baseline_commit=None):
    directory = work / variant
    project = GENERATOR.generate(directory, production=production)
    result_path = evidence.directory / ("trigger-" + variant + ".xcresult")
    report = {"variant": variant, "status": "running", "sources": project["sources"],
              "xcresult": result_path.name, "baseline_commit": baseline_commit}
    evidence.summary["variants"].append(report)
    evidence.flush()
    write_json(evidence.directory / ("trigger-" + variant + "-sources.json"), project["sources"])
    command = ["xcodebuild", "-project", project["project"], "-scheme", project["scheme"],
               "-configuration", "Debug", "-destination", "id=" + device,
               "-destination-timeout", "120", "-derivedDataPath", str(directory / "DerivedData"),
               "-resultBundlePath", str(result_path), "-parallel-testing-enabled", "NO",
               "-maximum-concurrent-test-simulator-destinations", "1", "-test-timeouts-enabled", "YES",
               "-default-test-execution-time-allowance", "60", "-maximum-test-execution-time-allowance", "120",
               "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "test"]
    built = evidence.run(command, label=variant + "-xcodebuild", timeout=1200, allowed=(0, 65))
    # Reject build failures and empty/skipped suites even when xcodebuild happens to return zero.
    parsed = evidence.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)],
                          label=variant + "-xcresult-summary")
    results = json.loads(parsed.stdout)
    write_json(evidence.directory / ("trigger-" + variant + "-tests.json"), results)
    passed, failed, skipped = (int(results.get(key, 0)) for key in ("passedTests", "failedTests", "skippedTests"))
    executed = passed + failed
    complete = executed >= MIN_TESTS and skipped == 0
    report.update(xcodebuild_returncode=built.returncode, passed_tests=passed, failed_tests=failed,
                  skipped_tests=skipped, executed_tests=executed, complete=complete)
    if variant == "fixed":
        # Verify both scratch copies and live working-tree files after the run. No patched copies permitted.
        for relative in GENERATOR.PRODUCTION:
            expected = project["sources"][relative]["sha256"]
            if GENERATOR.sha256(ROOT / relative) != expected or GENERATOR.sha256(directory / "Sources" / Path(relative).name) != expected:
                raise RuntimeError("Production source changed during test: " + relative)
        success = built.returncode == 0 and failed == 0 and complete
        report["status"] = "passed" if success else "failed"
        evidence.flush()
        if not success:
            raise RuntimeError("Fixed XCUI regression failed or incomplete")
    else:
        # Baseline contrast is diagnostic, NEVER counted as an alpha3 pass or required to fail.
        report["status"] = "baseline-tests-failed" if failed else "baseline-tests-passed"
        evidence.flush()
        if not complete:
            raise RuntimeError("Baseline did not execute the complete XCUI suite (possibly build/setup failure)")
    container = evidence.run(["xcrun", "simctl", "get_app_container", device, GENERATOR.BUNDLE_ID, "data"],
                             label=variant + "-container").stdout.strip()
    state = Path(container) / "Documents/trigger-state.json"
    if state.is_file():
        shutil.copyfile(state, evidence.directory / ("trigger-" + variant + "-last-host-state.json"))
    # Per-test counter/coordinate JSON and screenshots are retained in xcresult attachments.
    evidence.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate-only", metavar="DIRECTORY", type=Path,
                        help="Emit project and source hashes only; does NOT run/claim a simulator test")
    parser.add_argument("--evidence-dir", type=Path,
                        help="New empty artifact directory (default: build-evidence/trigger-<UTC>-<suffix>)")
    parser.add_argument("--runtime", help="Available runtime ID, name, or version, e.g. 18.5")
    parser.add_argument("--device-type", help="Device type ID or name, e.g. iPhone 16 Pro")
    parser.add_argument("--baseline-ref", help="Optional independent read-only git snapshot, e.g. b94b666")
    args = parser.parse_args()
    if args.generate_only:
        print(json.dumps({"status": "generated-only-not-executed",
                          **GENERATOR.generate(args.generate_only)}, indent=2))
        return 0
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.evidence_dir or ROOT / "build-evidence" / ("trigger-" + stamp + "-" + uuid.uuid4().hex[:6])).resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Evidence directory must be new/empty; refusing to overwrite previous results")
    output.mkdir(parents=True, exist_ok=True)
    evidence = Evidence(output)
    evidence.summary.update(started_utc=stamp, host_platform=platform.platform())
    evidence.flush()
    device = None
    exit_code = 1
    try:
        if platform.system() != "Darwin" or not shutil.which("xcodebuild") or not shutil.which("xcrun"):
            evidence.summary["reason"] = "Requires macOS + Xcode 16.4/CoreSimulator; no xcodebuild here; NOT EXECUTED"
            return 2
        evidence.summary["xcode"] = evidence.run(["xcodebuild", "-version"], label="xcode-version").stdout.strip()
        evidence.summary["revision"] = evidence.run(["git", "rev-parse", "HEAD"], label="git-head").stdout.strip()
        evidence.summary["working_tree"] = evidence.run(["git", "status", "--short"], label="git-status").stdout
        runtime, device_type = choose_device(evidence, args)
        # This runner never uses 'booted', simctl erase-all, an attached device, or a shared simulator.
        device = evidence.run(["xcrun", "simctl", "create", "DXTrigger-" + uuid.uuid4().hex[:10],
                               device_type["identifier"], runtime["identifier"]], label="sim-create").stdout.strip()
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", device):
            raise RuntimeError("simctl create returned no valid dedicated simulator UUID")
        evidence.summary["simulator_udid"] = device
        evidence.run(["xcrun", "simctl", "boot", device], label="sim-boot")
        evidence.run(["xcrun", "simctl", "bootstatus", device, "-b"], label="sim-bootstatus", timeout=300)
        with tempfile.TemporaryDirectory(prefix="dxtrigger-", dir=os.environ.get("RUNNER_TEMP")) as temporary:
            work = Path(temporary)
            # Fixed is first: do not allow baseline setup to delay the primary regression.
            execute_variant(work, "fixed", device, evidence)
            if args.baseline_ref:
                commit, sources = snapshot_baseline(work, args.baseline_ref, evidence)
                execute_variant(work, "baseline", device, evidence, production=sources, baseline_commit=commit)
        evidence.summary.update(status="passed", passed=True)
        exit_code = 0
    except Exception as error:
        evidence.summary.update(status="failed", passed=False, error=str(error))
        for report in evidence.summary["variants"]:
            if report["status"] == "running":
                report.update(status="failed", error=str(error))
        print(str(error), file=sys.stderr)
    finally:
        if device:
            # Try delete even if shutdown fails; never hide cleanup failures behind test success.
            cleanup_errors = []
            for label, command in (("sim-shutdown", ["xcrun", "simctl", "shutdown", device]),
                                   ("sim-delete", ["xcrun", "simctl", "delete", device])):
                try:
                    evidence.run(command, label=label, allowed=(0, 149) if label == "sim-shutdown" else (0,))
                except Exception as error:
                    cleanup_errors.append(str(error))
            evidence.summary["simulator_deleted"] = not cleanup_errors
            if cleanup_errors:
                evidence.summary.update(status="cleanup-failed", passed=False, cleanup_errors=cleanup_errors)
                exit_code = 1
        evidence.flush()
        print(json.dumps({"status": evidence.summary["status"], "evidence": str(output)}, indent=2))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
