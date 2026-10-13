#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${SNPLG_DEVICE:-}"
MYSTYLE="/storage/emulated/0/MyStyle"
PLUGIN_DIR="plugin"
NO_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) PLUGIN_DIR="$arg" ;;
  esac
done

[ -n "$DEVICE" ] || { echo "set SNPLG_DEVICE (e.g. 192.168.1.50:5555 or a usb serial)" >&2; exit 1; }
[ -d "$REPO_ROOT/$PLUGIN_DIR" ] || { echo "no such plugin directory: $PLUGIN_DIR" >&2; exit 1; }
cd "$REPO_ROOT/$PLUGIN_DIR"

step() { printf '\n==> %s\n' "$*"; }
adb() { command adb -s "$DEVICE" "$@"; }

adb devices | awk -v d="$DEVICE" '$1==d && $2=="device"' >/dev/null || adb connect "$DEVICE" >/dev/null
adb get-state >/dev/null

if [ "$NO_BUILD" = 0 ]; then
  step "building $PLUGIN_DIR"
  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    export PLUGIN_VERSION_CODE="${PLUGIN_VERSION_CODE:-$(git -C "$REPO_ROOT" rev-list --count HEAD)}"
    export PLUGIN_VERSION_NAME="${PLUGIN_VERSION_NAME:-local-$(git -C "$REPO_ROOT" rev-parse --short=7 HEAD)}"
  fi
  ./buildPlugin.sh >/dev/null
fi

SNPLG="$(ls -1 build/outputs/*.snplg 2>/dev/null | head -1)"
[ -n "$SNPLG" ] || { echo "no .snplg in build/outputs/ (run without --no-build?)" >&2; exit 1; }
NAME="$(basename "$SNPLG")"
step "installing $NAME (device $DEVICE)"

UIXML="/tmp/snplg-ui-$$.xml"
trap 'adb shell rm -f /sdcard/_ui.xml >/dev/null 2>&1 || true; rm -f "$UIXML" >/dev/null 2>&1 || true' EXIT

ui_dump() {
  local i
  for i in 1 2 3 4; do
    adb shell input keyevent 224 >/dev/null
    sleep 0.7
    if adb shell uiautomator dump /sdcard/_ui.xml >/dev/null 2>&1 \
       && adb pull /sdcard/_ui.xml "$UIXML" >/dev/null 2>&1 \
       && [ -s "$UIXML" ]; then
      return 0
    fi
    sleep 1
  done
  echo "uiautomator dump failed (screen asleep or mid-transition?)" >&2
  return 1
}

ui_tap_text() {
  local text pt
  for text in "$@"; do
    pt=$(python3 - "$UIXML" "$text" <<'EOF'
import re, sys
xml, target = open(sys.argv[1]).read(), sys.argv[2]
for node in re.findall(r'<node [^>]*?/?>', xml):
    m = re.search(r'text="([^"]*)"', node)
    if not m or m.group(1) != target:
        continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
    if b:
        x1, y1, x2, y2 = map(int, b.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
EOF
    ) || continue
    set -- $pt
    adb shell input tap "$1" "$2"
    sleep 2.5
    return 0
  done
  echo "UI node not found: $*" >&2
  return 1
}

step "pushing to $MYSTYLE"
adb push "$SNPLG" "$MYSTYLE/$NAME" >/dev/null

step "opening Settings -> Plugins"
adb logcat -c 2>/dev/null || true
adb shell am start -n com.ratta.settings/.SettingsActivity \
  -a com.ratta.settings.application.PluginManagerFragment >/dev/null
sleep 3

step "tap: Add Plugin / Choose Installation Package"
ui_dump
ui_tap_text "Add Plugin" "Choose Installation Package" "Select Plugin Package"

step "tap: $NAME"
ui_dump
ui_tap_text "$NAME"

step "tap: Install"
ui_dump
ui_tap_text "Install"

step "waiting for install result"
for _ in $(seq 1 30); do
  LOG="$(adb logcat -d 2>/dev/null | grep -E 'PluginInstallManager|startInstallTask' | tail -20)"
  if echo "$LOG" | grep -q "Install Success"; then
    adb shell input keyevent 3 >/dev/null
    step "INSTALL OK"
    echo "$LOG" | tail -5
    exit 0
  fi
  if echo "$LOG" | grep -qiE "fail|exception|error"; then
    echo "install FAILED:" >&2
    echo "$LOG" >&2
    exit 1
  fi
  sleep 1
done
echo "timed out waiting for install result" >&2
exit 1
