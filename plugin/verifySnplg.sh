#!/usr/bin/env bash
set -euo pipefail

EXPECT_VERSION_NAME=""
EXPECT_VERSION_CODE=""
ARCHIVE=""

usage() {
  echo "usage: $0 [--expect-version-name NAME] [--expect-version-code CODE] path/to/insert-screenshot.snplg" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-version-name) EXPECT_VERSION_NAME="${2:?}"; shift 2 ;;
    --expect-version-code) EXPECT_VERSION_CODE="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *) if [[ -n "$ARCHIVE" ]]; then usage; fi; ARCHIVE="$1"; shift ;;
  esac
done
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "archive not found: ${ARCHIVE:-<missing>}" >&2; usage; }
for tool in unzip python3; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 2; }; done

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ARCHIVE" -d "$TMP"

ENTRIES="$(cd "$TMP" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
EXPECTED="$(printf '%s\n' \
  PluginConfig.json \
  app.npk \
  drawable-mdpi/assets_icon.png \
  icon.png \
  insert-screenshot.bundle | LC_ALL=C sort)"
if [[ "$ENTRIES" != "$EXPECTED" ]]; then
  echo 'archive entry set mismatch (< expected, > actual):' >&2
  diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ENTRIES") >&2 || true
  exit 1
fi

PLUGIN_CONFIG="$TMP/PluginConfig.json" EXPECT_VERSION_NAME="$EXPECT_VERSION_NAME" \
EXPECT_VERSION_CODE="$EXPECT_VERSION_CODE" python3 - <<'PY'
import json, os, sys

config = json.load(open(os.environ['PLUGIN_CONFIG']))
errors = []

def expect(key, value):
    if config.get(key) != value:
        errors.append(f"{key} must be {value!r}, got {config.get(key)!r}")

expect('pluginID', '0sndxkrq54kv1uk7')
expect('pluginKey', 'insert-screenshot')
expect('jsMainPath', 'index')
expect('nativeCodePackage', '/app.npk')

permissions = sorted(config.get('uses-permissions', []))
wanted = sorted(['plugin.permission.FILE:READ', 'plugin.permission.FILE:WRITE'])
if permissions != wanted:
    errors.append(f"permissions must be exactly {wanted}, got {permissions}")

packages = sorted(config.get('reactPackages', []))
wanted_packages = sorted(['com.insertscreenshot.ImageCropPackage'])
if packages != wanted_packages:
    errors.append(f"reactPackages must be exactly {wanted_packages}, got {packages}")

name, code = os.environ['EXPECT_VERSION_NAME'], os.environ['EXPECT_VERSION_CODE']
if name and config.get('versionName') != name:
    errors.append(f"versionName {config.get('versionName')!r} != expected {name!r}")
if code and str(config.get('versionCode')) != code:
    errors.append(f"versionCode {config.get('versionCode')!r} != expected {code!r}")
if not str(config.get('versionCode', '')).isdecimal():
    errors.append(f"versionCode must be a decimal string, got {config.get('versionCode')!r}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
PY

NPK="$TMP/app.npk"
NPK_ENTRIES="$(unzip -Z1 "$NPK")"
grep -q '^classes.*\.dex$' <<<"$NPK_ENTRIES" || fail 'app.npk contains no classes.dex'

UNEXPECTED_SO="$(grep -E '\.so$' <<<"$NPK_ENTRIES" || true)"
[[ -z "$UNEXPECTED_SO" ]] || fail "app.npk contains unexpected native libraries: $UNEXPECTED_SO"

NPK_DIR="$TMP/npk"
mkdir -p "$NPK_DIR"
unzip -q "$NPK" -d "$NPK_DIR"
for cls in com/insertscreenshot/ImageCropPackage com/insertscreenshot/ImageCropModule; do
  grep -a -l "$cls" "$NPK_DIR"/classes*.dex >/dev/null 2>&1 || fail "class $cls not found in app.npk"
done

BUNDLE="$TMP/insert-screenshot.bundle"
[[ "$(wc -c <"$BUNDLE")" -gt 100000 ]] || fail 'JS bundle is suspiciously small'
grep -qF 'ImageCrop' "$BUNDLE" || fail 'JS bundle does not reference the ImageCrop native module'
grep -qF 'registerAsset' "$BUNDLE" || fail 'JS bundle does not register the sidebar icon asset'
head -c 600 "$BUNDLE" | grep -qF '__DEV__=false' || fail 'JS bundle is not a production build (expected __DEV__=false; bundle with --dev false)'

echo "OK: $(basename "$ARCHIVE") (version ${EXPECT_VERSION_NAME:-<unchecked>}/${EXPECT_VERSION_CODE:-<unchecked>}, pluginID 0sndxkrq54kv1uk7)"
