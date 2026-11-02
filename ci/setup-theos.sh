#!/usr/bin/env bash
set -euo pipefail
THEOS_REV=cfba89a53a05b4a1b822121158acc3669c20602f
SDK_REV=0222fd5413cf4b9af096f37b4621afa2688572f7
export THEOS="$RUNNER_TEMP/dynamicstagex-theos"
SDK_REPO="$RUNNER_TEMP/dynamicstagex-sdk"
test ! -e "$THEOS"
test ! -e "$SDK_REPO"
git init "$THEOS"
git -C "$THEOS" remote add origin https://github.com/roothide/theos.git
git -C "$THEOS" fetch --depth=1 origin "$THEOS_REV"
git -C "$THEOS" checkout --detach FETCH_HEAD
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_REV"
git -C "$THEOS" submodule update --init --recursive --jobs 4
# SDK is fixed to an exact source tree; its advertised directory name is not its real SDK version.
git init "$SDK_REPO"
git -C "$SDK_REPO" remote add origin https://github.com/theos/sdks.git
git -C "$SDK_REPO" sparse-checkout init --cone
git -C "$SDK_REPO" sparse-checkout set iPhoneOS16.5.sdk
git -C "$SDK_REPO" fetch --depth=1 --filter=blob:none origin "$SDK_REV"
git -C "$SDK_REPO" checkout --detach FETCH_HEAD
test "$(git -C "$SDK_REPO" rev-parse HEAD)" = "$SDK_REV"
mkdir -p "$THEOS/sdks"
mv "$SDK_REPO/iPhoneOS16.5.sdk" "$THEOS/sdks/"
echo "THEOS=$THEOS" >> "$GITHUB_ENV"
echo "$THEOS/bin" >> "$GITHUB_PATH"
git -C "$THEOS" rev-parse HEAD > build-evidence/theos-revision.txt
git -C "$THEOS" submodule status --recursive > build-evidence/theos-submodules.txt
printf '%s\n' "$SDK_REV" > build-evidence/sdk-revision.txt
python3 - "$THEOS/sdks/iPhoneOS16.5.sdk/SDKSettings.json" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); data=p.read_bytes(); d=json.loads(data)
assert d['Version']=='16.4' and d['CanonicalName']=='iphoneos16.4'
print(json.dumps({'directory':'iPhoneOS16.5.sdk','actual_version':d['Version'],
 'canonical':d['CanonicalName'],'settings_sha256':hashlib.sha256(data).hexdigest()},indent=2))
pathlib.Path('build-evidence/sdk-settings.json').write_bytes(data)
PY
