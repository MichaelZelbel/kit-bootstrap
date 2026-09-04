# =============================================================================
# kit-bootstrap / windows / setup-hub.ps1
#
# The engine behind HubSetup.exe. The .exe is the wizard a person clicks; this
# file is the work it does.
#
# Why it exists: until 2026-08-09 the only way onto a Windows PC was to paste a
# long line into PowerShell. Michael's words for that were "cryptic commands",
# and he was right - nobody else's software asks that. Windows people expect a
# file they double-click, which then works out for itself whether this machine
# needs a first install or an update. This is that, and the wizard around it is
# only a face on top.
#
# It decides between two jobs by looking, never by asking:
#   nothing here yet  -> INSTALL   (fetch what is missing, then make the hub)
#   already have one  -> UPDATE    (bring it current, then re-check the wiring)
#
# Safe to run as many times as you like. It never deletes a memory.
#
# Usage on its own, without the .exe:
#   powershell -ExecutionPolicy Bypass -File setup-hub.ps1 [-Hub C:\Users\you\hub] [-RepoUrl <git url>]
#
#   -Beside   put a SECOND hub at -Hub and leave this computer working from the one
#             it already has. Needs -Hub, and needs a hub already here to sit beside.
#             For a work hub next to a personal one, for trying a hub before moving
#             into it, and for a clean hub to record on a machine that carries a full
#             one. See Test-KitBeside in join.ps1 for what it leaves alone and why.
# =============================================================================
param(
    [string]$Hub,
    [string]$RepoUrl,
    # Which product this installer is for. A brand-new hub is copied from that
    # repository's starter folder rather than written from imagination, so what a
    # reader ends up with is the folder their book actually walks them through.
    # Another kit building its own .exe overrides these two and changes nothing else.
    [string]$StarterRepo = 'https://github.com/MichaelZelbel/teach-it-once-kit.git',
    [string]$StarterPath = 'starter-hub',
    # Which AI tools may be synced from this PC, as a comma list (e.g. claude,codex).
    # '-' or '' means none. The default '(auto)' means "no choice made this run": keep
    # what this device already has recorded, or every syncable tool found here. The
    # wizard fills this from its checklist page.
    [string]$PromptSources = '(auto)',
    [switch]$SkipPrereqs,
    [switch]$NoPause,
    [switch]$Beside,
    # Which kit-bootstrap tag or branch the shared install code comes from. The wizard
    # passes the tag this .exe was built from, so a reader runs exactly the code that
    # passed its runs, the same promise install-hub.sh has always made on macOS and Linux.
    # Empty falls back to KB_BRANCH and then to the moving v2 branch, which is what a
    # developer running this file straight out of a checkout wants.
    [string]$KbBranch
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 is what a double-clicked installer runs under, and it
# still asks for TLS below 1.2 by default. GitHub refuses that, so without this
# line the very first download fails on a stock PC and says nothing useful about
# why. It has to be here as well as in the shared code, because it is needed to
# fetch the shared code.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# A log, because the wizard window closes and takes its output with it. When
# somebody says "it did not work", this file is the answer.
$LogDir = Join-Path $env:LOCALAPPDATA 'Hub'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'setup-log.txt'
try { Start-Transcript -Path $LogFile -Append -ErrorAction Stop | Out-Null } catch { }

function Stop-Setup {
    param([string]$Message, [int]$Code = 1)
    Write-Host ""
    Write-Host "  STOPPED: $Message" -ForegroundColor Red
    Write-Host ""
    Write-Host "  The full record of this run is at:"
    Write-Host "    $LogFile"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    if (-not $NoPause) { Write-Host ""; Read-Host "  Press Enter to close" | Out-Null }
    exit $Code
}

Write-Host ""
Write-Host "  Setting up your hub" -ForegroundColor Cyan
Write-Host "  ==================="
Write-Host ""

# -----------------------------------------------------------------------------
# 1. The shared install code.
#
# Fetched from the network FIRST and only then from the copy inside this .exe.
# That order is the whole point: an installer somebody downloaded in March runs
# March's code otherwise, on precisely the machine that has been neglected
# longest. A PC with no network still finishes, using what it shipped with.
# -----------------------------------------------------------------------------
# WHICH BRANCH THIS INSTALLER PULLS ITS LIBRARY FROM, in one place, because getting it
# wrong is invisible: a v2 installer that fetches v1\join.ps1 runs v1's code and behaves
# exactly like v1, so a whole line of work reaches nobody while every test that fetches
# from the network still passes. The bash twin carries KB_BRANCH for the same reason.
# Overridable so a test can point at a branch without editing this file.
# THE PIN, AND WHY WINDOWS NOW HAS ONE (2026-09-04).
#
# install-hub.sh has always pinned an immutable TAG, and says why in its own comment: this
# book's readers get exactly the code that passed its end-to-end runs. This file defaulted to
# the moving v2 branch instead, so the two platforms made different promises and only one of
# them was written down. The consequence was real: on 2026-09-03 six pushes to v2 reached
# every Windows reader who ran the installer, hours before the release that described them
# existed, while macOS and Linux readers stayed on the previous tag until its pin moved.
#
# So the wizard passes -KbBranch with the tag the .exe was built from, and
# build-installer.ps1 refuses to build unless that tag exists and names the very commit being
# built. A developer running this file straight from a checkout passes nothing and still gets
# v2, which is what they want.
#
# The self-healing this gives up (an installer saved in March fetching today's fixes) is paid
# for by the copy of join.ps1 inside the .exe, which is now the same code as the pin rather
# than a fallback for a machine with no network.
if (-not $KbBranch) { $KbBranch = if ($env:KB_BRANCH) { $env:KB_BRANCH } else { 'v2' } }

# WHAT THE CALLER ASKED FOR, KEPT SAFE ACROSS THE LIBRARY LOAD.
#
# join.ps1 is a script in its own right as well as this file's library, so it has its own
# param block, and that block declares [string]$Hub. Dot-sourcing runs a param block IN THE
# CALLER'S SCOPE, so `. $Join -AsLibrary` set $Hub back to its default of $null and threw
# away whatever -Hub this installer was given. -Hub therefore never worked, on any run,
# since the day the library grew that parameter, and nothing ever said so: with $Hub empty,
# Find-KitHub simply detected the machine's existing hub and the common case looked perfect.
# It surfaced on 2026-09-03 as "-Beside needs -Hub as well" on a command line that plainly
# had one.
#
# Saved here and put back after every load, rather than renaming the library's parameter,
# because readers run join.ps1 directly too and -Hub means the same thing to them.
$WantHub = $Hub

$Bundled = Join-Path $PSScriptRoot 'join.ps1'
$Join    = $null
$cache   = Join-Path $env:LOCALAPPDATA 'Hub\join.ps1'
try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 `
        -Uri "https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/$KbBranch/join.ps1" `
        -OutFile $cache -ErrorAction Stop
    $Join = $cache
    Write-Host "   ok: got the current install code"
} catch {
    if (Test-Path $Bundled) {
        $Join = $Bundled
        Write-Warning "no network, so I am using the copy that came with this installer. It may be behind."
    }
}
if (-not $Join) {
    Stop-Setup "I could not load the install code, and this installer has no copy of its own. Check that this PC can reach the internet, then run it again."
}

