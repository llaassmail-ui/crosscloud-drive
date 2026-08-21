[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$')]
    [string]$Version,

    [switch]$SkipReadiness
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$repoRoot = $repoRoot.ProviderPath
$distRoot = Join-Path $repoRoot "dist"
$releaseName = "CrossCloudDrive-$Version"
$releasePath = Join-Path $distRoot $releaseName
$zipPath = Join-Path $distRoot "$releaseName.zip"
$checksumPath = Join-Path $distRoot "SHA256SUMS.txt"
$launcherSource = Join-Path $repoRoot "scripts\CrossCloudDrive.Launcher.ps1"
$exePath = Join-Path $releasePath "CrossCloudDrive.exe"

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-PathInsideDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside generated release directory: $resolvedPath"
    }
}

function Copy-ReleaseItem {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $source = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release source item: $RelativePath"
    }

    $destination = Join-Path $DestinationRoot $RelativePath
    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

function Get-PS2ExeCommand {
    $command = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        throw "ps2exe is not installed. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Install-Module ps2exe -Scope CurrentUser -Force`""
    }
    return $command
}

function New-LauncherExe {
    param([Parameter(Mandatory = $true)][string]$OutputPath)

    $ps2exe = Get-PS2ExeCommand
    $parameters = @{
        inputFile = $launcherSource
        outputFile = $OutputPath
        noConsole = $true
        title = "CrossCloud Drive"
        product = "CrossCloud Drive"
        description = "Multi-cloud object storage drive mounter for Windows"
        company = "CrossCloud Drive"
        copyright = "MIT License"
        version = $Version
    }

    & $ps2exe @parameters
}

function Write-Checksums {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $lines = foreach ($path in $Paths) {
        $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
        "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $path)
    }
    $lines | Set-Content -LiteralPath $checksumPath -Encoding ASCII
}

if (-not $SkipReadiness) {
    Write-Step "Running release readiness checks"
    & (Join-Path $repoRoot "scripts\Test-ReleaseReadiness.ps1")
}

Write-Step "Preparing release directory"
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
Assert-PathInsideDirectory -Path $releasePath -Parent $distRoot
Assert-PathInsideDirectory -Path $zipPath -Parent $distRoot
if (Test-Path -LiteralPath $releasePath) {
    Remove-Item -LiteralPath $releasePath -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
New-Item -ItemType Directory -Force -Path $releasePath | Out-Null

Write-Step "Copying release files"
foreach ($item in @("README.md", "README.en.md", "LICENSE", "SECURITY.md", "CONTRIBUTING.md", "docs", "scripts")) {
    Copy-ReleaseItem -RelativePath $item -DestinationRoot $releasePath
}

foreach ($excluded in @("Build-Release.ps1", "Test-ReleaseReadiness.ps1")) {
    $excludedPath = Join-Path $releasePath "scripts\$excluded"
    if (Test-Path -LiteralPath $excludedPath) {
        Remove-Item -LiteralPath $excludedPath -Force
    }
}

Write-Step "Building CrossCloudDrive.exe"
New-LauncherExe -OutputPath $exePath

Write-Step "Creating release ZIP"
Compress-Archive -LiteralPath $releasePath -DestinationPath $zipPath -Force

Write-Step "Writing SHA256 checksums"
Write-Checksums -Paths @($exePath, $zipPath)

Write-Host "Release built:" -ForegroundColor Green
Write-Host "  $releasePath"
Write-Host "  $zipPath"
Write-Host "  $checksumPath"
