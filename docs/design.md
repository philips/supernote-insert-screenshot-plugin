# Insert Screenshot Supernote Plugin — Design

## Purpose

Enable studying Math Academy on a Supernote device without a second device. The
user reads/studies at mathacademy.com/learn in the einkbro web browser,
screenshots a quiz problem, then inserts that screenshot into the currently open
note to solve the problem while referring to it.

## Target workflow

1. Open Math Academy in einkbro web browser.
2. Read/study at mathacademy.com/learn.
3. Screenshot a quiz problem using the top-bar tool.
4. Open Supernote sidebar, tap "Last Opened Note".
5. Tap "Insert Last Screenshot" plugin in the note.
6. Crop the screenshot as needed using native note tools.
7. Solve the problem while referring to the screenshot inside the note.

## Core principle

Speed over configurability. The default action inserts the most recent image in
the SCREENSHOT folder with no prompts and no file picker. Any UX that slows the
capture-to-note loop is opt-in only.

## Behavior

### Default action: Insert Last Screenshot

- Locate the SCREENSHOT folder on device.
- Select the most recently modified image file.
- Insert it onto the current note page at a default position/size.
- No dialogs, no picker.

### Cropping

Cropping is handled in the note using native Supernote tools (resize, move,
lasso, eraser) after insertion. The plugin does not provide a custom crop view.
This keeps the plugin simple and reuses familiar, battery-friendly native tools.

### Optional file picker

A single setting, default off, enables choosing a different screenshot via the
file picker instead of auto-selecting the most recent one. When off, the fast
path is used. When on (or via a secondary/long-press action), the picker opens.

## Edge cases

- SCREENSHOT folder missing or empty: show a brief, non-blocking message.
- Most recent file is not a supported image type: skip to next valid image.
- No note currently open: action is unavailable / no-op with a message.

## Non-goals (v1)

- Custom in-plugin crop UI.
- Editing or annotating the screenshot before insertion.
- Managing or cleaning up the SCREENSHOT folder.

## Platform facts (from sn-plugin-lib 0.1.65)

The plugin is a React Native app packaged as a `.snplg` and installed via the
Supernote Settings plugin manager. Relevant APIs:

- `PluginManager.init()` then `registerButton(type, appTypes, config)` — type `1`
  is the toolbar; `showType: 0` runs an action with no UI, `showType: 1` opens
  the plugin view. `registerButtonListener({onButtonPress})` handles no-UI taps.
- `FileUtils.listFiles(dir)` returns `{path: string}[]`. There is no documented
  mtime field, so "most recent" is determined by the Supernote screenshot naming
  convention `YYYYMMDD_HHMMSS.png` (lexical sort, newest first).
- `PluginCommAPI.getCurrentFilePath()` — verify a `.note` file is open.
- `PluginNoteAPI.saveCurrentNote()` — flush pending edits to disk. Called
  once before `insertImage` (flush user edits) and once after it (flush the
  new element — required for the reload below to pick it up).
- `PluginCommAPI.insertImage(pngPath)` — insert a PNG onto the current
  page/layer. Input must be PNG; screenshots already are.
- `PluginCommAPI.reloadFile()` — refresh the view after insertion.
  With the lasso tool selected the note app performs a full single-page
  reload from disk on this call; without the post-insert save, the inserted
  element is still only in memory and the reload renders the page without
  it (the image is persisted later by autosave and appears on reopen).

## Permissions

Declared in `PluginConfig.json` `uses-permissions`:

- `plugin.permission.FILE:READ` — read the shared-storage SCREENSHOT folder
  (`/storage/emulated/0/SCREENSHOT`).
- `plugin.permission.FILE:WRITE` — insert the image into the current note.

Both are requested at runtime on first use.

## Cropping: platform constraint (confirmed on sn-plugin-lib 0.1.65)

True cropping cannot be done in pure JS:

- No JS API reads raw image bytes/base64 and none writes an arbitrary PNG.
- No image crop/resize API; `insertImage(pngPath)` inserts the whole PNG.
- Supernote provides no in-note crop tools for image objects (move/resize only).
- RN core has no filesystem, WebView/canvas, or `ImageEditor`.

Therefore cropping requires native code. Plan: a small native module
`cropImage(src, dst, x, y, w, h)` (Android `Bitmap`), built via the Supernote RN
template + gradle. The crop rectangle UI itself is pure JS (PanResponder).

Useful native APIs found for the cropper dialog:

- `RattaFileSelector.selectImage()` "Choose alternate screenshot" (native picker).
- `PluginNoteAPI.insertImage(pngPath)` insert the (cropped) result.
- `PluginManager.closePluginView()` the top-left X close button.

## Picker status

The optional picker is wired as a second toolbar button (`showType: 1`) and a
`pickScreenshot()` seam. v1 selects the most recent screenshot inside that seam;
a real chooser UI (list of thumbnails from `listFiles`) is a drop-in replacement
without touching the insertion path.
