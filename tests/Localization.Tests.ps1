$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Localization.ps1"

$localeRoot = Join-Path $PSScriptRoot "..\scripts\locales"
$localizationSource = Get-Content -LiteralPath "$PSScriptRoot\..\scripts\OssMount.Localization.ps1" -Raw
$zh = Import-CrossCloudLocale -Language "zh-CN" -LocaleRoot $localeRoot
$en = Import-CrossCloudLocale -Language "en-US" -LocaleRoot $localeRoot

$zhKeys = @($zh.Keys | Sort-Object)
$enKeys = @($en.Keys | Sort-Object)
Assert-Equal ($zhKeys -join "|") ($enKeys -join "|") "Chinese and English locale keys match"
Assert-True ($zhKeys.Count -ge 50) "Locale dictionaries cover the application surface"
Assert-Equal "连接" (Get-CrossCloudText -Dictionary $zh -Key "NavConnection") "Chinese text is loaded"
Assert-Equal "Connection" (Get-CrossCloudText -Dictionary $en -Key "NavConnection") "English text is loaded"
Assert-Equal "中文" (Get-CrossCloudText -Dictionary $zh -Key "LanguageName") "Language names are localized"
Assert-Throws { Get-CrossCloudText -Dictionary $en -Key "MissingKey" } "Missing translation keys fail clearly"
Assert-True ($localizationSource.Contains("[System.Management.Automation.Language.Parser]::ParseFile")) "Localization supports Windows PowerShell without Import-PowerShellDataFile"
Assert-True ($localizationSource.Contains('$hashtableAst.SafeGetValue()')) "Localization reads only the locale hashtable AST"

Assert-Equal "zh-CN" (Resolve-CrossCloudLanguage -SavedLanguage "zh-CN" -WindowsLanguage "en-US") "Saved language wins"
Assert-Equal "en-US" (Resolve-CrossCloudLanguage -SavedLanguage "" -WindowsLanguage "en-GB") "Non-Chinese Windows uses English"
Assert-Equal "zh-CN" (Resolve-CrossCloudLanguage -SavedLanguage "" -WindowsLanguage "zh-TW") "Chinese Windows uses Chinese"
Assert-Equal "zh-CN" (Resolve-CrossCloudLanguage -SavedLanguage "invalid" -WindowsLanguage "") "Unknown language falls back to Chinese"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CrossCloudDrive-LocaleTests-" + [guid]::NewGuid().ToString("N"))
try {
    $settingsFile = Join-Path $tempRoot "settings.json"
    Save-CrossCloudLanguage -Language "en-US" -SettingsFile $settingsFile
    Assert-Equal "en-US" (Get-SavedCrossCloudLanguage -SettingsFile $settingsFile) "Language preference persists"
    Assert-Throws { Save-CrossCloudLanguage -Language "fr-FR" -SettingsFile $settingsFile } "Unsupported languages are rejected"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Complete-TestFile
