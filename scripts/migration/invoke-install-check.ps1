param(
    [Parameter(Mandatory)][string]$BootstrapRoot,
    [Parameter(Mandatory)][ValidateSet('fresh','update')][string]$Mode,
    [Parameter(Mandatory)][string]$Setup,
    [Parameter(Mandatory)][string]$Manifest,
    [Parameter(Mandatory)][string]$Previous,
    [Parameter(Mandatory)][string]$Older,
    [string]$Evidence = 'evidence'
)
$ErrorActionPreference = 'Stop'
if ($env:CI -ne 'true' -or -not $env:MIGRATION_FIXTURES) { throw 'Use only on the throwaway CI runner with checked private fixtures.' }
$original = Join-Path $BootstrapRoot 'windows/test-beta-install.ps1'
$source = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $original).Path)
# The fresh repository has no published latest release while its gates run. The updater's
# existing ReleaseBase option reads the exact old manifest from our checked private fixture.
# Change this one test invocation; keep every assertion and every installed product byte.
$needle = '-CheckOnly -NoPause | Out-String'
if ([regex]::Matches($source,[regex]::Escape($needle)).Count -ne 1) { throw 'The exact bootstrap test invocation changed; review fixture routing.' }
$adaptedSource = $source.Replace($needle, '-ReleaseBase $env:MIGRATION_FIXTURES -CheckOnly -NoPause | Out-String')
$adapted = Join-Path $BootstrapRoot 'windows/test-migration-install.ps1'
if (Test-Path -LiteralPath $adapted) { throw 'An adapted test file already exists.' }
New-Item -ItemType Directory -Force $Evidence | Out-Null
Add-Content -LiteralPath (Join-Path $Evidence 'provenance.txt') -Value 'Updater CheckOnly uses its existing -ReleaseBase option to read the verified previous private manifest; all original bootstrap assertions and installed updater bytes remain unchanged.'
try {
    [IO.File]::WriteAllText($adapted,$adaptedSource,[Text.UTF8Encoding]::new($true))
    & $adapted -Mode $Mode -Setup $Setup -Manifest $Manifest -Previous $Previous -Older $Older -Evidence $Evidence
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
} finally { Remove-Item -LiteralPath $adapted -ErrorAction SilentlyContinue }
