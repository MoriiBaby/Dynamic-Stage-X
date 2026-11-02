# Bridge checks

## Actual local checks

```sh
sh Tests/Bridge/run-local.sh                    # C production tests always; evidence optional
sh Tests/Bridge/run-local.sh --require-evidence # evidence absent -> NOT RUN and exit 2
python3 Tests/Bridge/fetch_evidence.py          # opt-in, fixed public URLs + expected SHA256
```

`run-local.sh` compiles only `DXABIEncoding.c` + `DXLeasePolicy.c` + their actual C test into a temporary `/tmp` directory and removes it. Requires a C11 compiler and Python 3. No iOS/package build, device attach, CI or deployment action. 21,053 checks cover exact signatures, malformed input and exhaustive field-restore ownership masks. Source-declaration/hash checks are provenance checks, **not Objective-C compilation or actual private runtime tests**.

Downloaded `evidence/` remains local research data. For source redistribution EXCLUDE `Tests/Bridge/evidence/**` and `__pycache__`; INCLUDE `evidence-manifest.json`, scripts, production tests and Docs/SYSTEM-API.md. No third-party header contents need be redistributed. All 93 pinned URLs/hashes remain in the manifest; docs contain the most relevant 26. Missing raw headers explicitly print NOT RUN, never PASS. The original exploratory `fetch_additional.py` is not the replay entry point; use `fetch_evidence.py` and the fixed manifest.

## Not executed: required real-iOS acceptance

| Case | Required observation (not inferred from C tests) |
|---|---|
| iOS15 and later, arm64/arm64e | Apple SDK compile/import/link; actual method/protocol encodings logged, no maximum OS gate |
| Two warm apps | Unique main-display scenes, real updates, each App receives its own taps/scrolls inside the pane |
| Cold bottom | Release all, native foreground launch, acknowledge actual scene, acquire both before applying, no ghost hosts |
| Replace bottom | At most 3 temporary leases, at most 2 visible panes; old lease released before new focus |
| Hidden/detached window | apply cannot report interactive readiness; rollback leaves native scene usable |
| Busy apply/focus | Rejected call cannot release/cancel a lease held by another operation |
| Text in both panes | Native focused Scene and PID agree; alternating text never reaches the other App |
| Keyboard varieties | Docked/floating/third-party/hardware keyboard frame authority independently confirmed; SB notification alone is not proof |
| Native focus takeover | Generation changes; release does not restore stale input owner |
| Lock/Home/foreign App | Main invalidation notification, detach own hosts, no scene destruction or forced unlock |
| App exit/restart | Native scene/process observer or active watchdog invalidates old handle; same bundle/PID alone cannot revive it |
| Concurrent/double release | Same restoration result, no premature native activation before restoration confirmation |
| Native field takeover | Changed foreign frame/state is not overwritten; unaffected owned fields restore independently |
| Timeout/late callback | No expired new mutation; late context callback no-op; focus superseding/cancel semantics independently tested |
| Private exception/ABI drift | Remaining cleanup still runs; unknown invalidation token is not guessed or repeatedly registered |
| 100 enter/exit + pressure | No accumulated hosts/observers/assertions; native full-screen behavior restored |

Until those are executed, describe the result as **implemented source candidate**, not validated interactive split screen.