. $Join -AsLibrary

# Newer than the network copy is a real state, not a theoretical one: this .exe
# and the published branch are published by two separate acts, so either can be
# ahead. Preferring the network blindly would then load code with the parts this
# installer needs missing, and fail somewhere further down wearing a confusing
# name. Check for one function that only the newer code has, and step back to the
# copy inside the .exe when it is not there. The canary moves forward with the
# code: it is the NEWEST function this file calls, or the check passes on a copy
# that is missing everything added since.
if (-not (Get-Command Test-KitBeside -ErrorAction SilentlyContinue)) {
    if ($Join -ne $Bundled -and (Test-Path $Bundled)) {
        Write-Warning "the published install code is older than this installer, so I am using the copy that came with it."
        . $Bundled -AsLibrary
    }
}
# Both loads above are dot-sources, and both wiped it. See $WantHub.
$Hub = $WantHub

foreach ($fn in 'Install-KitPrereqs', 'New-KitHub', 'Copy-KitStarterHub', 'Find-KitHub',
                 'Join-KitMemory', 'Install-KitHubCli', 'Install-KitHubTools',
                 'Install-KitPromptHarvest', 'Update-KitPath',
                 'Find-KitAiTools', 'Set-KitPromptSources', 'Write-KitSyncReport',
                 'Connect-KitNotebook', 'Write-KitMcpConfig', 'Install-KitNotebookSync',
                 'Connect-KitSkills', 'Set-KitHermesHub', 'Set-KitHermesApprovals',
                 'Get-KitDefaultHubDir', 'Get-KitHubPathRefusal',
                 'Test-KitBeside', 'Test-KitSamePath') {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        Stop-Setup "the install code on this PC is incomplete ($fn is missing). Download the newest installer from https://github.com/MichaelZelbel/kit-bootstrap/releases/latest and run that."
    }
}

