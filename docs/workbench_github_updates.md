# Workbench GitHub Release Updates

## Update channel

The packaged PySide6 workbench uses the public repository
`zjkl19/GuanbingBridgeMonitoring` and the stable GitHub Release channel. It
queries GitHub's `releases/latest` API once per 24 hours after startup and also
provides a manual **检查更新** button. Source/development launches never install
updates automatically.

Git tags alone are not updates. The repository currently has tags through
`v1.7.39` but no GitHub Release. A user will only be offered a newer published,
non-draft, non-prerelease Release with the required assets.

## Required Release assets

For tag `vX.Y.Z`, publish both files with exactly these names:

- `BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip`
- `BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip.sha256`

The ZIP must contain one `BridgeMonitoringWorkbench.exe` and its adjacent
`release_manifest.json`. Use the source repository ZIP only for source review;
it is not a runnable workbench update.

GitHub's Releases API exposes asset download URLs and may expose a platform
`sha256:` digest. The updater accepts that digest or the separately published
`.sha256` asset, then also validates the EXE against the package's internal
release manifest. See GitHub's [Release REST API](https://docs.github.com/en/rest/releases/releases)
and [release-integrity guidance](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity).

## Prepare and publish a stable update

1. Finish local and cross-bridge validation.
2. Set root `VERSION` to a stable version such as `v1.7.40`; development
   suffixes are rejected by default.
3. Commit, push, and create/push the matching tag.
4. Build and package locally from the repository root:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/package_workbench_github_release.ps1
   ```

5. Review `release/workbench/publish_vX.Y.Z.json`, the ZIP SHA256, release
   notes, EXE screenshots, smoke JSON, and release manifest.
6. Publish only after review, for example:

   ```powershell
   gh release create vX.Y.Z `
     release/workbench/BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip `
     release/workbench/BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip.sha256 `
     --verify-tag --title "vX.Y.Z" --notes-file RELEASE_NOTES.md
   ```

Publishing a Release is an external action and is not performed automatically
by the build script.

## Installation and rollback behavior

- Download occurs under `%LOCALAPPDATA%\BridgeMonitoringWorkbench\updates`.
- The ZIP and EXE must pass SHA256 and package-structure checks before the user
  can install.
- Installation only begins after explicit confirmation.
- A detached PowerShell helper waits for the running workbench to exit.
- The current installation is copied to a timestamped sibling backup before
  replacement.
- Existing `config` files are preserved. Config files introduced for the first
  time by a newer package are added, but existing project settings are not
  overwritten.
- The helper starts the new EXE after copying. On failure it attempts to restore
  the backup and writes an update log beside the helper script.

The first production Release should be tested on a disposable copy of the
installed directory before enabling it for routine bridge work.
