# Implementation Plan — Insert Screenshot Plugin

## Milestone 0: Scaffold & research (DONE)

- Runtime confirmed: React Native + `sn-plugin-lib` 0.1.65, packaged `.snplg`.
- Manifest: `PluginConfig.json` (pluginID, jsMainPath, uses-permissions) +
  `app.json`; entry point `index.js` calling `PluginManager.init()` and
  `registerButton`.
- SCREENSHOT folder: `/storage/emulated/0/SCREENSHOT`, read via
  `FileUtils.listFiles`. FILE:READ required.
- Image insertion: `PluginCommAPI.insertImage(pngPath)` onto the current page;
  FILE:WRITE required; wrap with `saveCurrentNote()` / `reloadFile()`.
- Scaffold created under `plugin/` (manifest, entry point, RN App, src/lib,
  buttons, unit test, build config).

## Build & deploy (DONE)

- `plugin/buildPlugin.sh` bundles RN, copies `PluginConfig.json`, zips to
  `build/outputs/<name>.snplg`. Pure-JS; no gradle/native step.
- `scripts/snplg-deploy.sh` pushes to `MyStyle/` and drives the Settings install
  flow over adb/uiautomator. Auto-stamps versionCode from git commit count.
- See `docs/build-deploy.md`.

## Remaining for Milestone 1

- Add `assets/icon.png` (see `plugin/assets/README.md`).
- `npm install` in `plugin/`, then `./buildPlugin.sh`; deploy and verify
  `insertImage` on-device.
- Confirm the exact SCREENSHOT path and screenshot filename format on the actual
  firmware (adjust `SCREENSHOT_DIR` / sort if needed).

## Milestone 1: Default "Insert Last Screenshot"

- Implement SCREENSHOT folder discovery.
- Implement "most recently modified image" selection (filter by image types).
- Implement insert-image-onto-current-page at a default position/size.
- Wire the plugin's primary action to this flow (no dialogs).

## Milestone 2: Error handling

- Empty/missing folder -> brief non-blocking message.
- No valid image -> skip invalid, message if none remain.
- No open note -> no-op with message.

## Milestone 3: Optional file picker

- Add a setting (default off): "Use file picker to choose screenshot".
- When on, invoke the native file picker instead of auto-selecting.
- Optionally expose picker as a secondary/long-press action regardless of
  setting.

## Milestone 4: Polish

- Verify cropping with native tools works after insertion.
- Validate the end-to-end Math Academy loop on device.
- Document install/usage steps.

## Open questions to resolve during M0

- Exact plugin packaging/install mechanism for the current firmware.
- Whether plugins can write to the current note programmatically, or only via a
  provided insertion API.
- Permissions model for reading the SCREENSHOT folder.