# -----------------------------------------------------------------------------
# 2. What this PC is missing. Git, Node.js, and whether Hermes is here.
# -----------------------------------------------------------------------------
$missing = @()
if (-not $SkipPrereqs) {
    $missing = @(Install-KitPrereqs)
} else {
    Update-KitPath
}
# Git is the one thing nothing else can work around: a hub is a git folder.
if (-not (Test-KitCommand 'git')) {
    Stop-Setup "Git is not on this PC and I could not install it. Get it from https://git-scm.com/download/win , then run this installer again."
}

# -----------------------------------------------------------------------------
# 3. Install or update? Look, do not ask.
# -----------------------------------------------------------------------------
# BESIDE means "do not ask this machine where its hub is". Find-KitHub answers that
# question, and on a machine that already works from one it answers with THAT one: it
# reads $env:HUB_DIR before it looks at anything else. So an explicit -Hub naming a
# folder that did not exist yet used to fall straight through to the hub already here,
# which was then brought up to date under a green tick while the folder actually asked
# for was never made and nothing said why. A beside run looks at the path it was given
# and at nothing else.
if ($Beside) {
    if (-not $Hub) {
        Stop-Setup "-Beside needs -Hub as well. It puts a hub in a place you name and leaves this PC working from the one it already has, so it has to be told where. Example: -Beside -Hub $(Get-KitDefaultHubDir)"
    }
    $other = Find-KitHub
    if (-not $other) {
        Stop-Setup "there is no hub on this PC yet, so there is nothing for a second one to sit beside. Run this without -Beside and it will make the first one."
    }
    if (Test-KitSamePath $other $Hub) {
        Stop-Setup "$Hub is the hub this PC already works from, so it cannot sit beside itself. Run this without -Beside to bring it up to date."
    }
    $env:KB_BESIDE = '1'
    Write-KbSay "This PC works from $other and keeps working from it. The new hub will sit beside it."
    $found = if (Test-KitHub $Hub) { (Resolve-Path $Hub).Path } else { $null }
} else {
    $found = Find-KitHub -Hint $Hub
    if ($found -and $Hub -and -not (Test-KitSamePath $found $Hub)) {
        Stop-Setup "you asked for a hub at $Hub, but this PC already works from $found. To put a second hub at $Hub and leave $found in charge of this PC, add -Beside. To bring $found up to date instead, leave off -Hub."
    }
}
$isNew = $false

if ($found) {
    $Hub = $found
    Write-KbSay "Found the hub already on this PC at $Hub"
    $before = (git -C $Hub rev-parse --short HEAD 2>$null)
    Update-KitHub -Hub $Hub
    $after = (git -C $Hub rev-parse --short HEAD 2>$null)
    if ($before -and $after -and $before -ne $after) {
        Write-KbOk "it was out of date. Brought it up to date ($before to $after)."
    }
    # The starter can grow after a hub is born (dev/ and its .gitignore arrived
    # 2026-08-19). Top up whatever is missing, top level only and never over
    # anything already there, so a re-run delivers new rooms without treading on
    # a word the person wrote. The one exception is .gitignore, which is merged
    # line-by-line inside Copy-KitStarterHub: every hub already has one, and
    # skip-if-present would keep the dev/ fence from ever reaching an old hub.
    # Before this line, an update run never looked at the starter at all, so a
    # new room only ever reached new hubs.
    $topupBefore = @(Get-ChildItem -Force -Name $Hub | Sort-Object)
    try { Copy-KitStarterHub -Path $Hub -StarterRepo $StarterRepo -StarterPath $StarterPath | Out-Null } catch {}
    $topupAfter = @(Get-ChildItem -Force -Name $Hub | Sort-Object)
    if (Compare-Object $topupBefore $topupAfter) {
        Write-KbOk "the starter grew since this hub was made; added what was missing, touched nothing else."
    }
} else {
    $isNew = $true
    if (-not $Hub) { $Hub = Get-KitDefaultHubDir }
    $why = Get-KitHubPathRefusal -Path $Hub
    if ($why) { Stop-Setup "I will not put the hub at ${Hub}: $why" }
    if ($Beside) { Write-KbSay "Making the hub at $Hub" }
    else          { Write-KbSay "No hub on this PC yet, so I am making one" }
    try { New-KitHub -Path $Hub -RepoUrl $RepoUrl -StarterRepo $StarterRepo -StarterPath $StarterPath }
    catch { Stop-Setup $_.Exception.Message }
    $Hub = (Resolve-Path $Hub).Path
}

