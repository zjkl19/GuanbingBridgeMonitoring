# Remote Machine Inventory

Last updated: 2026-07-04

## Principles

- Prefer SSH or WinRM for automation and sparse status checks.
- Prefer RDP only for manual inspection, GUI debugging, or UAC actions.
- Prefer SMB plus `robocopy` for large intra-LAN data transfer.
- Do not expose RDP, SMB, database ports, or file shares directly to the public
  internet.
- Keep private keys and passwords outside git.

## Machines

| Alias | Host | Role | Preferred access | Current status | Notes |
|---|---:|---|---|---|---|
| `gb-133` | `192.168.100.133` | Main compute worker and MATLAB runner | SSH `dell@192.168.100.133:2222` | Active | Guanbing root `F:\Guanbing`; Zhishan data under `F:\芝山大桥数据`; Hongtang data under `E:\洪塘大桥数据`. |
| `gb-126` | `192.168.100.126` | Large storage server and data source | WinRM as `Administrator`; SMB admin share | Active | Storage target `H:\Guanbingwork`; source exports under `H:\DHtest\定时导出`; RDP currently available through VPN; SSH port 22 timed out from this workstation on 2026-07-01, so keep SSH disabled until repaired. |
| `gb-office` | `192.168.254.34` via `gb-133` | User office workstation, light-duty remote control only | SSH `Administrator@192.168.254.34:2222` with `ProxyJump gb-133` | Active | Device name `DESKTOP-500FVB6`; CPU Hygon C86-3G, RAM 16 GB, GPU Glenfly Arise1020 2 GB. Direct SSH from this workstation is not routable; use 133 as the jump host. Windows `sshd` service is running on TCP 2222 and starts automatically. The earlier fallback task `Guanbing-OpenSSH-2222-OfficePC-Fallback` is left as a manual recovery path only and is not running. Do not schedule heavy MATLAB/report workloads here unless explicitly requested. |
| `site-ipc-*` | TBD | Site industrial PCs | Reverse tunnel or VPN preferred | Planned | If ISP NAT prevents inbound ports, use VPN/overlay or VPS reverse tunnel. |
| `vps-*` | TBD | Optional jump host / reverse tunnel relay | SSH with key-only auth | Planned | Restrict inbound ports and avoid storing bridge data on VPS unless explicitly approved. |

## Guanbing Path Profiles

Machine-specific project paths should be handled by source-controlled
`config/path_profiles.json` plus optional untracked
`config/path_profiles.local.json`, not by editing bridge profiles separately on
each machine.

Current expected behavior:

- local development PC can keep data under `D:\` or `E:\` as needed;
- `gb-133` should resolve production data roots such as `F:\管柄数据`,
  `F:\芝山大桥数据`, and `F:\水仙花大桥数据`;
- if a production host is renamed, the resolver can fall back to an existing
  path match when hostname matching fails;
- the MATLAB GUI shows the active path-profile decision on the run page so the
  user can see whether a path came from profile resolution, a preset, or manual
  input.

## Known Commands

133 SSH:

```powershell
ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no dell@192.168.100.133
```

Office PC SSH setup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\ops\setup_office_pc_openssh_2222.ps1
```

Office PC SSH through 133 jump host:

```powershell
ssh gb-office "hostname; whoami"
ssh -J dell@192.168.100.133:2222 -p 2222 Administrator@192.168.254.34 "hostname; whoami"
```

126 WinRM:

```powershell
$sec = ConvertTo-SecureString '<password>' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('Administrator', $sec)
Invoke-Command -ComputerName 192.168.100.126 -Credential $cred -ScriptBlock {
    hostname
}
```

133 to 126 administrative share:

```powershell
cmd /c "net use \\192.168.100.126\H$ /user:Administrator <password> /persistent:no"
```

126 SSH:

- Not currently a reliable path from this workstation.
- Do not rely on `gb-126` in SSH config until a fresh non-interactive probe
  succeeds.

## Credential Policy

- Store SSH private keys under `%USERPROFILE%\.ssh`.
- Use `docs/ops/ssh_config.template` as a template only.
- Never commit passwords or private keys.
- If a private key is suspected leaked, remove the corresponding public key from
  every remote `authorized_keys` location and replace the key pair.
