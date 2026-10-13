#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

read_json() {
  local file="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // ""' "$file"
  else
    python3 -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8-sig')).get(sys.argv[2],''))" "$file" "$key"
  fi
}

write_json_key() {
  local file="$1" key="$2" value="$3"
  if command -v jq >/dev/null 2>&1; then
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    FILE="$file" KEY="$key" VALUE="$value" python3 - <<'PY'
import json, os
p = os.environ["FILE"]
cfg = json.load(open(p, encoding="utf-8-sig"))
cfg[os.environ["KEY"]] = os.environ["VALUE"]
open(p, "w", encoding="utf-8").write(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
PY
  fi
}

NAME="$(read_json PluginConfig.json name)"
[ -n "$NAME" ] || { echo "PluginConfig.json: missing name" >&2; exit 1; }

GEN="$PROJECT_ROOT/build/generated"
OUT="$PROJECT_ROOT/build/outputs"
rm -rf "$GEN" "$OUT"
mkdir -p "$GEN" "$OUT"

echo "==> bundling $NAME"
npx react-native bundle \
  --entry-file index.js \
  --bundle-output "$GEN/$NAME.bundle" \
  --platform android \
  --assets-dest "$GEN" \
  --dev false

cp PluginConfig.json "$GEN/PluginConfig.json"

if [ -n "${PLUGIN_VERSION_NAME:-}" ]; then
  write_json_key "$GEN/PluginConfig.json" versionName "$PLUGIN_VERSION_NAME"
fi
if [ -n "${PLUGIN_VERSION_CODE:-}" ]; then
  write_json_key "$GEN/PluginConfig.json" versionCode "$PLUGIN_VERSION_CODE"
fi

ICON="$(read_json PluginConfig.json iconPath)"
if [ -n "$ICON" ] && [ -f "$PROJECT_ROOT/$ICON" ]; then
  cp "$PROJECT_ROOT/$ICON" "$GEN/$(basename "$ICON")"
  write_json_key "$GEN/PluginConfig.json" iconPath "/$(basename "$ICON")"
fi

if [ -f "$PROJECT_ROOT/android/settings.gradle" ]; then
  echo "==> building native app.npk"
  export JAVA_HOME="${JAVA_HOME:-$HOME/jdk17}"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
  ( cd "$PROJECT_ROOT/android" && ./gradlew :app:buildPluginNpk --no-daemon )
  cp "$PROJECT_ROOT/android/app/build/outputs/npk/app.npk" "$GEN/app.npk"
fi

echo "==> packaging $NAME.snplg"
( cd "$GEN" && zip -rq "$OUT/$NAME.snplg" . )

echo "==> built $OUT/$NAME.snplg"
