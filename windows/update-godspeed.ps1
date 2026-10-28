# =============================================================================
# kit-bootstrap / windows / update-godspeed.ps1
#
# What the Start menu's "Update my mission control" runs on a PC with the notebook.
#
# Until 18 October 2026 that entry ran setup-godspeed.ps1 without the notebook: it refreshed the
# commands and how the PC is wired to the folder, never the notebook, and it said Hermes was
# missing while the notebook's own Hermes was working. The notebook travels inside
# GodspeedSetup.exe, so updating it means running the newest GodspeedSetup.exe. This looks up the
# newest release; when it carries a newer notebook than this PC has, it downloads it, checks it
# against the release's own checksums and runs it without questions. When this PC is up to date
# already, or GitHub cannot be reached, it brings the folder and the wiring up to date with the
# setup this PC has, as the entry always did.
#
#   powershell -ExecutionPolicy Bypass -File update-godspeed.ps1 [-KbBranch <pin>] [-NoPause]
# =============================================================================
param(
    [string]$KbBranch,
    # Where the newest release is read from: a web address, or a folder holding the same three
    # files (the tests use a folder).
    [string]$ReleaseBase = 'https://github.com/MichaelZelbel/godspeed-mission-control/releases/latest/download',
    # The notebook's state folder; by default the one godspeed-folders.ps1 finds (new name first).
    [string]$State,
    # Look and say, change nothing. For the tests.
    [switch]$CheckOnly,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
if (-not $State) { . (Join-Path $PSScriptRoot 'godspeed-folders.ps1'); $State = Get-GodspeedStateFolder }
# Windows PowerShell 5.1 asks for TLS below 1.2 unless told, and GitHub refuses that.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Close-Update([int]$Code) {
    if (-not $NoPause) { Write-Host ""; Read-Host "  Press Enter to close" | Out-Null }
    exit $Code
}

function Get-ReleaseFile([string]$Name, [string]$To) {
    if (Test-Path -LiteralPath $ReleaseBase -PathType Container) {
        Copy-Item -LiteralPath (Join-Path $ReleaseBase $Name) -Destination $To -Force
    } else {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri ($ReleaseBase.TrimEnd('/') + '/' + $Name) -OutFile $To
    }
}

function Get-Short([string]$Commit) { if ($Commit -and $Commit.Length -ge 7) { $Commit.Substring(0, 7) } else { $Commit } }

Write-Host ""
Write-Host "  Updating Godspeed Mission Control" -ForegroundColor Cyan
Write-Host ""

