# Workbench GitHub Release Updates

## Update channel

The packaged PySide6 workbench uses the public repository
`zjkl19/GuanbingBridgeMonitoring` and the stable GitHub Release channel. It
queries GitHub's `releases/latest` API once per 24 hours after startup by default.
The user can disable **自动检查更新** and can always use **立即检查更新**. Source/development launches never install
updates automatically.

Git tags alone are not updates. `v1.8.0-rc1` was the first published GitHub
Pre-release and is intentionally ignored by the stable updater; `v1.8.0` is the
first stable unified-workbench update. A user is offered only a newer published,
non-draft, non-prerelease Release with all required assets.

## Required Release assets

For tag `vX.Y.Z`, publish both files with exactly these names:

- `BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip`
- `BridgeMonitoringWorkbench-vX.Y.Z-win-x64.zip.sha256`

The ZIP must contain one `桥梁健康监测工作平台.exe` and its adjacent
schema-v3 `release_manifest.json`. The manifest inventories every packaged file
except itself with relative path, byte count and SHA256, and pins all required
analysis/report/gate/visual smoke results. Use the source repository ZIP only
for source review; it is not a runnable workbench update.
The required analysis gates include a real compiled automatic-cleaning preview
request with closed request/config/preview SHA provenance and an
extrema-preservation assertion; a package cannot be staged when that gate is
false or absent.
They also include `installed_profile_matrix_smoke`: the frozen EXE must load every
profile in the packaged bridge catalog independently, reproduce the catalog's
report-capable/analysis-only split, and leave every catalog/config/template
asset byte-identical. No fixed bridge count is accepted as a substitute for the
installed catalog.

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
      --verify-tag --title "vX.Y.Z" --notes-file docs/releases/vX.Y.Z.md
   ```

Publishing a Release is an external action and is not performed automatically
by the build script.

## Installation and rollback behavior

- Download occurs under `%LOCALAPPDATA%\BridgeMonitoringWorkbench\updates`.
- The ZIP, EXE and all inventory files must pass SHA256, path, count and
  required-smoke checks before the user can install. Traversal, absolute,
  duplicate-case and symbolic-link ZIP entries are rejected.
- Installation only begins after explicit confirmation.
- The verified staged EXE starts in installer mode and waits for the running
  workbench to exit. No external Python or PowerShell runtime is required.
- If the normal staging path would approach the Windows path limit, extraction
  automatically switches to a short system-temporary staging root.
- A complete candidate directory is built from the current installation,
  obsolete managed runtime files are removed, and the new package is overlaid.
  The candidate is fully revalidated before any live path changes.
- Existing `config` files are preserved. Config files introduced for the first
  time by a newer package are added, but existing project settings are not
  overwritten.
- Unmanaged operator files are preserved. The live install is then renamed to a
  timestamped sibling backup and the verified candidate is activated by an
  atomic directory rename.
- Any failure before or after activation restores the exact old directory and
  writes a JSON update log. On success the installed runtime is revalidated and
  the new EXE is started.
- The “更新备份” action lists recognized transaction backups. Cleanup is never
  automatic: after explicit confirmation it preserves the newest two valid
  backups and removes only older direct siblings whose name, EXE and release
  manifest identity are closed. Invalid or manually named folders are retained.

`scripts/validate_workbench_update_cycle.py` runs the required disposable test
against the real Release ZIP: archive staging, frozen-EXE installation, config
and unmanaged-file retention, stale-runtime removal, all-profile installed
smoke, native screenshot, and fault-injected exact rollback. Run it again for
every stable release candidate before publication.
