$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$repoRoot = $repoRoot.ProviderPath

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RepositoryTextFiles {
    $excludedDirectories = @(".git", ".idea", ".vscode", "cache", "oss-cache", "credentials", "secrets", "dist")
    $excludedExtensions = @(".png", ".jpg", ".jpeg", ".gif", ".zip", ".7z", ".exe", ".dll", ".msi", ".log", ".tmp")

    Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($repoRoot.Length).TrimStart("\", "/")
        $parts = $relative -split '[\\/]'
        $directoryAllowed = -not ($parts | Where-Object { $excludedDirectories -contains $_ })
        $extensionAllowed = -not ($excludedExtensions -contains $_.Extension.ToLowerInvariant())
        $directoryAllowed -and $extensionAllowed
    }
}

Write-Step "Checking PowerShell syntax"
$parseFailures = @()
$psFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "scripts") -Recurse -Filter "*.ps1" -File)
foreach ($file in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) {
        $parseFailures += "{0}: {1}" -f $file.FullName, $parseError.Message
    }
}

if ($parseFailures.Count -gt 0) {
    $parseFailures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "PowerShell syntax check failed."
}
Write-Host "PASS: $($psFiles.Count) PowerShell files are AST-clean" -ForegroundColor Green

Write-Step "Running local tests"
$testFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "tests") -Filter "*.Tests.ps1" -File | Sort-Object Name)
foreach ($testFile in $testFiles) {
    Write-Host $testFile.Name
    & $testFile.FullName
}

Write-Step "Scanning public release contents"
$rules = @(
    @{ Name = "Alibaba Cloud AccessKey ID"; Pattern = "LT" + "AI[A-Za-z0-9]{12,}" },
    @{ Name = "AWS AccessKey ID"; Pattern = "AK" + "IA[A-Z0-9]{16}" },
    @{ Name = "Local Windows user path"; Pattern = "C:\\Users\\" + "112" + "07" },
    @{ Name = "AI assistant trace"; Pattern = "(?i)(\.co" + "dex|\bCo" + "dex\b|\bOpen" + "AI\b|\bChat" + "GPT\b)" },
    @{ Name = "Legacy private bucket marker"; Pattern = "(?i)our-" + "workspace" },
    @{ Name = "Legacy private user marker"; Pattern = "(?i)users/" + "lari" }
)

$findings = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-RepositoryTextFiles) {
    $relative = $file.FullName.Substring($repoRoot.Length).TrimStart("\", "/")
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    foreach ($rule in $rules) {
        if ($content -match $rule.Pattern) {
            $lineNumber = 0
            foreach ($line in ($content -split "`r?`n")) {
                $lineNumber++
                if ($line -match $rule.Pattern) {
                    $findings.Add(("{0}:{1}: {2}" -f $relative, $lineNumber, $rule.Name))
                    break
                }
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "Release scan found content that should not be published."
}

Write-Host "PASS: release scan found no blocked markers" -ForegroundColor Green
Write-Host "Release readiness checks passed." -ForegroundColor Green
