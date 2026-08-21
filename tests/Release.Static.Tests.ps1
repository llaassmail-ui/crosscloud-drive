$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"

$build = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\Build-Release.ps1" -Raw
$launcher = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\CrossCloudDrive.Launcher.ps1" -Raw
$gitignore = Get-Content -LiteralPath "$PSScriptRoot\..\.gitignore" -Raw
$readiness = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\Test-ReleaseReadiness.ps1" -Raw

Assert-True ($build.Contains('Test-ReleaseReadiness.ps1')) "Release build runs readiness checks by default"
Assert-True ($build.Contains('Invoke-ps2exe') -or $build.Contains('Invoke-PS2EXE')) "Release build locates ps2exe"
Assert-True ($build.Contains('CrossCloudDrive.exe')) "Release build creates the expected exe name"
Assert-True ($build.Contains('Compress-Archive')) "Release build creates a zip archive"
Assert-True ($build.Contains('Get-FileHash')) "Release build writes SHA256 hashes"
Assert-True ($build.Contains('SHA256SUMS.txt')) "Release build uses the standard checksum file name"
Assert-True ($build.Contains('Assert-PathInsideDirectory')) "Release build validates generated paths before deletion"
Assert-True ($build -notmatch '(?i)Remove-Item\s+-LiteralPath\s+\$repoRoot\s+-Recurse') "Release build never removes the repository root"
Assert-True ($build.Contains('scripts')) "Release build includes script modules in the release folder"
Assert-True ($build.Contains('docs')) "Release build includes documentation in the release folder"
Assert-True ($build.Contains('CONTRIBUTING.md')) "Release build includes contribution guidance"
Assert-True ($build.Contains('tests') -eq $false) "End-user release build does not include tests"
Assert-True ($build.Contains('Test-ReleaseReadiness.ps1')) "Release build removes developer-only readiness script from the end-user package"

Assert-True ($launcher.Contains('scripts\oss-mount-gui.ps1')) "Launcher locates the GUI script next to the release folder"
Assert-True ($launcher.Contains('-WindowStyle Hidden')) "Launcher hides the PowerShell host window"
Assert-True ($launcher.Contains('-STA')) "Launcher starts the GUI in STA mode"
Assert-True ($launcher -notmatch '(?i)rclone\s+(delete|purge)') "Launcher does not contain cloud object deletion commands"
Assert-True ($launcher.Contains('Keep CrossCloudDrive.exe together with the release folder contents')) "Launcher explains missing release contents"

Assert-True ($gitignore.Contains('dist/')) "Generated dist directory is gitignored"
Assert-True ($gitignore.Contains('*.exe')) "Generated exe files are gitignored"
Assert-True ($gitignore.Contains('SHA256SUMS.txt')) "Generated checksum file is gitignored"
Assert-True ($readiness.Contains('"dist"')) "Release readiness scan ignores generated dist output"

Complete-TestFile