# -----------------------------------------------------------------------------
# 4. The wiring. Identical whether this was an install or an update, which is why
#    running the installer twice is a normal thing to do rather than a mistake.
#
#    First, which AI tools live here and which may be synced. The wizard's
#    checklist arrives as -PromptSources; the choice lands on this device before
#    any wiring runs, so everything below obeys it. Sits AFTER the prerequisites
#    on purpose, so detection sees the machine as step 2 left it.
# -----------------------------------------------------------------------------
if ($PromptSources -ne '(auto)') {
    Set-KitPromptSources -Value $PromptSources
    if ($PromptSources.Trim() -eq '' -or $PromptSources.Trim() -eq '-') { $env:KB_SYNC_SOURCES = '-' }
    else { $env:KB_SYNC_SOURCES = $PromptSources }
}
Write-KitSyncReport

Join-KitMemory     -Hub $Hub    # the one memory every machine shares
Install-KitHubCli  -Hub $Hub    # the hub's own commands, on PATH, from any folder
Install-KitHubTools -Hub $Hub -ToolsRepo $StarterRepo   # the kit's own programs, on this machine
Install-KitPromptHarvest -Hub $Hub   # the daily job that files what you type to an AI here
# The notebook, and the one thing about it that has to travel: connect it once and the
# connection lives in the folder, so the next computer only ever types the passphrase.
# Quiet and complete for the reader who never connects one - which is most of the book.
Connect-KitNotebook -Hub $Hub

# One real room, junctions to it, and it counts what it wired. Replaces three lines
# that pointed .agents\skills at .claude\skills whenever .claude\skills existed, which
# on a hub built by the book meant pointing every non-Claude assistant at the empty
# folder the top-up had just made, under a green tick.
Connect-KitSkills -Hub $Hub | Out-Null

# Where Hermes works. terminal.cwd, never `workspace`, and proved by a file read
# rather than by reading the setting back. See the long note above the function: four
# of the six known ways to do this are silent no-ops and the kit shipped one.
Set-KitHermesHub -Hub $Hub | Out-Null

# The leash. A translation of the Claude permissions file, not a rename: Hermes
# already allows every command the kit runs, so this writes no allowlist at all and
# only closes the gaps its own floor leaves open. Measured, both ways.
Set-KitHermesApprovals | Out-Null

# Remember where it is, so the next run of the installer finds it instantly and so
# other tools on this PC can stop guessing. One of the five things that answer "which
# hub does this computer work from", so a hub sitting beside another one does not take
# it (Test-KitBeside in join.ps1 lists all five).
if (-not (Test-KitBeside)) {
    [Environment]::SetEnvironmentVariable('HUB_DIR', $Hub, 'User')
    $env:HUB_DIR = $Hub
}

# -----------------------------------------------------------------------------
# 5. What just happened, in words.
# -----------------------------------------------------------------------------
# Built from what actually happened on THIS PC, never from the promise. The old
# text claimed every assistant shares one memory, on machines where one tool (or
# none) had been wired. The truth lets a person see a gap; the promise hides it.
Write-KbSay "Done"
if (Test-KitBeside)  { Write-Host "This second hub is ready at:" }
elseif ($isNew)      { Write-Host "Your hub is at:" }
else                 { Write-Host "This PC is up to date and wired in. Your hub is at:" }
Write-Host ""
Write-Host "  $Hub"
Write-Host ""
if (Test-KitBeside) {
    Write-Host "It has its own folders, its own git history and its own assistant memory."
    Write-Host "This PC still works from $other, which keeps the hub commands, the daily"
    Write-Host "job, the hourly notebook job and the folder Hermes starts in. To work in"
    Write-Host "the new one, open a terminal or an assistant inside it."
    Write-Host ""
}
Write-KitSyncReport
Write-Host @"

Two things worth knowing:

  * Open a NEW terminal window before you use the hub commands. Windows only
    hands the updated list of commands to windows opened after an install.
  * Your hub travels between machines through git. Push it from here, and run
    this same installer on the next machine to pick it up there. To change which
    AI tools are read on this PC, run the installer again, or edit
    HUB_PROMPT_SOURCES in $HOME\.hub\device.env
"@

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Warning "I could not install these, so some things will not work until they are here: $($missing -join ', ')"
}

Write-Host ""
Write-Host "  A record of this run is at $LogFile"
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
if (-not $NoPause) { Write-Host ""; Read-Host "  Press Enter to close" | Out-Null }
exit 0
