# CrossCloud Drive

`CrossCloud Drive` mounts multi-cloud object storage as a Windows drive for Cloud PCs and regular Windows devices. The current version supports Alibaba Cloud International OSS and uses PowerShell, rclone, WinFsp, and Windows Task Scheduler. Future providers are planned for Amazon S3, S3-compatible storage, and Google Cloud Storage through the same provider architecture.

The repository name `crosscloud-drive` is intentionally provider-neutral. Current OSS, RAM, and endpoint documentation refers to the first implemented provider: Alibaba Cloud International OSS.

## Current capabilities

- Chinese and English GUI with instant language switching.
- No Python, Node.js, Go, or other runtime is required.
- Bucket starts empty; OSS path `/` means the entire bucket.
- The default VFS cache limit is `5G`. Choices include `5G`, `10G`, `20G`, and custom values with a `1G` minimum.
- The default directory cache is `1m`, and object modification times are preserved.
- Access is tested before the connection is saved and mounted.
- Hidden sign-in mounting and a hidden recovery check every 5 minutes.
- Separate actions for stop, reconnect, and removing the local device connection.
- Batch generation of RAM prefix policies and administrator full-bucket object policies.

Each Windows user manages one CrossCloud connection. The tool does not take over or terminate rclone processes owned by other software or Windows users. The provider boundary is ready for future Amazon S3, S3-compatible, or GCS providers, but V2 does not implement them yet.

## Provider Status

| Provider | Status | Notes |
|---|---|---|
| Alibaba Cloud International OSS | Supported | Current GUI, CLI, RAM policy scripts, and docs cover this provider. |
| Amazon S3 | Planned | The provider boundary is ready, but implementation is not included yet. |
| S3-compatible storage | Planned | Future support can reuse the S3 parameter model for MinIO, Cloudflare R2, and similar services. |
| Google Cloud Storage | Planned | Planned as a separate provider. |

## Quick start

For regular users, download `CrossCloudDrive-<version>.zip` from GitHub Releases, extract it, and double-click `CrossCloudDrive.exe`. If Windows SmartScreen warns about the unsigned exe, verify that the file came from this repository's Release page and compare it with `SHA256SUMS.txt`.

To run from source:

1. Copy the entire project directory to the target Windows Cloud PC. The GUI loads modules, providers, and locale files from `scripts`; do not copy only one `.ps1` file.
2. Double-click `scripts\start-oss-mount-gui.vbs`. This launcher hides the PowerShell startup window; `.cmd` remains as a compatibility shim.
3. On first use, install rclone and WinFsp from the Connection page.
4. On the Settings page, enter the region, bucket, OSS path, AccessKey ID, and Secret.
5. Select **Test only**, then select **Save and connect** after the access check succeeds.

Start from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\oss-mount-gui.ps1
```

Guides:

- [Chinese user guide](docs/用户使用手册.md)
- [Chinese administrator guide](docs/管理员部署指南.md)
- [English user guide](docs/User-Guide.md)
- [English administrator guide](docs/Administrator-Guide.md)
- [Roadmap](docs/ROADMAP.md)

## Alibaba OSS / RAM Policies

Use one RAM user per employee and restrict object access to a prefix such as `users/<user>/`. Use a full-bucket object policy only for an administrator or NAS account. Never use the Alibaba Cloud root account AccessKey.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<user-a>","<user-b>" `
    -CreateAccessKey
```

For an administrator or NAS identity:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<admin-user>" `
    -PolicyMode FullBucket `
    -CreateAccessKey
```

Alibaba Cloud CLI must already be installed and configured with RAM administration permissions. The generated CSV contains plaintext Secrets. Store it in a password manager, remove it securely after configuration, and never commit it.

## Object Storage Boundaries

Object storage is not NTFS. Folders are usually object-name prefixes; an empty folder can be represented by a directory marker. Directory caching, file locks, random writes, and renames may differ from a local disk. Deletes, overwrites, and versioning can also leave historical storage. Stop and local removal only handle local tasks, processes, remotes, settings, and cache; they do not delete cloud objects.

`--vfs-cache-max-size` is a cleanup target, not a hard disk quota. Uploading or in-use files can temporarily exceed it, and low system-drive space can make writes fail.

## Release security scan

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```

The script runs PowerShell syntax checks, all local tests, and a public-release sensitive-data scan. Field names, policy action names, and scan rules are not credentials. Review any match in context before release.

Do not commit AccessKeys, Secrets, credential CSV files, `rclone.conf`, logs, caches, real bucket names, internal paths, screenshots, or internal personnel information. The `.gitignore` covers common credential and runtime files, but review the release contents manually.

Build local release artifacts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version "0.1.0"
```

Generated `dist/` contents, exe files, zip files, and checksum files are for GitHub Releases only and must not be committed to git.

## License

[MIT](LICENSE)
