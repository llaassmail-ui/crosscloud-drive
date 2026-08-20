function Import-CrossCloudLocale {
    param(
        [ValidateSet("zh-CN", "en-US")][string]$Language,
        [string]$LocaleRoot = (Join-Path $PSScriptRoot "locales")
    )

    $localeFile = Join-Path $LocaleRoot "$Language.psd1"
    if (-not (Test-Path -LiteralPath $localeFile)) {
        throw "Locale file was not found: $localeFile"
    }
    if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
        return Import-PowerShellDataFile -LiteralPath $localeFile
    }

    # Windows PowerShell 5.1 does not expose Import-PowerShellDataFile when
    # started with -NoProfile. Read only the hashtable AST used by our locale
    # files instead of invoking the file as a script.
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($localeFile, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Locale file could not be parsed: $localeFile"
    }
    $hashtableAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false) | Select-Object -First 1
    if (-not $hashtableAst) {
        throw "Locale file does not contain a hashtable: $localeFile"
    }
    return $hashtableAst.SafeGetValue()
}

function Get-CrossCloudText {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Dictionary,
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )

    if (-not $Dictionary.ContainsKey($Key)) {
        throw "Missing localization key: $Key"
    }
    $value = [string]$Dictionary[$Key]
    if ($Arguments.Count -gt 0) { return $value -f $Arguments }
    return $value
}

function Resolve-CrossCloudLanguage {
    param(
        [AllowEmptyString()][string]$SavedLanguage,
        [AllowEmptyString()][string]$WindowsLanguage
    )

    if ($SavedLanguage -in @("zh-CN", "en-US")) { return $SavedLanguage }
    if ($WindowsLanguage -match '^(?i)zh(?:-|$)') { return "zh-CN" }
    if ($WindowsLanguage -match '^[A-Za-z]{2,3}(?:-|$)') { return "en-US" }
    return "zh-CN"
}

function Get-SavedCrossCloudLanguage {
    param([Parameter(Mandatory = $true)][string]$SettingsFile)

    if (-not (Test-Path -LiteralPath $SettingsFile)) { return "" }
    try {
        $settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
        if ($settings.Language -in @("zh-CN", "en-US")) { return [string]$settings.Language }
    }
    catch { }
    return ""
}

function Save-CrossCloudLanguage {
    param(
        [ValidateSet("zh-CN", "en-US")][string]$Language,
        [Parameter(Mandatory = $true)][string]$SettingsFile
    )

    $parent = Split-Path -Parent $SettingsFile
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [ordered]@{ Language = $Language } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}
