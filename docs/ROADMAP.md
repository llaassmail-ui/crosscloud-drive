# Roadmap

CrossCloud Drive is intended to become a provider-neutral object storage drive mounter for Windows. The first supported provider is Alibaba Cloud International OSS.

## Current Release

- Alibaba Cloud International OSS provider.
- Windows PowerShell 5.1 GUI with Chinese and English language switching.
- rclone and WinFsp based drive mounting.
- Hidden sign-in mount and 5-minute recovery task.
- Per-Windows-user single managed connection.
- RAM policy helper scripts for prefix-limited users and full-bucket administrator identities.
- Local stop, reconnect, and full local connection removal without deleting cloud objects.

## Planned Providers

| Provider | Status | Notes |
|---|---|---|
| Amazon S3 | Planned | Add an S3 provider module, S3-specific validation, and GUI fields. |
| S3-compatible storage | Planned | Reuse the S3 model for providers such as MinIO, Cloudflare R2, and compatible gateways. |
| Google Cloud Storage | Planned | Add a separate provider module and authentication flow. |

## Planned Improvements

- Support multiple saved connections for the same Windows user.
- Add a credential rotation flow.
- Improve diagnostics for rclone, WinFsp, scheduled tasks, and low disk space.
- Add packaged release builds so end users do not need to browse the source tree.
- Expand automated tests around provider-specific configuration.

## Current Limits

- Only Alibaba Cloud International OSS is implemented.
- Each Windows user manages one CrossCloud Drive connection.
- Object storage behavior is not identical to NTFS. Directory markers, rename behavior, file locks, and versioned deletes can differ from a local disk.
- The tool removes local configuration and mount state only. It does not delete cloud-side objects.
