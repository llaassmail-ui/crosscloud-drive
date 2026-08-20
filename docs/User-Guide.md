# CrossCloud Drive V2 User Guide

This guide is for employees using a Windows Cloud PC or Windows workstation. An administrator prepares the OSS bucket, RAM identity, and AccessKey. CrossCloud Drive then mounts the authorized OSS location as a Windows drive.

## 1. What You Need

Ask your administrator for the OSS region, bucket name, OSS path such as `/users/<user>`, and a RAM AccessKey ID and Secret. `/` means the entire bucket and is normally reserved for administrators.

Never use an Alibaba Cloud root-account AccessKey. Do not place a Secret in screenshots, chat messages, command-line arguments, or public documents. A disclosed Secret must be disabled and replaced.

## 2. Start the Application

The complete project directory is required because the GUI loads modules, providers, and language files from `scripts`.

Double-click:

```text
scripts\start-oss-mount-gui.vbs
```

`start-oss-mount-gui.vbs` hides the PowerShell startup window. `start-oss-mount-gui.cmd` is kept as a compatibility shim and is mainly useful for troubleshooting startup issues.

Or start it from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\oss-mount-gui.ps1
```

The GUI uses Windows PowerShell 5.1 and WinForms. It does not require Python, Node.js, Go, or another language runtime. Use the `English/中文` button at the lower left to switch languages immediately.

## 3. First Connection

### Install Components

On the Connection page, select **Install components**. The application installs rclone, which accesses and mounts OSS, and WinFsp, which enables the Windows drive. Installation can trigger a UAC prompt. Reopen the application if the components are not detected immediately.

### Enter Settings

Open the Settings page:

| Field | Meaning |
|---|---|
| Region | The region containing the bucket |
| Endpoint | Filled for a known region; enter a host name for a custom region |
| Bucket | Required and empty by default; do not add a leading slash |
| Remote path | `/` by default; `/users/<user>` mounts only that prefix |
| AccessKey ID | RAM AccessKey supplied by the administrator |
| AccessKey Secret | Required for first configuration; hidden by default |
| Drive letter | Automatic selection is recommended, or choose an unused letter |
| Cache limit | `5G` by default; `10G`, `20G`, or a custom value of at least `1G` |
| Mount at sign-in | Enabled by default |
| Automatic recovery | Enabled by default; checks every 5 minutes |

Use `5G` for office documents and smaller system drives, `10G` for general files, and `20G` for frequent large files when sufficient disk space is available. The cache limit is a cleanup target, not a strict quota. Uploading or open files can temporarily exceed it.

### Test and Connect

1. Select **Test only**.
2. After the test succeeds, select **Save and connect**.
3. Return to the Connection page and wait for the drive to appear.
4. Select **Open drive**, or open the drive in File Explorer.

Action buttons are temporarily disabled while an operation is running to prevent duplicate mounts.

## 4. Daily Use

The Connection page shows the remote location, endpoint, last check, and component status. The Activity page keeps up to 500 recent local entries and supports filters for all activity, errors, mounts, and uploads.

**Stop** disconnects the mount for the current sign-in session but keeps the connection and scheduled tasks. Automatic recovery will not restart a manually stopped connection during the same session. The connection can return at the next Windows sign-in.

**Reconnect** tests the saved connection, clears the current-session pause, and mounts it again.

**Remove local connection** removes the local tasks, managed mount process, drive record, managed rclone remote, state, runtime files, and default cache. A second confirmation can also uninstall rclone and WinFsp. This action never deletes OSS cloud objects. A custom cache outside the tool-owned directory is preserved by default.

## 5. Common Questions

### Why Is the Drive a Network Location?

CrossCloud Drive uses rclone network mode. This is expected and does not prevent normal browsing, copying, saving, or deleting.

### Why Does OSS Still Show a Deleted File?

Wait for directory-cache refresh and confirm that the deletion occurred inside the mounted drive. Versioning can retain an older version or delete marker, the OSS console may show historical versions, an empty folder can be a zero-byte directory marker, or a cached operation may be retrying because of disk, permission, network, or endpoint errors.

Historical versions should be managed by an administrator through OSS version management and lifecycle rules.

### Why Is There a Check Every Five Minutes?

Automatic recovery checks the drive and the exact managed rclone process. It does not start a duplicate when the connection is healthy. The task runs through a hidden `wscript.exe` launcher, so no command window should appear.

### What Happens When the Disk Is Full?

Full VFS caching needs local disk space. A full system drive can cause saves or uploads to fail, repeated retries, or application stalls. Free disk space and reconnect, then inspect the Activity page or `mount.log`.

### Can OSS Time Zone Be Changed?

OSS service timestamps use UTC. File Explorer normally displays local time. CrossCloud Drive preserves object modification times; different displays do not mean that file contents changed.

### What Happens After Sleep or Sign-out?

- Disconnecting the remote session normally leaves the Cloud PC and rclone running.
- After sleep or a short network outage, rclone can recover and the recovery task checks periodically.
- After sign-out, restart, or power-on, the sign-in task mounts again.
- A Cloud PC reset or restore can remove local settings and require reconfiguration.

### Why Is the Secret Empty After Reopening?

The application state file does not store the Secret. rclone stores credentials for the current Windows user. Enter a new ID and Secret when rotating the AccessKey.

### What Does OSS-Managed Encryption Do?

OSS-managed encryption protects objects at rest. OSS decrypts authorized reads automatically and transfers data over HTTPS, so normal downloads and mounted-file reads return the original file content.

## 6. Costs

rclone and WinFsp do not charge OSS usage fees. Typical OSS charges include current and historical version storage, PUT/GET/LIST/DELETE and multipart requests, billable outbound or cross-region traffic, and incomplete multipart uploads.

Prices vary by region, storage class, network path, and current Alibaba Cloud International pricing. Administrators should configure budgets, lifecycle rules, and cost alerts.

## 7. Local Data

V2 stores state, language settings, hidden runtime files, cache, and logs under:

```text
%LOCALAPPDATA%\CrossCloudDrive
```

The application state file does not contain the AccessKey Secret.
