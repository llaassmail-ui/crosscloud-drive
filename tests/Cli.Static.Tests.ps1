$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"

$installer = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\install-oss-rclone-mount.ps1" -Raw
$ram = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\create-oss-ram-users.ps1" -Raw

foreach ($module in @("OssMount.State.ps1", "OssMount.Core.ps1", "OssMount.Tasks.ps1", "AlibabaOss.Provider.ps1")) {
    Assert-True ($installer.Contains($module)) "CLI installer loads $module"
}
Assert-True ($installer.Contains("Get-CrossCloudMountArguments")) "CLI installer uses shared mount arguments"
Assert-True ($installer.Contains("Set-CrossCloudScheduledTasks")) "CLI installer uses shared scheduled tasks"
Assert-True ($installer.Contains("Save-CrossCloudConnectionState")) "CLI installer saves V2 state"
Assert-True ($installer.Contains('CacheMaxSize = "5G"')) "CLI installer defaults to a 5 GB cache"
Assert-True (-not $installer.Contains("--no-modtime")) "CLI installer preserves object modification times"
Assert-True ($installer -notmatch '(?i)taskkill\s+/IM\s+rclone') "CLI installer has no global rclone termination"
Assert-True ($installer.Contains('SensitiveValues @($accessKeyId, $accessKeySecret)')) "CLI installer redacts both AccessKey fields from process output"
Assert-True ($ram.Contains("OssMount.RamPolicy.ps1")) "RAM script uses the shared policy module"
Assert-True ($ram.Contains('PolicyMode = "Prefix"')) "RAM script defaults to prefix isolation"
Assert-True ($ram -notmatch '(?i)(private-bucket-example|users/private-user)') "RAM script contains no private bucket or employee path"

Complete-TestFile
