# Configure and mount one Alibaba Cloud OSS connection for the current Windows user.
# Administrator permission is only needed when winget installs rclone or WinFsp.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Bucket,

    [string]$Region = "ap-southeast-1",
    [AllowEmptyString()][string]$Endpoint = "",
    [AllowEmptyString()][string]$OssPath = "/",
    [AllowEmptyString()][string]$DriveLetter = "",
    [string]$CacheMaxSize = "5G",
    [AllowEmptyString()][string]$CacheDir = "",
    [bool]$AutoMount = $true,
    [bool]$AutoRecover = $true,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "OssMount.State.ps1")
. (Join-Path $PSScriptRoot "OssMount.Core.ps1")
. (Join-Path $PSScriptRoot "OssMount.Tasks.ps1")
. (Join-Path $PSScriptRoot "providers\AlibabaOss.Provider.ps1")

function Test-CrossCloudAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CrossCloudWinFspInstalled {
    $roots = @(
        (Join-Path $env:ProgramFiles "WinFsp\bin"),
        (Join-Path ${env:ProgramFiles(x86)} "WinFsp\bin")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) { return $true }
    }
    return [bool](Get-Service -Name "WinFsp.Launcher" -ErrorAction SilentlyContinue)
}

function ConvertFrom-CrossCloudSecureString {
    param([Parameter(Mandatory = $true)][securestring]$SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Install-CrossCloudDependencies {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget was not found. Install rclone and WinFsp manually, then rerun with -SkipInstall."
    }

    foreach ($package in @("WinFsp.WinFsp", "Rclone.Rclone")) {
        Write-Host "Installing $package..." -ForegroundColor Cyan
        $result = Invoke-CrossCloudProcess -FilePath $winget.Source -Arguments @(
            "install", "--id", $package, "--exact", "--silent",
            "--accept-package-agreements", "--accept-source-agreements"
        )
        if ($result.ExitCode -ne 0) {
            throw "Failed to install ${package}: $($result.Stderr)"
        }
    }
}

$paths = Get-CrossCloudPaths
$normalizedBucket = Normalize-AlibabaOssBucket -Bucket $Bucket
$normalizedPath = Normalize-AlibabaOssPrefix -Prefix $OssPath
$normalizedCacheSize = Normalize-CacheSize -CacheSize $CacheMaxSize
$resolvedEndpoint = if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    Resolve-AlibabaOssEndpoint -Region $Region
}
else {
    Normalize-AlibabaOssEndpoint -Endpoint $Endpoint
}

if (-not $SkipInstall) {
    if (-not (Test-CrossCloudAdministrator)) {
        Write-Warning "Dependency installation may request administrator permission."
    }
    Install-CrossCloudDependencies
}

$rclone = Get-CrossCloudRcloneExe
if (-not $rclone) {
    throw "rclone was not found. Reopen PowerShell after installation or install rclone manually."
}
if (-not (Test-CrossCloudWinFspInstalled)) {
    throw "WinFsp was not found. Install WinFsp before mounting OSS."
}

$selectedDrive = if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
    Get-CrossCloudAvailableDriveLetter
}
else {
    Normalize-DriveLetter -DriveLetter $DriveLetter
}
$selectedCacheDir = if ([string]::IsNullOrWhiteSpace($CacheDir)) { $paths.CacheRoot } else { $CacheDir }

Write-Host "== CrossCloud Drive setup ==" -ForegroundColor Cyan
Write-Host "Bucket       : $normalizedBucket"
Write-Host "Endpoint     : $resolvedEndpoint"
Write-Host "OSS path     : $(if ($normalizedPath) { '/' + $normalizedPath } else { '/' })"
Write-Host "Drive        : ${selectedDrive}:"
Write-Host "Cache limit  : $normalizedCacheSize"
Write-Host "Auto mount   : $AutoMount"
Write-Host "Auto recover : $AutoRecover"
Write-Host ""

$accessKeyId = (Read-Host "Enter RAM user AccessKey ID").Trim()
$secretSecure = Read-Host "Enter RAM user AccessKey Secret" -AsSecureString
$accessKeySecret = ConvertFrom-CrossCloudSecureString -SecureString $secretSecure
if ([string]::IsNullOrWhiteSpace($accessKeyId) -or [string]::IsNullOrWhiteSpace($accessKeySecret)) {
    throw "AccessKey ID and Secret are required."
}

$remoteName = "crosscloud-main"
$definition = New-AlibabaOssRemoteDefinition -RemoteName $remoteName -Endpoint $resolvedEndpoint `
    -AccessKeyId $accessKeyId -AccessKeySecret $accessKeySecret
$configResult = Invoke-CrossCloudProcess -FilePath $rclone `
    -Arguments (Get-CrossCloudRemoteConfigArguments -Definition $definition) `
    -SensitiveValues @($accessKeyId, $accessKeySecret)
if ($configResult.ExitCode -ne 0) {
    throw "Unable to configure the rclone remote: $($configResult.Stderr)"
}

$state = New-CrossCloudConnectionState -Paths $paths
$state.Region = $Region
$state.Endpoint = $resolvedEndpoint
$state.Bucket = $normalizedBucket
$state.RemotePath = $normalizedPath
$state.RemoteName = $remoteName
$state.DriveLetter = $selectedDrive
$state.CacheDir = $selectedCacheDir
$state.CacheMaxSize = $normalizedCacheSize
$state.DirCacheTime = "1m"
$state.AutoMount = $AutoMount
$state.AutoRecover = $AutoRecover
$state.AccessKeyId = $accessKeyId

Write-Host "Testing OSS access..." -ForegroundColor Cyan
$testResult = Invoke-CrossCloudProcess -FilePath $rclone `
    -Arguments @("lsf", (Get-CrossCloudRemoteTarget -State $state), "--max-depth", "1") `
    -SensitiveValues @($accessKeyId, $accessKeySecret)
if ($testResult.ExitCode -ne 0) {
    throw "OSS access test failed: $($testResult.Stderr)"
}

New-Item -ItemType Directory -Force -Path $state.CacheDir, $paths.RuntimeRoot, $paths.LogRoot | Out-Null
Save-CrossCloudConnectionState -State $state -Paths $paths | Out-Null
$runtime = Install-CrossCloudRuntimeFiles -SourceScriptsRoot $PSScriptRoot -RuntimeRoot $paths.RuntimeRoot
Set-CrossCloudScheduledTasks -LauncherPath $runtime.Launcher -AutoMount $AutoMount -AutoRecover $AutoRecover
Clear-CrossCloudMountPaused -Paths $paths

$mountArguments = Get-CrossCloudMountArguments -State $state -LogFile (Join-Path $paths.LogRoot "mount.log")
$mountArgumentLine = ($mountArguments | ForEach-Object {
    ConvertTo-CrossCloudProcessArgument -Value ([string]$_)
}) -join " "
Start-Process -FilePath $rclone -ArgumentList $mountArgumentLine -WindowStyle Hidden | Out-Null

Write-Host ""
Write-Host "Configuration completed. The drive is mounting at ${selectedDrive}:." -ForegroundColor Green
Write-Host "Mount log: $(Join-Path $paths.LogRoot 'mount.log')"
Write-Host "Use the CrossCloud Drive GUI to stop, reconnect, or fully remove this connection."
