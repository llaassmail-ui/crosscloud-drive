# Release Checklist

Use this checklist before publishing CrossCloud Drive to GitHub or attaching a release ZIP.

## Repository Checks

- Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1` from the repository root.
- Confirm the repository does not contain AccessKeys, Secrets, credential CSV files, `rclone.conf`, logs, caches, real bucket names, internal paths, employee names, or private screenshots.
- Confirm README links, user guides, administrator guides, and GUI text describe the same behavior.
- Confirm local stop, removal, and uninstall flows do not call cloud object deletion commands.
- Confirm scheduled tasks use hidden launchers and do not leave visible PowerShell windows in normal operation.

## Release ZIP Contents

Build local release artifacts with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version "0.1.0"
```

Attach these generated files to GitHub Releases:

- `dist/CrossCloudDrive-<version>.zip`
- `dist/SHA256SUMS.txt`

Do not commit generated release artifacts to git.

Include:

- `CrossCloudDrive.exe`
- `README.md`
- `README.en.md`
- `LICENSE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `docs/`
- `scripts/`
- `tests/`

Exclude:

- `.git/`
- `.github/` if the ZIP is for end users rather than contributors
- `dist/`
- credential CSV files
- `rclone.conf`
- logs and caches
- generated `.exe` files outside the release zip
- screenshots with private data
- any locally generated ZIP files

## Manual Windows Validation

Before tagging a release, validate on a real Windows desktop or Cloud PC:

- Double-click `scripts\start-oss-mount-gui.vbs` and confirm no startup console remains visible.
- Double-click `CrossCloudDrive.exe` from the generated release directory and confirm the GUI opens.
- Check Chinese and English GUI text at normal and high DPI.
- Install dependency flow, access test, save and connect, stop, reconnect, and remove local connection.
- Confirm a manual stop does not immediately restart during the same sign-in session.
- Confirm sign-in mount and the 5-minute recovery task are hidden.
- Confirm local removal does not delete OSS objects.
