# Plan — Folder-browsing file picker (issue #2)

## Goal

Let users pick images from any folder under the Supernote root (EXPORT, INBOX,
Document, ...), with breadcrumb navigation and tappable folders.

## Approach

Use the native picker, `RattaFileSelector.selectFile`, instead of a custom
browser. Implemented in `plugin/App.tsx` `openPicker`.

## Verify on device

- Picker opens in SCREENSHOT and can navigate up to the Supernote root and
  into EXPORT / INBOX.
- PNG filter hides other file types; folders remain visible.
- Selecting a file loads it into the crop view; cancel is a no-op.
- Whether `limitPath` is required, and whether the picker works without it.
- Picker renders correctly over the plugin view and returns focus afterwards.

## Fallback

If the native picker is unusable, build a custom browser: list a directory with
`FileUtils.listFiles` (strings only; no is-directory API, so classify by
extension), render breadcrumbs and a folder/image grid.
