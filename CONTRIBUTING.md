# Contributing

Thanks for improving CrossCloud Drive. This project is a Windows PowerShell 5.1 and WinForms tool, so changes should keep the user runtime lightweight and avoid new required dependencies.

## Before Opening a Pull Request

Run the release readiness checks from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```

The check runs PowerShell syntax validation, local tests, and a public-release sensitive-data scan.

## Development Notes

- Keep GUI text in `scripts/locales/zh-CN.psd1` and `scripts/locales/en-US.psd1` instead of hard-coding user-facing strings.
- Keep provider-specific logic in `scripts/providers`; shared mounting, state, task, and removal behavior should stay provider-neutral.
- Do not add cloud deletion commands to local stop, removal, or uninstall flows.
- Do not terminate every `rclone.exe` process. Only touch the exact process managed by this tool.
- Keep Windows PowerShell 5.1 compatibility unless a future release explicitly changes the runtime requirement.

## What Not to Commit

Never commit AccessKeys, Secrets, credential CSV files, `rclone.conf`, logs, caches, real bucket names, internal paths, employee names, screenshots containing private data, or local environment details.
