# =============================================================================
# kit-bootstrap / windows / detect-godspeed.ps1
#
# What the wizard asks before it shows its first page, on a PC that may already have Godspeed
# Mission Control: where the mission control is, whether this PC already has the notebook, and
# whether the notebook already here is newer than the one this installer carries. The answers are
# written as name=value lines to -Out, because the wizard's own language cannot read JSON.
#
# Why it is a file of its own. The wizard used to ask join.ps1 only "where is the mission control",
# and the answer was whatever this PC works from. On a PC whose notebook sits beside an older
# mission control, that is the wrong folder to update, and the update then stopped at "An upgrade
# cannot silently change the workspace". And the version check ran only after the installer had
# replaced the program and stopped the notebook, so an older installer left a PC with the older
# program running a newer notebook (found on 17 October 2026). Both questions are now answered here,
# before anything is touched.
#
#   found=<folder>        the mission control to update, empty when there is none
#   notebook=1|0          1 when this PC already has the notebook, kept for that folder
#   worksfrom=<folder>    the mission control this PC works from, when that is another one
#   installed=<commit>    the notebook version on this PC, empty when there is none
#   newer=1|0             1 when the notebook on this PC is newer than -Mine
# =============================================================================
param(
    [Parameter(Mandatory)][string]$Join,
    [Parameter(Mandatory)][string]$Out,
    # When the notebook this installer carries was made (git's committer date, ISO 8601).
    [string]$Mine,
    # The notebook's state folder; by default the one godspeed-folders.ps1 finds (new name first).
    [string]$State
)
$ErrorActionPreference = 'Continue'
. $Join -AsLibrary
if (-not $State) { . (Join-Path $PSScriptRoot 'godspeed-folders.ps1'); $State = Get-GodspeedStateFolder }

$workspace = $null
$installed = ''
$installedAt = $null
$record = Join-Path $State 'installation.json'
if (Test-Path -LiteralPath $record) {
    try {
        $config = Get-Content -LiteralPath $record -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($config.workspace -and (Test-KitGodspeed $config.workspace)) { $workspace = (Resolve-Path -LiteralPath $config.workspace).Path }
        if ($config.kitCommit) { $installed = [string]$config.kitCommit }
        if ($config.kitCommittedAt) { $installedAt = $config.kitCommittedAt }
    } catch { }
}

$pc = Find-KitGodspeed
$found = if ($workspace) { $workspace } elseif ($pc) { $pc } else { '' }
$worksFrom = if ($workspace -and $pc -and -not (Test-KitSamePath $pc $workspace)) { $pc } else { '' }

# Windows PowerShell 5.1 reads the date as text and PowerShell 7 as a date; both convert.
$newer = '0'
if ($Mine -and $installedAt) {
    try { if (([datetimeoffset]$installedAt) -gt ([datetimeoffset]$Mine)) { $newer = '1' } } catch { }
}

# UTF-8, which the wizard reads, so a folder under a user name with an accent arrives intact.
Set-Content -LiteralPath $Out -Encoding UTF8 -Value @(
    "found=$found",
    "notebook=$(if ($workspace) { '1' } else { '0' })",
    "worksfrom=$worksFrom",
    "installed=$installed",
    "newer=$newer"
)
