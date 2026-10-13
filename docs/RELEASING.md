# Releasing

Releases are built by GitHub Actions from a git tag. You never build or upload a release by hand.

```bash
scripts/release.sh v0.2.0            # checks, asks, tags main, pushes the tag
scripts/release.sh v0.2.0 --dry-run  # only the checks
scripts/release.sh v0.2.0-rc.1       # a pre-release
```

Pushing the tag starts `.github/workflows/release.yml`. When it finishes, the GitHub release
`v0.2.0` exists with `insert-screenshot-v0.2.0.snplg` and its `.sha256` attached, and release notes
generated from the commits since the previous release.

## What the workflow does

Every push to `main`, every pull request touching `plugin/`, and every tag runs the **build** job.
Only tags also run the **release** job.

**build**

1. On a tag: validates it (see below).
2. Computes the plugin version (see below).
3. Typecheck, lint, and the jest suite (`npm ci`, Node 22).
4. The gradle native build (`./gradlew :app:testDebugUnitTest`, JDK 21), which compiles the
   `ImageCrop` module and runs its unit tests (none yet).
5. `./buildPlugin.sh`, with the version stamped into the archive.
6. `verifySnplg.sh` on the result, then `testVerifySnplg.sh` (the verifier's own tests).
7. Uploads the archive as a workflow artifact (14 days), so any main build or PR build can be
   installed on a device without a release.

**release** (tags only)

1. Downloads the archive the build job produced, so what is published is exactly what was tested.
2. Verifies it again, writes a `.sha256`, and runs `gh release create` with generated notes.
   Tags with a suffix (`v1.0.0-rc.1`) are marked as pre-releases.
3. Runs in the `release` environment. To require a human approval before anything is published,
   add required reviewers to that environment in the repository settings (Settings > Environments).

## Versions

| Field | Value | Why |
|---|---|---|
| `versionName` | the tag (`v0.2.0`), or `dev-<sha>` for other builds | shown by the host |
| `versionCode` | `git rev-list --count HEAD` | **must strictly increase**, or Plugin Manager will not upgrade in place |

The committed `plugin/PluginConfig.json` keeps `versionName 0.0.1` / `versionCode 1`; the real
values are stamped into the generated copy at build time (`PLUGIN_VERSION_NAME` and
`PLUGIN_VERSION_CODE` in `buildPlugin.sh`). Do not edit them by hand. `scripts/snplg-deploy.sh`
uses the same scheme (`local-<sha>`, commit count), so a local build installs over a CI build of
the same or an older commit. A bare `./buildPlugin.sh` keeps the committed `0.0.1` / `1`.

A commit count only rises while `main` history is linear. Do not force-push or rewrite `main`
after a release. The workflow also refuses a tag whose commit count does not exceed the previous
release's.

Dev builds use the same scheme, so a newer main build upgrades an older release in place. Going
the other way (an older build over a newer one) is not something the plugin can rely on; if
Plugin Manager refuses, uninstall first (note that this may discard the plugin's data).

## Rules enforced on a tag

The build job fails, before building anything, if:

- the tag is not `vMAJOR.MINOR.PATCH` (optionally `-suffix`);
- the tagged commit is not on `main`;
- the version is not newer than the newest existing `v*` tag (by version order, so `v0.10.0` > `v0.9.0`);
- the commit count did not increase since the previous release.

`scripts/release.sh` checks the same things locally, plus: a clean working tree, being on `main`,
and `main` being pushed and in sync (the release builds what is on GitHub, not what is on your machine).

## The archive verifier

`plugin/verifySnplg.sh` fails the build if the `.snplg` is not something Plugin Manager should
install. It exists because these failures are silent on a device:

- **`reactPackages` missing or wrong.** `buildPlugin.sh` can ship an empty list, which yields a
  plugin that installs but whose `NativeModules.ImageCrop` is `null` (cropping fails at runtime).
  The list must be exactly `com.insertscreenshot.ImageCropPackage`.
- **`pluginID` / `pluginKey` changed.** A new ID installs a second plugin instead of upgrading.
- **Wrong permissions.** Exactly `FILE:READ`, `FILE:WRITE` (the plugin makes no network calls, so
  no `INTERNET`). Adding a permission is a deliberate act: it prompts every user, so change the
  verifier in the same commit.
- **Wrong version** (checked against the values the workflow computed).
- **Unexpected or missing archive entries**, a development JS bundle (`__DEV__` not `false`), a
  bundle under 100 KB, a bundle that does not reference the `ImageCrop` module or register the
  sidebar icon asset, unexpected `.so` files inside `app.npk`, or the
  `ImageCropPackage`/`ImageCropModule` classes missing from the dex files.

`plugin/testVerifySnplg.sh` builds deliberately broken copies of a good archive and checks that each
is rejected for the intended reason. When you add a check to the verifier, add a case there.

Run both locally after a build:

```bash
cd plugin
./buildPlugin.sh
./verifySnplg.sh build/outputs/insert-screenshot.snplg
./testVerifySnplg.sh build/outputs/insert-screenshot.snplg
```

When the plugin legitimately changes (a new native module, a new permission), update the expected
values in `verifySnplg.sh` and `testVerifySnplg.sh`.

## If something goes wrong

- **The build job fails on a tag.** Nothing was published. Fix `main`, then release a *new* version
  (`v0.2.1`). Do not move or reuse a tag; delete the failed tag with
  `git push --delete origin v0.2.0 && git tag -d v0.2.0` only if no release was created from it.
- **A bad release was published.** Delete the GitHub release, and cut a new, higher version with the
  fix. Because `versionCode` only ever goes up, the fix is a new, higher version; do not try to re-issue
  an old one.
- **First run in a fork or new repository.** The `release` environment is created automatically on
  first use; workflow permissions must allow `contents: write` for the release job.

## Not done (yet)

- The `.snplg` is not signed by this pipeline. The `.sha256` only detects corruption; it does not
  protect against someone replacing both files.
- No automatic changelog beyond GitHub's generated notes.