$config = $null
try { $config = Get-Content -LiteralPath (Join-Path $State 'installation.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }

$work = Join-Path ([IO.Path]::GetTempPath()) ('godspeed-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$latest = $null
try {
    Get-ReleaseFile 'windows-manifest.json' (Join-Path $work 'windows-manifest.json')
    $latest = Get-Content -LiteralPath (Join-Path $work 'windows-manifest.json') -Raw | ConvertFrom-Json
} catch {
    Write-Host "  I could not reach GitHub to look for a newer version ($($_.Exception.Message))."
    Write-Host "  So I bring this PC up to date with the version it has."
}

# Newer means made later, never merely different: a PC that runs a version newer than the newest
# release (a test version) is not taken back.
$newer = $false
if ($latest -and $latest.kitCommit -and $config) {
    if ($config.kitCommittedAt -and $latest.kitCommittedAt) {
        try { $newer = ([datetimeoffset]$latest.kitCommittedAt) -gt ([datetimeoffset]$config.kitCommittedAt) } catch { $newer = $false }
    } elseif ($latest.kitCommit -ne $config.kitCommit) {
        $newer = $true
    }
}

if ($newer) {
    $version = if ($latest.version) { "$($latest.version), " } else { '' }
    Write-Host "  A newer version is out ($version$(Get-Short $latest.kitCommit)). This PC has $(Get-Short $config.kitCommit)."
    if ($CheckOnly) { Write-Host "  CHECK: would download and install it."; Remove-Item -LiteralPath $work -Recurse -Force; exit 0 }
    Write-Host "  Downloading it..."
    try {
        Get-ReleaseFile 'SHA256SUMS' (Join-Path $work 'SHA256SUMS')
        Get-ReleaseFile 'GodspeedSetup.exe' (Join-Path $work 'GodspeedSetup.exe')
    } catch {
        Write-Host "  The download did not finish ($($_.Exception.Message)). Nothing was changed. Try again later." -ForegroundColor Red
        Close-Update 1
    }
    # The release lists the checksum of every file it carries. A file that does not match is not
    # run, whatever else is true about it.
    $sums = @{}
    foreach ($line in (Get-Content -LiteralPath (Join-Path $work 'SHA256SUMS'))) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$') { $sums[$Matches[2]] = $Matches[1].ToLowerInvariant() }
    }
    foreach ($name in 'GodspeedSetup.exe', 'windows-manifest.json') {
        $have = (Get-FileHash -LiteralPath (Join-Path $work $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sums[$name] -ne $have) {
            Write-Host "  The downloaded $name does not match the release's checksum, so I did not run it. Nothing was changed." -ForegroundColor Red
            Close-Update 1
        }
    }
    Write-Host "  Installing it. A window shows what it does; this can take a few minutes. Your notes, files and settings stay as they are."
    # WaitForExit on the setup itself, never Start-Process -Wait: -Wait also waits for everything the
    # setup starts, and the notebook it starts keeps running on purpose.
    $setup = Start-Process -FilePath (Join-Path $work 'GodspeedSetup.exe') -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru
    $setup.WaitForExit()
    $code = $setup.ExitCode
    $after = $null
    try { $after = Get-Content -LiteralPath (Join-Path $State 'installation.json') -Raw | ConvertFrom-Json } catch { }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    if ($code -eq 0 -and $after -and $after.kitCommit -eq $latest.kitCommit) {
        Write-Host ""
        Write-Host "  Your mission control is up to date ($version$(Get-Short $latest.kitCommit))." -ForegroundColor Green
        Close-Update 0
    }
    Write-Host ""
    Write-Host "  The update did not finish (the setup ended with $code). What happened is written in" -ForegroundColor Red
    Write-Host "  $(Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt'). Your notes are kept. Running this again tries once more."
    Close-Update 1
}

if ($latest) {
    if ($config -and $latest.kitCommit -eq $config.kitCommit) { Write-Host "  You have the newest version already." }
    elseif ($config) { Write-Host "  This PC has a version newer than the newest release, so there is nothing to download." }
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($CheckOnly) { Write-Host "  CHECK: would bring this PC up to date with the version it has."; exit 0 }
Write-Host "  Bringing your mission control folder and this PC's wiring up to date..."
Write-Host ""

# The setup this PC has, for the folder the notebook keeps. Named, never left to the search: a PC
# whose notebook sits beside an older mission control works from that older one, and the setup
# then stopped at "An upgrade cannot silently change the workspace". When the notebook does sit
# beside another mission control, -Beside keeps the PC working from that one, as it did.
$setupArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'setup-godspeed.ps1'), '-IntegratedNotebook', '-NoPause')
if ($KbBranch) { $setupArgs += @('-KbBranch', $KbBranch) }
if ($config -and $config.workspace) {
    $setupArgs += @('-Godspeed', $config.workspace)
    # The same question the wizard asks first (detect-godspeed.ps1), in a window of its own because
    # it loads the install code.
    $answers = Join-Path ([IO.Path]::GetTempPath()) ('godspeed-found-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot 'detect-godspeed.ps1') -Join (Join-Path $PSScriptRoot 'join.ps1') -Out $answers -State $State | Out-Null
    $worksFrom = ''
    if (Test-Path -LiteralPath $answers) {
        foreach ($line in (Get-Content -LiteralPath $answers)) { if ($line -like 'worksfrom=*') { $worksFrom = $line.Substring(10) } }
        Remove-Item -LiteralPath $answers -Force -ErrorAction SilentlyContinue
    }
    if ($worksFrom) {
        Write-Host "  This PC keeps working from $worksFrom, as before."
        $setupArgs += '-Beside'
    }
}
& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @setupArgs
Close-Update $LASTEXITCODE
