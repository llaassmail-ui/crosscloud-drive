# Security Policy

## Supported Versions

Security fixes are expected on the latest public version only unless a maintainer states otherwise.

## Reporting a Vulnerability

Do not publish credentials, internal bucket names, logs, screenshots, or exploit details in a public issue. Report the problem privately to the project maintainer or repository owner first.

If an Alibaba Cloud AccessKey, RAM user credential, `rclone.conf`, or generated credential CSV was exposed, rotate the AccessKey immediately in Alibaba Cloud RAM and remove the leaked material from every location where it was copied.

## Credential Handling

CrossCloud Drive does not store the AccessKey Secret in its own state JSON. rclone manages credentials for the current Windows user. Administrators should issue one RAM user per employee, use prefix-limited policies for normal users, and avoid root-account AccessKeys.

Before publishing a release, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```
