[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-LauncherRootCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($PSScriptRoot) {
        $candidates.Add($PSScriptRoot)
    }

    try {
        $mainModule = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($mainModule) {
            $candidates.Add((Split-Path -Parent $mainModule))
        }
    }
    catch { }

    $candidates.Add((Get-Location).ProviderPath)

    return $candidates | Where-Object { $_ } | Select-Object -Unique
}

function Resolve-CrossCloudGuiScript {
    foreach ($root in Get-LauncherRootCandidates) {
        $scriptPath = Join-Path $root "scripts\oss-mount-gui.ps1"
        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $scriptPath).ProviderPath
        }
    }

    throw "Cannot find scripts\oss-mount-gui.ps1 next to the launcher. Keep CrossCloudDrive.exe together with the release folder contents."
}

$guiScript = Resolve-CrossCloudGuiScript
$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-STA",
    "-File", $guiScript
)

$process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
if ($process) {
    $process.WaitForExit()
    exit $process.ExitCode
}

exit 1
