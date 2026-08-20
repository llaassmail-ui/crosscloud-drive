# CrossCloud Drive V2 Administrator Guide

This guide covers Alibaba Cloud International OSS, RAM access, Windows deployment, lifecycle behavior, and local removal. V2 supports Alibaba OSS only. Each Windows user has one connection managed by CrossCloud Drive; unrelated rclone processes are not controlled or terminated.

## 1. Recommended Architecture

Use a private bucket and isolate employees by object prefix:

```text
<bucket-name>/
  users/
    <user-a>/
    <user-b>/
  shared/
```

Use a separate RAM user and AccessKey for every employee. Grant prefix access to normal users and full-bucket object access only to administrator or NAS identities. Never distribute the Alibaba Cloud root-account AccessKey.

OSS-managed encryption can protect objects at rest. Authorized downloads are transparently decrypted and return the original content. If versioning is enabled, configure lifecycle rules for historical versions, expired delete markers, and incomplete multipart uploads.

## 2. RAM Policies

### Prefix-Isolated User

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "oss:GetBucketLocation",
        "oss:ListObjects",
        "oss:ListObjectsV2"
      ],
      "Resource": "acs:oss:*:*:<bucket-name>",
      "Condition": {
        "StringLike": {
          "oss:Prefix": [
            "users/<user>/",
            "users/<user>/*"
          ]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "oss:GetObject",
        "oss:PutObject",
        "oss:DeleteObject",
        "oss:AbortMultipartUpload",
        "oss:ListParts",
        "oss:RestoreObject"
      ],
      "Resource": "acs:oss:*:*:<bucket-name>/users/<user>/*"
    }
  ]
}
```

### Full-Bucket Object Access

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "oss:GetBucketLocation",
        "oss:GetBucketInfo",
        "oss:GetBucketStat",
        "oss:ListObjects",
        "oss:ListObjectsV2",
        "oss:ListObjectVersions"
      ],
      "Resource": [
        "acs:oss:*:*:<bucket-name>"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "oss:GetObject",
        "oss:PutObject",
        "oss:DeleteObject",
        "oss:DeleteObjectVersion",
        "oss:AbortMultipartUpload",
        "oss:ListParts",
        "oss:RestoreObject"
      ],
      "Resource": [
        "acs:oss:*:*:<bucket-name>/*"
      ]
    }
  ]
}
```

This is full-bucket object access, not unrestricted bucket administration. It does not grant permission to change ACLs, encryption, lifecycle, CORS, or bucket deletion.

## 3. Batch RAM Provisioning

Install and configure Alibaba Cloud CLI with an identity allowed to manage RAM users, policies, policy attachments, and AccessKeys.

Create prefix-isolated users:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<user-a>","<user-b>" `
    -CreateAccessKey
```

Create an administrator or NAS identity:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<admin-user>" `
    -PolicyMode FullBucket `
    -CreateAccessKey
```

With `-CreateAccessKey`, the script writes `oss-ram-users-accesskeys.csv` in the current directory. It contains plaintext Secrets. Move it immediately to an approved password manager, deliver credentials securely, remove the CSV after deployment, and never commit it.

## 4. GUI Deployment

Distribute the complete project directory. Start with:

```text
scripts\start-oss-mount-gui.vbs
```

This launcher hides the PowerShell startup window. `start-oss-mount-gui.cmd` remains as a compatibility shim.

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\oss-mount-gui.ps1
```

The GUI has Connection, Settings, and Activity pages and supports immediate Chinese/English switching. Bucket is empty by default. Remote path `/` means the bucket root. The default VFS cache limit is `5G`; directory cache is `1m`.

Install rclone and WinFsp, enter the OSS and RAM settings, select **Test only**, and then select **Save and connect**. The GUI uses Windows PowerShell 5.1 and WinForms and requires no additional language runtime.

## 5. CLI Deployment

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-oss-rclone-mount.ps1 `
    -Bucket "<bucket-name>" `
    -Region "ap-southeast-1" `
    -OssPath "users/<user>" `
    -DriveLetter "Z"
```

Use `-SkipInstall` when rclone and WinFsp are already present. Use `-OssPath "/"` only with an identity authorized for the bucket root. The script prompts for the AccessKey and does not require the Secret as a command-line argument.

GUI and CLI both use the `crosscloud-main` remote and the same shared mount argument builder.

## 6. Sign-in Mount and Recovery

The application creates two hidden scheduled tasks for the current Windows user:

```text
CrossCloud Drive - Sign-in mount
CrossCloud Drive - Recovery
```

The recovery task checks every 5 minutes and starts a mount only when both the drive and the exact managed process are absent. A manual stop pauses recovery for the current sign-in session. The hidden launcher is stored under `%LOCALAPPDATA%\CrossCloudDrive\runtime`.

If a command window appears every 5 minutes, inspect Task Scheduler for a legacy `Mount OSS workspace drive ...` task and remove the local connection through the current GUI.

## 7. Stop and Local Removal

**Stop** terminates only the exact managed mount and preserves configuration and tasks.

**Remove local connection** removes the V1/V2 tasks, exact managed process, drive records, managed rclone remote, state, runtime files, and default cache. A second confirmation can uninstall rclone and WinFsp. Custom cache directories outside the application-owned directory are preserved by default.

Neither action deletes OSS cloud objects. Cloud deletion, historical-version cleanup, and lifecycle changes remain administrator-controlled OSS operations.

## 8. Cache, Object Semantics, and Time

The default cache is `%LOCALAPPDATA%\CrossCloudDrive\cache`. `--vfs-cache-max-size` is a cleanup target rather than a hard quota. Uploading or open files can temporarily exceed it. A full system drive can cause writes, uploads, or applications to fail.

OSS folders are object-name prefixes, not NTFS directories. A deleted item can remain visible because of versioning, a delete marker, a directory marker, directory caching, or a failed request. Manage historical versions through OSS version management and lifecycle policies.

OSS service timestamps use UTC, while File Explorer normally displays local time. Different display time zones do not imply changed content.

## 9. Cost Controls

Typical charges include object and historical-version storage, request counts, outbound or cross-region traffic, and incomplete multipart uploads. Pricing varies by region, storage class, network path, and current Alibaba Cloud International rates.

Configure budget alerts, verify the endpoint and traffic path, and apply lifecycle rules for historical versions, delete markers, and incomplete multipart uploads.

## 10. Troubleshooting and Security

For `AccessDenied`, verify the RAM identity, policy attachment, exact bucket, endpoint region, and prefix spelling. For a missing drive, inspect the Activity page and `%LOCALAPPDATA%\CrossCloudDrive\logs\mount.log`, then verify WinFsp, rclone, drive availability, and free disk space.

The application state file does not store the AccessKey Secret. rclone manages credentials for the current Windows user. Rotate and re-enter credentials after any suspected disclosure.

Before a public release, scan for credentials and private data:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```

The script runs PowerShell syntax checks, all local tests, and a public-release sensitive-data scan. Field names, policy action names, and scan rules are not credentials. Review any match in context before release.

Do not publish credential CSV files, `rclone.conf`, logs, caches, real bucket names, internal paths, screenshots, or employee information.
