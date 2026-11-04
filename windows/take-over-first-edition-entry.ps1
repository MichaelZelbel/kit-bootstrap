# =============================================================================
# kit-bootstrap / windows / take-over-first-edition-entry.ps1
#
# Windows' Apps list showed two entries named Godspeed Mission Control on a PC that still had the
# first edition (setup 2.18.0): the first edition's own and this setup's (known issue #7). The
# setup brings a first-edition mission control up to date by default, and this is what it runs at
# the end of that, so Apps lists one Godspeed and the one that is left owns the helpers, the daily
# job and GODSPEED_DIR that the two editions shared. Uninstalling it then removes them
# (uninstall-godspeed.ps1 keeps them only while the first edition's entry exists).
#
# WHAT IT DOES. Removes the first edition's uninstall entry, after saving a copy of the key with
# reg.exe in the setup log folder (double-click that .reg file to put the entry back).
#
# WHEN IT DOES NOT. "Keep both" was ticked (-KeepBoth): both entries stay. The install did not
# finish (the setup's result file does not say "ok"): nothing is removed. No first edition on this
# PC: nothing changes. A copy that could not be saved: the entry stays.
#
# WHAT IT NEVER TOUCHES. Not a file, not the mission control folder, the notebook, the state folder
# or the profile, not the helpers, the job or GODSPEED_DIR: only the one registry key, and only
# the key. Never fails: a leftover entry is better than a setup that stops over it.
# =============================================================================
param(
    # The setup's own result file; its "ok" says the whole run finished.
    [Parameter(Mandatory)][string]$SetupResultFile,
    # "Keep both" was ticked: the second mission control lives beside the first, both entries stay.
    [switch]$KeepBoth,
    # Where Windows lists the first edition's setup. A test points this at a key of its own.
    [string]$Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{7B3C1E64-9A55-4E1D-9D6C-2F0B8A4C51D7}_is1',
    # The setup log folder, where the copy of the key's values is kept.
    [string]$LogFolder = (Join-Path $env:LOCALAPPDATA 'Godspeed')
)
$ErrorActionPreference = 'Continue'
function Say([string]$Message) { Write-Output $Message }

try {
    if ($KeepBoth) { Say 'kept the first edition''s entry in the Apps list: you asked to keep both'; exit 0 }
    if (-not (Test-Path -LiteralPath $Key)) { exit 0 }
    $result = ''
    try { $result = (Get-Content -LiteralPath $SetupResultFile -Raw -ErrorAction Stop).Trim() } catch { }
    if ($result -ne 'ok') { Say 'kept the first edition''s entry in the Apps list: this setup did not finish'; exit 0 }

    # The copy first. reg.exe wants HKCU\... without the colon.
    $regPath = $Key -replace '^(HK[A-Z_]+):', '$1'
    New-Item -ItemType Directory -Force -Path $LogFolder -ErrorAction SilentlyContinue | Out-Null
    $copy = Join-Path $LogFolder ('first-edition-apps-entry-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.reg')
    & reg.exe export $regPath $copy /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $copy) -or (Get-Item -LiteralPath $copy).Length -eq 0) {
        Say 'kept the first edition''s entry in the Apps list: a copy of it could not be saved'
        exit 0
    }
    Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Key) { Say 'the first edition''s entry in the Apps list could not be removed' }
    else { Say "took over the first edition's entry in the Apps list; a copy of it is in $copy" }
} catch {
    Say ('the first edition''s entry in the Apps list was left as it is: ' + $_.Exception.Message)
}
exit 0
