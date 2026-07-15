# 360 Cloud-Disk Transfer Runbook

Last verified: 2026-07-15

## Scope and security boundary

- Official CLI package: `@aicloud360/360-ai-cloud-disk-cli` `0.8.37`.
- The API key must exist only in the current process environment as `API_KEY`.
  Do not put it in this repository, a command line, a scheduled task, a status
  file, or a remote configuration file.
- CLI `0.8.37` can print credential and access-token fields in debug output even
  with `--quiet`. Always call it through `scripts/invoke_360disk_transfer.ps1`,
  which suppresses raw CLI output and emits only a sanitized JSON result.
- Every transfer is accepted only after the destination SHA256 matches the
  source SHA256.

## Installed runtime

- Local development machine: the wrapper resolves the bundled Codex Node
  runtime and the locally validated CLI deployment. Explicit paths can be
  supplied with `-NodePath` and `-CliPath`.
- Machine 133: isolated portable runtime only, with no system installation:
  `F:\Guanbing_v1.8.1-rc1\tools\360disk-portable`.
- The same wrapper is deployed on 133 at
  `F:\Guanbing_v1.8.1-rc1\tools\invoke_360disk_transfer.ps1`.
- Stable production `F:\Guanbing` and source-data trees are not used for tools,
  credentials, logs, or transfer staging.

## Network-mode policy

- The local machine is not using V2Ray TUN mode; its public default route is
  WLAN. Node/360disk normally connects directly and does not use the Windows
  system proxy unless `NODE_USE_ENV_PROXY=1` is set.
- `auto` uses direct mode for uploads. For downloads, if a process proxy is
  configured, it tries proxy mode first and direct mode as an outer retry.
- Do not globally disable the VPN and do not set `NODE_USE_ENV_PROXY=1` for all
  applications. The wrapper changes only its child-process environment and
  restores the previous values afterward.

## Verified commands

The caller must inject `API_KEY` into the current process before either command.
The examples intentionally contain no credential value.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\invoke_360disk_transfer.ps1 `
  -Action upload `
  -LocalPath D:\path\artifact.zip `
  -RemoteDirectory /中转/Guanbing/
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\invoke_360disk_transfer.ps1 `
  -Action download `
  -Nid 1234567890 `
  -DownloadDirectory D:\path\download
```

The JSON result records the effective network mode, attempt count, byte count,
elapsed time, MiB/s, Mbit/s, and SHA256. A non-zero exit means the artifact is
not accepted.

## 2026-07-15 pilot results

All payloads were new 8 MiB cryptographically random files so compression or
deduplication could not create a false speed result.

- Local upload, default direct path: four successful runs ranged from
  `0.066` to `0.319 MiB/s`; median `0.176 MiB/s`. One 55.6 MB package attempt
  failed after an upload-node connection timeout and a broken internal retry.
- Local upload, V2Ray explicitly forced: `0.123` and `0.197 MiB/s`. This is
  within the very large direct-path variance, so V2Ray is not the primary cause
  of slow CLI uploads.
- 360 signed-link download to 133: `3.148 MiB/s` (`26.405 Mbit/s`), SHA256
  matched.
- 133 direct CLI upload: `0.285 MiB/s` (`2.389 Mbit/s`).
- Local direct CLI download failed twice with `fetch failed`. A proxied retry
  succeeded at `0.558 MiB/s`; the hardened wrapper later succeeded at
  `0.169 MiB/s`. Both successful downloads matched the 133 source SHA256.

The dominant issue is high jitter and intermittent connectivity between this
local network and the 360 upload/download nodes, plus weak retry behavior in
CLI `0.8.37`. VIP membership is recognized by the service but did not remove
this CLI/API-path bottleneck. Treat these as preliminary small-file results;
repeat with a 1-2 GiB random artifact after Jiulongjiang cache production is
finished before choosing 360 as the default bulk-data route.

The disposable evidence directory is currently retained for review at
`/中转/Guanbing_Codex_Test_20260715_1430/`. Delete it only after the user no
longer needs the benchmark artifacts.
