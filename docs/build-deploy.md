# Build & Deploy

The plugin bundles a native Android module (`ImageCrop`) for image cropping, so
packaging is: bundle the React Native code, build `app.npk` with gradle, copy
`PluginConfig.json`, and zip everything into a `.snplg`.

## Prerequisites

- Node 18+ and `npm install` run inside `plugin/`.
- `zip` and `python3` (or `jq`) on PATH.
- `adb` on PATH for deploying, with the Supernote reachable over USB or Wi-Fi.
- `plugin/assets/icon.png` present (referenced by `index.js`).
- JDK 17 and the Android SDK (platform 35, build-tools 35) for the native build.
  `buildPlugin.sh` defaults `JAVA_HOME=$HOME/jdk17` and
  `ANDROID_HOME=$HOME/Android/Sdk`; override via env if yours differ.

## Native module

`android/` is a minimal Android app whose only job is to produce `app.npk` (a
debug APK with native `.so` libs stripped). `ImageCropModule` exposes
`imageSize(path)` and `crop(src, x, y, w, h)` to JS via `NativeModules.ImageCrop`.
`PluginConfig.json` registers it with `reactPackages` +
`nativeCodePackage: /app.npk`.

> After deploying new native code, force-stop the plugin host so the new dex
> loads: `adb shell am force-stop com.ratta.supernote.pluginhost`. The deploy
> path reinstall usually restarts it, but force-stop to be certain.

## Build

```sh
cd plugin
./buildPlugin.sh
```

Outputs `plugin/build/outputs/insert-screenshot.snplg`.

Optional version stamping (used by the deploy script automatically):

- `PLUGIN_VERSION_NAME` — any string, written to `versionName`.
- `PLUGIN_VERSION_CODE` — integer, written to `versionCode`. Must strictly
  increase for the device to upgrade in place, otherwise the installer rejects
  it with errorCode 103 "Plugin Version is low".

## Deploy

```sh
export SNPLG_DEVICE=192.168.1.50:5555   # or a USB serial from `adb devices`
scripts/snplg-deploy.sh
```

What it does:

1. Builds the `.snplg` (skip with `--no-build`).
2. `adb push` it to `/storage/emulated/0/MyStyle/`.
3. Opens Settings → Plugins and drives the Add Plugin → file → Install flow via
   `uiautomator` (no root needed).
4. Waits for `PluginInstallManager: Install Success` in logcat.

Re-running installs over the same `pluginID` as an in-place upgrade; no uninstall
needed. The deploy script auto-sets `PLUGIN_VERSION_CODE` from the git commit
count so a fresh build always upgrades the previous one.

### Flags / env

- `scripts/snplg-deploy.sh --no-build` — install the existing `.snplg`.
- `scripts/snplg-deploy.sh <dir>` — use a different plugin directory (default
  `plugin`).
- `SNPLG_DEVICE` — required; adb serial or `host:port`.

## CI (GitHub Actions)

`.github/workflows/release.yml` runs on every push to `main`, every pull
request, and manually. It reproduces the local build: `tsc`, `eslint`, `jest`,
gradle `:app:testDebugUnitTest` (compiles the native module), then
`buildPlugin.sh` stamped with the CI version and `verifySnplg.sh` on the
result. The `.snplg` is uploaded as a workflow artifact (14-day retention).

Version stamping: `versionCode` is the git commit count, so each newer commit
produces a higher code that upgrades in place; branch builds get
`versionName` `dev-<short sha>`.

Pushing a tag like `v0.1.0` (only from `main`, only newer than any existing
tag) additionally publishes the exact verified archive as a GitHub release
with a `.sha256` checksum; `-suffix` tags (e.g. `v0.1.0-rc.1`) are published
as pre-releases. Publishing runs in the `release` environment, so required
reviewers can be added there in the repo settings to gate releases.
