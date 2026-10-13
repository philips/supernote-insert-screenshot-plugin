#!/usr/bin/env bash
set -euo pipefail

GOOD="${1:?usage: $0 path/to/good.snplg}"
HERE="$(cd "$(dirname "$0")" && pwd)"
verify() { bash "$HERE/verifySnplg.sh" "$@"; }
WORK="$(mktemp -d)"
trap '[[ -n "${KEEP_WORK:-}" ]] || rm -rf "$WORK"' EXIT

passed=0
failed=0

mutate() {
  local name="$1" snippet="$2"
  GOOD="$GOOD" OUT="$WORK/$name.snplg" SNIPPET="$snippet" python3 - <<'PY'
import io, json, os, zipfile
files = {}
with zipfile.ZipFile(os.environ['GOOD']) as z:
    for info in z.infolist():
        if not info.is_dir():
            files[info.filename] = z.read(info.filename)
def config():
    return json.loads(files['PluginConfig.json'])
def set_config(c):
    files['PluginConfig.json'] = (json.dumps(c, indent=2) + "\n").encode()
def edit_npk(fn):
    src = zipfile.ZipFile(io.BytesIO(files['app.npk']))
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as dst:
        entries = {i.filename: src.read(i.filename) for i in src.infolist() if not i.is_dir()}
        fn(entries)
        for k, v in entries.items():
            dst.writestr(k, v)
    files['app.npk'] = out.getvalue()
exec(os.environ['SNIPPET'])
with zipfile.ZipFile(os.environ['OUT'], 'w', zipfile.ZIP_DEFLATED) as z:
    for k, v in files.items():
        z.writestr(k, v)
PY
}

expect_reject() {
  local name="$1" desc="$2"; shift 2
  if verify "$@" "$WORK/$name.snplg" >"$WORK/$name.log" 2>&1; then
    echo "FAIL (accepted a bad archive): $desc"; failed=$((failed + 1))
  else
    echo "ok   rejects: $desc"; passed=$((passed + 1))
  fi
}

if verify "$GOOD" >/dev/null 2>&1; then echo "ok   accepts the good archive"; passed=$((passed + 1))
else echo "FAIL: good archive rejected"; verify "$GOOD" || true; failed=$((failed + 1)); fi

mutate empty_packages "c = config(); c['reactPackages'] = []; set_config(c)"
expect_reject empty_packages "empty reactPackages"

mutate missing_package "c = config(); c['reactPackages'].remove('com.insertscreenshot.ImageCropPackage'); set_config(c)"
expect_reject missing_package "native package missing from reactPackages"

mutate extra_package "c = config(); c['reactPackages'].append('com.example.Evil'); set_config(c)"
expect_reject extra_package "unexpected extra native package"

mutate wrong_id "c = config(); c['pluginID'] = 'aaaaaaaaaaaaaaaa'; set_config(c)"
expect_reject wrong_id "changed pluginID"

mutate wrong_key "c = config(); c['pluginKey'] = 'other'; set_config(c)"
expect_reject wrong_key "changed pluginKey"

mutate less_perms "c = config(); c['uses-permissions'].remove('plugin.permission.FILE:READ'); set_config(c)"
expect_reject less_perms "missing FILE:READ permission"

mutate more_perms "c = config(); c['uses-permissions'].append('plugin.permission.FILE:DELETE'); set_config(c)"
expect_reject more_perms "unexpected extra permission"

mutate no_native "c = config(); del c['nativeCodePackage']; set_config(c)"
expect_reject no_native "nativeCodePackage missing"

mutate bad_code "c = config(); c['versionCode'] = 'abc'; set_config(c)"
expect_reject bad_code "non-numeric versionCode"

mutate extra_file "files['secrets.txt'] = b'x'"
expect_reject extra_file "unexpected file in the archive"

mutate missing_bundle "del files['insert-screenshot.bundle']"
expect_reject missing_bundle "missing JS bundle"

mutate tiny_bundle "files['insert-screenshot.bundle'] = b'__DEV__=false'"
expect_reject tiny_bundle "truncated JS bundle"

mutate so_in_npk "edit_npk(lambda e: e.__setitem__('lib/arm64-v8a/libhermes.so', b'x'))"
expect_reject so_in_npk "native library inside app.npk"

mutate no_dex "edit_npk(lambda e: [e.pop(k) for k in [k for k in e if k.endswith('.dex')]])"
expect_reject no_dex "app.npk without dex files"

mutate no_class "edit_npk(lambda e: [e.__setitem__(k, v.replace(b'com/insertscreenshot/ImageCropModule', b'com/insertscreenshot/XxxxxxxxxxxxxxModule')) for k, v in list(e.items()) if k.endswith('.dex')])"
expect_reject no_class "own native module class missing from the dex files"

mutate has_apk "files['app-release.apk'] = b'x'"
expect_reject has_apk "an APK smuggled into the archive"

GOOD_NAME="$(unzip -p "$GOOD" PluginConfig.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["versionName"])')"
GOOD_CODE="$(unzip -p "$GOOD" PluginConfig.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["versionCode"])')"
if verify --expect-version-name "$GOOD_NAME" --expect-version-code "$GOOD_CODE" "$GOOD" >/dev/null 2>&1; then
  echo "ok   accepts matching --expect-version-*"; passed=$((passed + 1))
else echo "FAIL: matching version expectation rejected"; failed=$((failed + 1)); fi
cp "$GOOD" "$WORK/good.snplg"
expect_reject good "wrong --expect-version-name" --expect-version-name "not-$GOOD_NAME"
expect_reject good "wrong --expect-version-code" --expect-version-code "99999999"

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
