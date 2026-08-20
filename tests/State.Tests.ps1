$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.State.ps1"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CrossCloudDrive-StateTests-" + [guid]::NewGuid().ToString("N"))
try {
    $paths = Get-CrossCloudPaths -LocalAppData $tempRoot
    Assert-Equal (Join-Path $tempRoot "CrossCloudDrive") $paths.Root "V2 root uses the product-owned directory"
    Assert-Equal "connection.json" ([IO.Path]::GetFileName($paths.StateFile)) "State file name is stable"
    Assert-Equal "mount-paused" ([IO.Path]::GetFileName($paths.PauseFile)) "Manual stop marker has a stable path"

    Assert-Equal "" (Normalize-CloudPath "/") "Slash means the container root"
    Assert-Equal "users/alice" (Normalize-CloudPath " /users/alice/ ") "Cloud path strips outer slashes"
    Assert-Throws { Normalize-CloudPath "users/../admin" } "Parent traversal is rejected"
    Assert-Equal "Z" (Normalize-DriveLetter " z: ") "Drive letters are normalized"
    Assert-Throws { Normalize-DriveLetter "1" } "Non-letter drives are rejected"
    Assert-Equal "5G" (Normalize-CacheSize "5 GB") "Cache display values become rclone values"
    Assert-Equal "1536M" (Normalize-CacheSize "1536M") "Custom cache values are supported"
    Assert-Throws { Normalize-CacheSize "512M" } "Cache values below 1 GB are rejected"

    $state = New-CrossCloudConnectionState -Paths $paths
    Assert-Equal "AlibabaOss" $state.Provider "Alibaba OSS is the first provider"
    Assert-Equal "" $state.Bucket "Bucket defaults to empty"
    Assert-Equal "" $state.RemotePath "Cloud root is stored as an empty prefix"
    Assert-Equal "5G" $state.CacheMaxSize "Cache defaults to 5 GB"
    Assert-Equal $true $state.AutoMount "Login mount defaults on"
    Assert-Equal $true $state.AutoRecover "Watchdog defaults on"

    Assert-Equal $false (Test-CrossCloudMountPaused -Paths $paths) "Mount is not paused by default"
    Set-CrossCloudMountPaused -Paths $paths
    Assert-Equal $true (Test-CrossCloudMountPaused -Paths $paths) "Manual stop creates the pause marker"
    Clear-CrossCloudMountPaused -Paths $paths
    Assert-Equal $false (Test-CrossCloudMountPaused -Paths $paths) "Reconnect clears the pause marker"

    $state.Bucket = "example-workspace"
    $state.AccessKeyId = "LTAIEXAMPLE"
    $state | Add-Member -NotePropertyName AccessKeySecret -NotePropertyValue "must-not-be-written"
    Save-CrossCloudConnectionState -State $state -Paths $paths | Out-Null
    $rawState = Get-Content -LiteralPath $paths.StateFile -Raw
    Assert-True (-not $rawState.Contains("must-not-be-written")) "State JSON does not contain the secret"
    Assert-True (-not $rawState.Contains("AccessKeySecret")) "State JSON does not contain a secret field"
    $loaded = Get-CrossCloudConnectionState -Paths $paths
    Assert-Equal "example-workspace" $loaded.Bucket "Saved state can be loaded"

    $ownedChild = Join-Path $paths.Root "cache\default"
    $outside = Join-Path $tempRoot "unrelated"
    Assert-True (Test-CrossCloudOwnedPath -Path $ownedChild -OwnedRoots @($paths.Root)) "Owned child path is accepted"
    Assert-True (-not (Test-CrossCloudOwnedPath -Path $paths.Root -OwnedRoots @($paths.Root))) "Owned root itself is rejected"
    Assert-True (-not (Test-CrossCloudOwnedPath -Path $outside -OwnedRoots @($paths.Root))) "Outside path is rejected"

    New-Item -ItemType Directory -Force -Path $paths.LegacyRoot | Out-Null
    $legacy = [pscustomobject]@{
        Bucket = "legacy-bucket"
        Endpoint = "oss-ap-southeast-1.aliyuncs.com"
        RemoteName = "aliyun-oss"
        OssPath = "users/alice/"
        DriveLetter = "Y"
        CacheDir = (Join-Path $tempRoot "legacy-cache")
        TaskName = "Mount OSS workspace drive Y"
    }
    $legacy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $paths.LegacyRoot "mount-Y.json") -Encoding UTF8
    $legacyState = Get-LegacyOssConnectionState -Paths $paths
    Assert-Equal "legacy-bucket" $legacyState.Bucket "V1 state is readable"
    Assert-Equal "users/alice" $legacyState.RemotePath "V1 trailing slash is normalized"
    Assert-Equal "Y" $legacyState.DriveLetter "V1 drive is preserved"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Complete-TestFile
