$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.State.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Core.ps1"

Assert-Equal "Z" (Get-CrossCloudAvailableDriveLetter -UsedDriveLetters @("C", "D")) "Highest free drive is selected"
Assert-Equal "Y" (Get-CrossCloudAvailableDriveLetter -UsedDriveLetters @("C", "Z")) "Used Z falls back to Y"
Assert-Equal "X" (Get-CrossCloudAvailableDriveLetter -UsedDriveLetters @("C", "Z") -PreferredDriveLetter "X") "Free preferred drive wins"
Assert-Throws { Get-CrossCloudAvailableDriveLetter -UsedDriveLetters ([char[]](68..90) | ForEach-Object { [char]$_ }) } "No available drive is reported"

$state = New-CrossCloudConnectionState -Paths ([pscustomobject]@{ CacheRoot = "C:\cache" })
$state.Bucket = "example-bucket"
$state.RemotePath = "users/alice"
$state.DriveLetter = "Z"
$state.CacheDir = "C:\cache path"
$state.CacheMaxSize = "5G"
$state.DirCacheTime = "1m"
$arguments = @(Get-CrossCloudMountArguments -State $state -LogFile "C:\logs\mount.log")
$argumentText = $arguments -join "|"
Assert-Equal "mount" $arguments[0] "Mount command is first"
Assert-True ($argumentText.Contains("crosscloud-main:example-bucket/users/alice")) "Remote target is included"
Assert-True ($argumentText.Contains("--network-mode")) "Network mode is enabled"
Assert-True ($argumentText.Contains("--vfs-cache-mode|full")) "Full VFS cache is enabled"
Assert-True ($argumentText.Contains("--vfs-cache-max-size|5G")) "Cache maximum is included"
Assert-True ($argumentText.Contains("--dir-cache-time|1m")) "Directory cache defaults to one minute"
Assert-True (-not $argumentText.Contains("--no-modtime")) "Modification times are not disabled"

$definition = [pscustomobject]@{
    RemoteName = "crosscloud-main"
    Type = "s3"
    Parameters = [ordered]@{
        provider = "Alibaba"
        access_key_id = "test-id"
        secret_access_key = "test-secret"
    }
}
$configArgs = @(Get-CrossCloudRemoteConfigArguments -Definition $definition)
Assert-Equal "config" $configArgs[0] "Remote configuration uses rclone config"
Assert-Equal "create" $configArgs[1] "Remote configuration creates or updates the remote"
Assert-True (($configArgs -join "|").Contains("secret_access_key|test-secret")) "Transient config command contains the secret"

$targetProcess = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 101; CommandLine = 'rclone mount crosscloud-main:example-bucket/users/alice Z: --network-mode' }
$wrongRemote = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 102; CommandLine = 'rclone mount personal:photos Z: --network-mode' }
$wrongDrive = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 103; CommandLine = 'rclone mount crosscloud-main:example-bucket/users/alice Y: --network-mode' }
$copyProcess = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 104; CommandLine = 'rclone copy crosscloud-main:example-bucket/users/alice Z:' }
$wrongExe = [pscustomobject]@{ Name = "powershell.exe"; ProcessId = 105; CommandLine = 'rclone mount crosscloud-main:example-bucket/users/alice Z:' }
Assert-True (Test-CrossCloudMountProcess -Process $targetProcess -RemoteTarget "crosscloud-main:example-bucket/users/alice" -DriveLetter "Z") "Exact managed mount is matched"
Assert-True (-not (Test-CrossCloudMountProcess -Process $wrongRemote -RemoteTarget "crosscloud-main:example-bucket/users/alice" -DriveLetter "Z")) "Other remotes are ignored"
Assert-True (-not (Test-CrossCloudMountProcess -Process $wrongDrive -RemoteTarget "crosscloud-main:example-bucket/users/alice" -DriveLetter "Z")) "Other drives are ignored"
Assert-True (-not (Test-CrossCloudMountProcess -Process $copyProcess -RemoteTarget "crosscloud-main:example-bucket/users/alice" -DriveLetter "Z")) "Non-mount rclone commands are ignored"
Assert-True (-not (Test-CrossCloudMountProcess -Process $wrongExe -RemoteTarget "crosscloud-main:example-bucket/users/alice" -DriveLetter "Z")) "Non-rclone processes are ignored"

$healthy = Get-CrossCloudCacheAdvice -CacheMaxSize "5G" -FreeBytes 30GB
$large = Get-CrossCloudCacheAdvice -CacheMaxSize "20G" -FreeBytes 30GB
$low = Get-CrossCloudCacheAdvice -CacheMaxSize "5G" -FreeBytes 8GB
Assert-Equal $false $healthy.Warning "Reasonable cache and free space has no warning"
Assert-Equal $true $large.Warning "Cache above 25 percent of free space warns"
Assert-Equal $true $low.Warning "Less than 10 GB free warns"

$processResult = Invoke-CrossCloudProcess -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "fixtures\fake-process.ps1"), "visible-value", "test-secret", "7") `
    -SensitiveValues @("test-secret")
Assert-Equal 7 $processResult.ExitCode "External process exit code is returned"
Assert-Equal "visible-value" $processResult.Stdout "External process stdout is returned"
Assert-Equal "***" $processResult.Stderr "Sensitive stderr is redacted"

Complete-TestFile
