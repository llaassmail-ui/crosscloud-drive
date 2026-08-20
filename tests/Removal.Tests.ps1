$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.State.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Core.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Tasks.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Removal.ps1"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CrossCloudDrive-RemovalTests-" + [guid]::NewGuid().ToString("N"))
try {
    $paths = Get-CrossCloudPaths -LocalAppData $tempRoot
    $state = New-CrossCloudConnectionState -Paths $paths
    $state.Bucket = "example-bucket"
    $state.RemotePath = "users/alice"

    $target = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 11; CommandLine = 'rclone mount crosscloud-main:example-bucket/users/alice Z: --network-mode' }
    $unrelated = [pscustomobject]@{ Name = "rclone.exe"; ProcessId = 12; CommandLine = 'rclone mount personal:photos Z: --network-mode' }
    $matches = @(Get-CrossCloudManagedMountProcesses -States @($state) -Processes @($target, $unrelated))
    Assert-Equal 1 $matches.Count "Only the managed rclone process is selected"
    Assert-Equal 11 $matches[0].ProcessId "Managed process ID is retained"

    $plan = Get-CrossCloudRemovalPlan -State $state -Paths $paths
    Assert-Equal "crosscloud-main" $plan.RemoteNames[0] "V2 remote is included in removal plan"
    Assert-Equal $true $plan.RemoveCache "Default cache is removed"
    Assert-Equal $true $plan.RemoveRuntime "Runtime files are removed"
    Assert-Equal $true $plan.RemovePauseMarker "Manual stop marker is removed"
    $state.CacheDir = Join-Path $tempRoot "custom-cache"
    $customPlan = Get-CrossCloudRemovalPlan -State $state -Paths $paths
    Assert-Equal $false $customPlan.RemoveCache "Custom cache is retained by default"

    New-Item -ItemType Directory -Force -Path $paths.CacheRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $paths.CacheRoot "cached.bin") -Value "local-only"
    Assert-Equal $true (Remove-CrossCloudOwnedDirectory -Path $paths.CacheRoot -OwnedRoots @($paths.Root)) "Owned child directory can be removed"
    Assert-True (-not (Test-Path -LiteralPath $paths.CacheRoot)) "Owned directory is deleted"
    Assert-Equal $false (Remove-CrossCloudOwnedDirectory -Path $tempRoot -OwnedRoots @($paths.Root)) "Outside directory is never deleted"

    New-Item -ItemType Directory -Force -Path $paths.LegacyRoot | Out-Null
    [pscustomobject]@{
        Bucket = "legacy-bucket"; Endpoint = "oss-eu-west-1.aliyuncs.com"; RemoteName = "aliyun-oss"
        OssPath = "users/bob/"; DriveLetter = "Y"; CacheDir = (Join-Path $tempRoot "legacy-cache")
        TaskName = "Mount OSS workspace drive Y"
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $paths.LegacyRoot "mount-Y.json") -Encoding UTF8
    $migrated = Import-CrossCloudLegacyConnection -Paths $paths
    Assert-Equal "legacy-bucket" $migrated.Bucket "Legacy connection is migrated"
    Assert-Equal "eu-west-1" $migrated.Region "Legacy endpoint maps to a region"
    Assert-True (Test-Path -LiteralPath $paths.StateFile) "Migrated V2 state is saved"

    $expectedLegacyRoot = $paths.LegacyRoot
    $outsideLegacyRoot = Join-Path $tempRoot "unrelated-legacy"
    New-Item -ItemType Directory -Force -Path $outsideLegacyRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $outsideLegacyRoot "keep.txt") -Value "keep"
    $paths.LegacyRoot = $outsideLegacyRoot
    Assert-Equal $false (Remove-CrossCloudLegacyDirectory -Paths $paths) "Unexpected legacy path is rejected"
    Assert-True (Test-Path -LiteralPath $outsideLegacyRoot) "Rejected legacy path is retained"
    $paths.LegacyRoot = $expectedLegacyRoot
    Assert-Equal $true (Remove-CrossCloudLegacyDirectory -Paths $paths) "Expected legacy directory can be removed"
    Assert-True (-not (Test-Path -LiteralPath $expectedLegacyRoot)) "Expected legacy directory is deleted"

    Set-CrossCloudMountPaused -Paths $paths
    Assert-True (Test-Path -LiteralPath $paths.PauseFile) "Pause marker exists before local cleanup"

    $source = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\OssMount.Removal.ps1" -Raw
    Assert-True ($source -notmatch '(?i)\brclone\s+(delete|purge)\b') "Removal source has no cloud deletion command"
    Assert-True ($source -notmatch '(?i)taskkill\s+/IM\s+rclone') "Removal source has no global rclone termination"
    Assert-True ($source.Contains('Paths.PauseFile')) "Removal source cleans the manual stop marker"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Complete-TestFile
