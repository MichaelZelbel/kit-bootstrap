# =============================================================================
# kit-bootstrap / windows / test-windows.ps1
#
# The Windows half of test.sh. Run it before pushing anything that touches
# join.ps1 or the installer:
#
#   powershell -ExecutionPolicy Bypass -File test-windows.ps1
#
# Run it under WINDOWS POWERSHELL 5.1 at least once, not only under 7. The .exe
# runs 5.1, and the first two bugs this suite ever caught were both "works in 7,
# throws in 5.1" - the shape of bug that reaches every reader and never the
# author.
#
# It writes only inside its own temporary folder and removes it at the end. It
# never touches a real hub.
# =============================================================================
$ErrorActionPreference = 'Continue'

$Pass = 0
$Fail = 0
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

# THE SUITE PUTS THE USER'S REAL PATH BACK WHEN IT FINISHES, AND IT HAS TO.
#
# Install-KitHubTools prepends its bin folder to the PERSISTED user PATH, and skips doing so when
# that exact folder is already in there. In real life the folder is $HOME\.local\bin and never
# moves, so it is written once. In here every case gets a fresh temporary HOME, so every case is a
# folder that was never in the list, and every run of this suite left a few more dead temporary
# paths behind for good. Found on 2026-08-29 with 44 of them in one account and the variable
# 4,221 characters long, at which point Windows starts refusing to set it and the last cases in
# this file fail with "Environment variable name or value is too long" - a message that names
# nothing about what actually happened.
#
# So: remember it now, put it back at the end, and never mind what any case did in between.
$UserPath0 = [Environment]::GetEnvironmentVariable('Path', 'User')

function Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        if ($r) { Write-Host "  ok    $Name"; $script:Pass++ }
        else    { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:Fail++ }
    } catch {
        Write-Host "  FAIL  $Name  ($($_.Exception.Message))" -ForegroundColor Red
        $script:Fail++
    }
}

function New-TestDir { param([string]$Name) $p = Join-Path $Root $Name; New-Item -ItemType Directory -Force $p | Out-Null; return $p }

function New-SourceHub {
    <# A committed git repo that looks like a hub, to clone from. #>
    param([string]$Path)
    New-Item -ItemType Directory -Force $Path | Out-Null
    git -C $Path init -q
    Set-Content (Join-Path $Path 'AGENTS.md') '# source hub'
    New-Item -ItemType Directory -Force (Join-Path $Path 'observations') | Out-Null
    Set-Content (Join-Path $Path 'observations\MEMORY.md') '# What I remember'
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path -c user.email='t@t' -c user.name='t' commit -q -m 'hub' 2>&1 | Out-Null
}

Write-Host ""
Write-Host "PowerShell $($PSVersionTable.PSVersion) - $($PSVersionTable.PSEdition)" -ForegroundColor Cyan
Write-Host "scratch: $Root"
Write-Host ""

New-Item -ItemType Directory -Force $Root | Out-Null
. (Join-Path $PSScriptRoot '..\join.ps1') -AsLibrary

Write-Host "-- the library loads and offers what the installer calls"
foreach ($fn in 'Find-KitHub', 'Test-KitHub', 'Update-KitHub', 'Join-KitMemory', 'Install-KitHubCli',
                 'Install-KitPrereqs', 'New-KitHub', 'Update-KitPath', 'Set-KbTextFile', 'Test-KitCommand',
                 'Install-KitPromptHarvest', 'Install-KitHubTools',
                 'Test-KitAiTool', 'Get-KitAiToolInfo', 'Find-KitAiTools', 'Get-KitEnabledSources',
                 'Get-KitNotebookState', 'Unlock-KitHubKey', 'Protect-KitHubKey',
                 'Save-KitNotebookToken', 'Write-KitMcpConfig', 'Install-KitNotebookSync',
                 'Set-KitNotebookEnv', 'Connect-KitNotebook', 'Test-KitInteractive',
                 'Set-KitPromptSources', 'Write-KitSyncReport', 'Get-KitHome',
                 'Write-KitExpiryRecord', 'Write-KitDueFolder', 'Get-KitRoomTwin') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}

Write-Host ""
Write-Host "-- writing text files (this is where PowerShell 5.1 differs from 7)"
Check "writes a file with blank lines in it" {
    $f = Join-Path (New-TestDir 'write') 'a.md'
    Set-KbTextFile -Path $f -Lines @('# title', '', 'body')
    (Test-Path $f) -and ((Get-Content $f).Count -eq 3)
}
Check "writes UTF-8 with NO byte-order mark" {
    $f = Join-Path (New-TestDir 'write2') 'b.md'
    Set-KbTextFile -Path $f -Lines @('# hi')
    $bytes = [System.IO.File]::ReadAllBytes($f)
    # A BOM would be EF BB BF. The first byte must be the '#' itself.
    $bytes[0] -eq 0x23
}
Check "an unwritable path throws instead of reporting success" {
    try { Set-KbTextFile -Path (Join-Path $Root 'no\such\folder\x.md') -Lines @('x'); $false }
    catch { $true }
}

Write-Host ""
Write-Host "-- telling a hub from a folder that merely looks like one"
Check "a folder that does not exist is not a hub"      { -not (Test-KitHub (Join-Path $Root 'ghost')) }
Check "an empty folder is not a hub"                   { -not (Test-KitHub (New-TestDir 'empty')) }
Check "a git folder with no hub files is not a hub"    {
    $d = New-TestDir 'bare'; git -C $d init -q; -not (Test-KitHub $d)
}
Check "a git folder with memory/ IS a hub"             {
    $d = New-TestDir 'real'; git -C $d init -q
    New-Item -ItemType Directory -Force (Join-Path $d 'memory') | Out-Null
    Test-KitHub $d
}
Check "a hint pointing at a real hub is used"          {
    $d = New-TestDir 'hinted'; git -C $d init -q; Set-Content (Join-Path $d 'AGENTS.md') 'x'
    (Find-KitHub -Hint $d) -eq (Resolve-Path $d).Path
}
Check "a hint pointing at rubbish is not trusted"      {
    (Find-KitHub -Hint (Join-Path $Root 'ghost')) -ne (Join-Path $Root 'ghost')
}

Write-Host ""
Write-Host "-- making a hub when the PC has none"
Check "a fresh hub is created and recognised" {
    $d = Join-Path $Root 'fresh'
    New-KitHub -Path $d | Out-Null
    (Test-KitHub $d) -and (Test-Path (Join-Path $d 'AGENTS.md')) -and (Test-Path (Join-Path $d 'observations\MEMORY.md'))
}
Check "making one twice is safe and keeps what is there" {
    $d = Join-Path $Root 'fresh'
    Set-Content (Join-Path $d 'AGENTS.md') '# mine, edited'
    New-KitHub -Path $d | Out-Null
    (Get-Content (Join-Path $d 'AGENTS.md') -Raw).Contains('mine, edited')
}
Check "a folder with somebody else's files in it is refused" {
    $d = New-TestDir 'occupied'; Set-Content (Join-Path $d 'holiday.jpg') 'x'
    try { New-KitHub -Path $d | Out-Null; $false } catch { $true }
}
Check "an existing hub is cloned from its repository" {
    $src = Join-Path $Root 'src'; New-SourceHub -Path $src
    $dst = Join-Path $Root 'cloned'
    New-KitHub -Path $dst -RepoUrl $src | Out-Null
    (Test-KitHub $dst) -and (Test-Path (Join-Path $dst 'AGENTS.md'))
}
Check "an address that is not a repository is refused, not half-done" {
    try { New-KitHub -Path (Join-Path $Root 'bad') -RepoUrl (Join-Path $Root 'ghost') | Out-Null; $false }
    catch { $_.Exception.Message -like '*Could not copy that repository*' }
}

Write-Host ""
Write-Host "-- a new hub copies the product's starter folder, it never invents one"
Check "the starter folder's files are laid down" {
    # A local fixture, so this case does not need the network to mean anything.
    $sr = Join-Path $Root 'starter-src'
    # Deliberately the OLD name: a starter from before the rename must come out renamed,
    # which is what a reader who downloaded the kit months ago actually has.
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-hub\context') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-hub\skills') | Out-Null
    Set-Content (Join-Path $sr 'starter-hub\AGENTS.md') '# the real one'
    Set-Content (Join-Path $sr 'starter-hub\context\about-me.md') 'about'
    Set-Content (Join-Path $sr 'starter-hub\skills\plan-my-day.md') 'plan'
    git -C $sr init -q
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'starter' 2>&1 | Out-Null

    $d = Join-Path $Root 'fromstarter'
    New-KitHub -Path $d -StarterRepo $sr | Out-Null
    (Test-Path (Join-Path $d 'profile\about-me.md')) -and (Test-Path (Join-Path $d 'skills\plan-my-day.md'))
}
Check "the starter's own AGENTS.md wins, no invented one overwrites it" {
    (Get-Content (Join-Path $Root 'fromstarter\AGENTS.md') -Raw).Contains('the real one')
}
Check "the starter's own memory page is kept, not replaced by a blank one" {
    $sr = Join-Path $Root 'starter-src'
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-hub\observations') | Out-Null
    Set-Content (Join-Path $sr 'starter-hub\observations\MEMORY.md') '# the product wrote this'
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'memory' 2>&1 | Out-Null
    $d = Join-Path $Root 'keepindex'
    New-KitHub -Path $d -StarterRepo $sr | Out-Null
    (Get-Content (Join-Path $d 'observations\MEMORY.md') -Raw).Contains('the product wrote this')
}
Check "a starter that cannot be fetched still leaves a usable hub, and warns" {
    $d = Join-Path $Root 'nostarter'
    $warned = $false
    try { New-KitHub -Path $d -StarterRepo (Join-Path $Root 'ghost-repo') -WarningVariable w -WarningAction SilentlyContinue | Out-Null
          $warned = @($w).Count -gt 0 } catch { }
    (Test-KitHub $d) -and $warned
}
Check "the real book kit's starter folder is reachable and has what the book names" {
    # The one case that must hit the network: it checks the DEFAULT a reader gets.
    $d = Join-Path $Root 'realstarter'
    $got = Copy-KitStarterHub -Path $d -StarterRepo 'https://github.com/MichaelZelbel/teach-it-once-kit.git'
    if (-not $got) { Write-Host "        (skipped: no network)"; return $true }
    $missing = @()
    foreach ($f in 'AGENTS.md', 'profile\about-me.md', 'profile\people.md', 'profile\voice.md',
                    'procedures.md', 'decisions.md', 'observations\MEMORY.md', 'rules', 'skills') {
        if (-not (Test-Path (Join-Path $d $f))) { $missing += $f }
    }
    if ($missing.Count) { Write-Host "        missing: $($missing -join ', ')" }
    # skills/ must ARRIVE and must arrive EMPTY. The five starter recipes moved out of
    # starter-hub/ into the kit's own skills/ on 2026-08-20, so the first recipe in a
    # reader's folder is one they wrote themselves. This branch kept looking for one of
    # them, which is a red that is not true.
    $recipes = @(Get-ChildItem (Join-Path $d 'skills') -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -eq '.md' }).Count
    if ($recipes -gt 0) { Write-Host "        skills/ arrived with $recipes recipe(s) in it" }
    ($missing.Count -eq 0) -and ($recipes -eq 0)
}

Write-Host ""
Write-Host "-- updating one that is already here"
Check "updating a folder that is not git is a warning, not a crash" {
    Update-KitHub -Hub (New-TestDir 'notgit') 3>$null; $true
}
Check "an offline update still lets the rest of the run finish" {
    $d = New-TestDir 'nogit-remote'; git -C $d init -q
    Set-Content (Join-Path $d 'AGENTS.md') 'x'
    Update-KitHub -Hub $d 3>$null; $true
}
Check "a hub with no remote is not called out of date" {
    # A hub made five minutes ago has nowhere to be out of date FROM, so
    # "could not pull, this may be out of date" is alarming and untrue.
    $d = New-TestDir 'noremote'; git -C $d init -q
    Set-Content (Join-Path $d 'AGENTS.md') 'x'
    # 6>&1 as well as 3>&1: Write-Host goes to the INFORMATION stream, not the
    # output or warning ones, so a test that only catches warnings sees nothing
    # and calls a working message a failure.
    $out = (Update-KitHub -Hub $d 3>&1 6>&1 | Out-String)
    (-not $out.Contains('could not pull')) -and $out.Contains('lives only on this computer')
}

Write-Host ""
Write-Host "-- the PATH, and finding the tools"
Check "Update-KitPath leaves a usable PATH"   { Update-KitPath; $env:Path -and ($env:Path.Length -gt 10) }
Check "Test-KitCommand finds a real command"  { Test-KitCommand 'git' }
Check "Test-KitCommand refuses an invented one" { -not (Test-KitCommand 'definitely-not-a-real-command-xyz') }
Check "an already-present tool is not reinstalled" {
    # Short-circuits on the command being there, so it must not call winget at all.
    Install-KitWingetPackage -Id 'Bogus.Package' -Command 'git' -Human 'Git'
}
Check "Git Bash is found via git, not via the PATH's bash" {
    $b = Get-KitGitBash
    (-not $b) -or ($b -like '*Git*bash.exe')
}

Write-Host ""
Write-Host "-- which AI tools live here, and who said yes"
# Added 2026-08-11. Before this the installer wired sync with no detection, no
# disclosure and no choice: it invented a ~\.claude folder on PCs that had never
# seen Claude Code, and the harvest read Codex's logs and pushed them to the
# repository without a word. These are the Windows twins of the cases in
# test.sh. When you change one side, change both.
#
# Detection is FORCED (KB_ASSUME_TOOLS) and the home folder is a scratch one
# (KB_HOME), never read from the PC running the suite, so the suite behaves the
# same on a machine crowded with AI tools and on a bare one.
Check "an assumed tool is reported with its powers" {
    try { $env:KB_ASSUME_TOOLS = 'claude'
          @(Find-KitAiTools) -contains 'claude|memory+prompts|Claude Code|' }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "a machine with nothing reports nothing" {
    try { $env:KB_ASSUME_TOOLS = '-'; @(Find-KitAiTools).Count -eq 0 }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "an unsyncable tool is reported with its reason" {
    try { $env:KB_ASSUME_TOOLS = 'comet'
          @(Find-KitAiTools | Where-Object { $_ -match 'not in files here' }).Count -eq 1 }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "no flag and no record means every syncable tool found" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex,comet'; $env:KB_HOME = New-TestDir 'src-home1'
          (Get-KitEnabledSources) -eq 'claude,codex' }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HOME = $null }
}
Check "the choice recorded on the device wins over detection" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex'; $env:KB_HOME = New-TestDir 'src-home2'
          New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.hub') | Out-Null
          Set-Content (Join-Path $env:KB_HOME '.hub\device.env') 'HUB_PROMPT_SOURCES=claude' -Encoding ascii
          (Get-KitEnabledSources) -eq 'claude' }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HOME = $null }
}
Check "the flag this run wins over the record, and dash means none" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex'; $env:KB_HOME = New-TestDir 'src-home2'
          $env:KB_SYNC_SOURCES = 'codex'
          $one = (Get-KitEnabledSources) -eq 'codex'
          $env:KB_SYNC_SOURCES = '-'
          $one -and ((Get-KitEnabledSources) -eq '') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HOME = $null; $env:KB_SYNC_SOURCES = $null }
}
Check "the choice is recorded, replaced not stacked, neighbours kept" {
    try { $env:KB_HOME = New-TestDir 'src-home3'
          New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.hub') | Out-Null
          Set-Content (Join-Path $env:KB_HOME '.hub\device.env') 'HUB_DIR=C:\somewhere' -Encoding ascii
          Set-KitPromptSources -Value 'claude,codex' | Out-Null
          Set-KitPromptSources -Value 'claude' | Out-Null
          $lines = @(Get-Content (Join-Path $env:KB_HOME '.hub\device.env'))
          (@($lines | Where-Object { $_ -eq 'HUB_PROMPT_SOURCES=claude' }).Count -eq 1) -and
          (@($lines | Where-Object { $_ -match '^HUB_PROMPT_SOURCES=' }).Count -eq 1) -and
          (@($lines | Where-Object { $_ -eq 'HUB_DIR=C:\somewhere' }).Count -eq 1) }
    finally { $env:KB_HOME = $null }
}
Check "the report says what is synced, what was left alone, what cannot be" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex,comet'; $env:KB_SYNC_SOURCES = 'claude'
          $rep = (Write-KitSyncReport 6>&1 | Out-String)
          $rep.Contains('Claude Code: its memory folder') -and
          $rep.Contains('Codex (switched off by your choice') -and
          $rep.Contains('Perplexity Comet:') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}
Check "a PC syncing nothing is told so" {
    try { $env:KB_ASSUME_TOOLS = '-'; $env:KB_SYNC_SOURCES = '-'
          (Write-KitSyncReport 6>&1 | Out-String).Contains('Nothing is synced') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}

Write-Host ""
Write-Host "-- the assistant the prereqs confirm: Hermes, not Claude Code"
# Batch AK, decided 2026-09-01: Hermes is the taught assistant from Chapter 3,
# so the prereqs deal in Hermes. Windows installs no app - Hermes Desktop ships
# its own hermes-setup.exe, exactly as the Claude desktop app was always the
# reader's own download - so Confirm-KitHermes CONFIRMS and points, never
# fetches. Install-KitClaudeCode stays defined, the Chapter 5 developer door.
# These are the Windows twins of the cases in test.sh. Change one, change both.
$script:RealHermesHome = $env:HERMES_HOME
$script:RealLocalApp   = $env:LOCALAPPDATA

Check "Confirm-KitHermes is defined" {
    [bool](Get-Command Confirm-KitHermes -ErrorAction SilentlyContinue)
}
Check "Install-KitClaudeCode stays defined, the Chapter 5 door" {
    [bool](Get-Command Install-KitClaudeCode -ErrorAction SilentlyContinue)
}
Check "a PC with Hermes is confirmed" {
    try { $env:KB_ASSUME_TOOLS = 'hermes'; (Confirm-KitHermes 6>$null) -eq $true }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "a PC without Hermes is pointed at the download, not left guessing" {
    try { $env:KB_ASSUME_TOOLS = '-'
          $env:KB_HERMES_BIN = Join-Path $Root 'no-such-hermes.exe'
          (-not (Confirm-KitHermes 3>$null 6>$null)) -and
          ((Confirm-KitHermes 3>&1 6>&1 | Out-String).Contains('hermes-agent.nousresearch.com')) }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HERMES_BIN = $null }
}
Check "the prereqs count a missing Hermes, and never Claude Code" {
    try { $env:KB_ASSUME_TOOLS = '-'
          $env:KB_HERMES_BIN = Join-Path $Root 'no-such-hermes.exe'
          $missing = @(Install-KitPrereqs 6>$null)
          ($missing -contains 'Hermes') -and ($missing -notcontains 'Claude Code') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HERMES_BIN = $null }
}
Check "a PC with Hermes is missing nothing, and Claude Code is never mentioned" {
    try { $env:KB_ASSUME_TOOLS = 'hermes'
          $txt = (Install-KitPrereqs 6>&1 | Out-String)
          $missing = @(Install-KitPrereqs 6>$null)
          ($missing.Count -eq 0) -and (-not $txt.Contains('Claude Code')) }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "hermes is seen where HERMES_HOME points" {
    try { $d = New-TestDir 'hm-hh'; Set-Content (Join-Path $d 'config.yaml') 'x'
          $env:HERMES_HOME = $d; $env:LOCALAPPDATA = New-TestDir 'hm-la0'
          $env:KB_HOME = New-TestDir 'hm-home0'
          Test-KitAiTool 'hermes' }
    finally { $env:HERMES_HOME = $script:RealHermesHome
              $env:LOCALAPPDATA = $script:RealLocalApp; $env:KB_HOME = $null }
}
Check "a native install under LOCALAPPDATA is seen" {
    try { $env:HERMES_HOME = $null
          $la = New-TestDir 'hm-la1'
          New-Item -ItemType Directory -Force (Join-Path $la 'hermes') | Out-Null
          Set-Content (Join-Path $la 'hermes\config.yaml') 'x'
          $env:LOCALAPPDATA = $la; $env:KB_HOME = New-TestDir 'hm-home1'
          Test-KitAiTool 'hermes' }
    finally { $env:HERMES_HOME = $script:RealHermesHome
              $env:LOCALAPPDATA = $script:RealLocalApp; $env:KB_HOME = $null }
}
Check "a default-profile install with no profiles folder is still seen" {
    # The old marker required .hermes\profiles and missed exactly this shape,
    # which is how Hermes was invisible on the machine of the person writing
    # the book about it.
    try { $env:HERMES_HOME = $null; $env:LOCALAPPDATA = New-TestDir 'hm-la2'
          $h = New-TestDir 'hm-home2'
          New-Item -ItemType Directory -Force (Join-Path $h '.hermes') | Out-Null
          Set-Content (Join-Path $h '.hermes\config.yaml') 'x'
          $env:KB_HOME = $h
          Test-KitAiTool 'hermes' }
    finally { $env:HERMES_HOME = $script:RealHermesHome
              $env:LOCALAPPDATA = $script:RealLocalApp; $env:KB_HOME = $null }
}
Check "no config file anywhere means not seen" {
    try { $env:HERMES_HOME = $null; $env:LOCALAPPDATA = New-TestDir 'hm-la3'
          $env:KB_HOME = New-TestDir 'hm-home3'
          -not (Test-KitAiTool 'hermes') }
    finally { $env:HERMES_HOME = $script:RealHermesHome
              $env:LOCALAPPDATA = $script:RealLocalApp; $env:KB_HOME = $null }
}
Check "the report calls it Hermes, not chat bots" {
    (Get-KitAiToolInfo 'hermes') -eq 'prompts|Hermes|'
}

Write-Host ""
Write-Host "-- the memory link, which is the point of the whole thing"
# Detection is FORCED to "Claude Code is here" for the link cases, because the
# link is gated on it now and these cases are about the link itself. The gate
# has its own cases below.
Check "the memory path is derived from the hub folder" {
    (Get-KitMemoryLinkPath -Hub 'C:\hub') -eq (Join-Path $HOME '.claude\projects\c--hub\memory')
}
Check "linking a hub makes a junction that points back at it" {
    try {
        $env:KB_ASSUME_TOOLS = 'claude'
        $d = Join-Path $Root 'linkme'
        New-KitHub -Path $d | Out-Null
        Join-KitMemory -Hub $d | Out-Null
        $link = Get-KitMemoryLinkPath -Hub $d
        $item = Get-Item $link -Force -ErrorAction SilentlyContinue
        $ok = $item -and $item.LinkType -and ((Resolve-Path (@($item.Target)[0])).Path -eq (Resolve-Path (Join-Path $d 'observations')).Path)
        if ($item) { (Get-Item $link -Force).Delete() }
        Remove-Item (Split-Path $link -Parent) -Recurse -Force -ErrorAction SilentlyContinue
        $ok
    } finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "a memory already in the old place is carried over, never lost" {
    try {
        $env:KB_ASSUME_TOOLS = 'claude'
        $d = Join-Path $Root 'carry'
        New-KitHub -Path $d | Out-Null
        $link = Get-KitMemoryLinkPath -Hub $d
        New-Item -ItemType Directory -Force $link | Out-Null
        Set-Content (Join-Path $link 'precious.md') 'do not lose me'
        Join-KitMemory -Hub $d 3>$null | Out-Null
        $carried = Test-Path (Join-Path $d 'observations\precious.md')
        $kept    = @(Get-ChildItem (Split-Path $link -Parent) -Directory | Where-Object { $_.Name -like 'memory.replaced-*' }).Count -gt 0
        $item = Get-Item $link -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType) { (Get-Item $link -Force).Delete() }
        Remove-Item (Split-Path $link -Parent) -Recurse -Force -ErrorAction SilentlyContinue
        $carried -and $kept
    } finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "no Claude Code means no junction and no invented folder" {
    # THE GATE. Before it, a PC that had never seen Claude Code got a fabricated
    # ~\.claude profile folder out of nowhere.
    try {
        $env:KB_ASSUME_TOOLS = '-'
        $d = Join-Path $Root 'nogate'
        New-KitHub -Path $d | Out-Null
        Join-KitMemory -Hub $d | Out-Null
        $link = Get-KitMemoryLinkPath -Hub $d
        (-not (Test-Path $link)) -and (Test-Path (Join-Path $d 'observations\MEMORY.md'))
    } finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "Claude Code switched off means its folder is left alone" {
    try {
        $env:KB_ASSUME_TOOLS = 'claude'
        $env:KB_SYNC_SOURCES = 'codex'
        $d = Join-Path $Root 'offgate'
        New-KitHub -Path $d | Out-Null
        Join-KitMemory -Hub $d | Out-Null
        -not (Test-Path (Get-KitMemoryLinkPath -Hub $d))
    } finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}

Write-Host ""
Write-Host "-- the kit's own programs, installed on the machine"
# Added 2026-08-10. The collector used to exist in exactly one person's own hub, so the
# program the book promises its readers ("a program fills it") was nowhere they could get
# it. It lives in the kit now and is installed ON THE PC, never copied into the hub folder,
# because Chapter 4 promises the hub is a folder of text files and that nothing in it needs
# a terminal. These are the Windows twins of the cases in test.sh. Change one, change both.
function New-TestKit {
    param([string]$Path)
    New-Item -ItemType Directory -Force (Join-Path $Path 'tools') | Out-Null
    Set-Content (Join-Path $Path 'tools\prompt-harvest.js')   'console.log(1)'
    Set-Content (Join-Path $Path 'tools\compile-rules.js')    'console.log(1)'
    Set-Content (Join-Path $Path 'tools\hub-prompt-archive')  'print(1)'
    Set-Content (Join-Path $Path 'tools\hub-notebook-sync')   "#!/bin/sh`nexit 0"
    Set-Content (Join-Path $Path 'tools\hub-notebook-env')    "#!/bin/sh`nexit 0"
    Set-Content (Join-Path $Path 'tools\README.md')           '# not a program'
    git -C $Path init -q
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path -c user.email='t@t' -c user.name='t' commit -q -m 'tools' 2>&1 | Out-Null
}
Check "no kit named means nothing installed and nothing said" {
    $out = Install-KitHubTools -Hub (New-TestDir 'tools-none') -ToolsRepo '' 3>&1 4>&1 | Out-String
    $out.Trim() -eq ''
}
Check "the three programs land on the PC and a README does not" {
    $kit = New-TestDir 'kit'; New-TestKit -Path $kit
    $hub = New-TestDir 'tools-hub'
    $home0 = $HOME
    try {
        $env:HOME = New-TestDir 'tools-home'
        Set-Variable -Name HOME -Value $env:HOME -Scope Global -Force
        Install-KitHubTools -Hub $hub -ToolsRepo $kit | Out-Null
        $bin = Join-Path $HOME '.local\bin'
        (Test-Path (Join-Path $bin 'hub-prompt-archive')) -and
        (Test-Path (Join-Path $bin 'prompt-harvest.js')) -and
        (Test-Path (Join-Path $bin 'hub-prompt-harvest.cmd')) -and
        # The rules compiler is the one program in here a reader types by hand. Until
        # 2026-08-21 it was Python and the book named a path inside the hub that nobody
        # has. Without the .cmd, a bare compile-rules.js silently does nothing in
        # PowerShell, which is worse than an error.
        (Test-Path (Join-Path $bin 'compile-rules.js')) -and
        (Test-Path (Join-Path $bin 'hub-compile-rules.cmd')) -and
        -not (Test-Path (Join-Path $bin 'README.md')) -and
        # THE ONE THAT MATTERS: nothing was put inside the hub folder.
        (@(Get-ChildItem $hub -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -in 'hub-prompt-archive', 'prompt-harvest.js', 'compile-rules.js' }).Count -eq 0) -and
        # A scheduled job gets almost no environment, so where the hub is must be written down.
        (@(Get-Content (Join-Path $HOME '.hub\device.env') | Where-Object { $_ -match '^HUB_DIR=' }).Count -eq 1)
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $home0
    }
}
Check "the notebook runner lands with them, and a join refreshes from the kit written down" {
    # The notebook step schedules ~\.local\bin\hub-notebook-sync and silently does
    # nothing when it is missing, so this install is what decides whether a reader's
    # notebook ever updates itself. And a JOIN names no kit, so a later run with an
    # empty -ToolsRepo must refresh from the repo written down at install time.
    $kit = New-TestDir 'kit2'; New-TestKit -Path $kit
    $hub = New-TestDir 'tools-hub2'
    $home0 = $HOME
    try {
        $env:HOME = New-TestDir 'tools-home2'
        Set-Variable -Name HOME -Value $env:HOME -Scope Global -Force
        Install-KitHubTools -Hub $hub -ToolsRepo $kit | Out-Null
        $bin = Join-Path $HOME '.local\bin'
        $landed = Test-Path (Join-Path $bin 'hub-notebook-sync')
        Remove-Item (Join-Path $bin 'hub-notebook-sync') -Force -ErrorAction SilentlyContinue
        Install-KitHubTools -Hub $hub -ToolsRepo '' | Out-Null
        $landed -and
        (Test-Path (Join-Path $bin 'hub-notebook-sync')) -and
        (@(Get-Content (Join-Path $HOME '.hub\device.env') | Where-Object { $_ -match '^HUB_TOOLS_REPO=' }).Count -eq 1)
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $home0
    }
}
Check "the standalone join offers the notebook connection" {
    # Until 2026-08-18 only setup-hub.ps1 called the connect step: a joined second
    # machine got the runner installed and the credentials sitting in the folder,
    # and nothing introduced them.
    $joinText = Get-Content (Join-Path $PSScriptRoot '..\join.ps1') -Raw
    $joinText -match '(?m)^Connect-KitNotebook -Hub \$Hub'
}

Write-Host ""
Write-Host "-- the daily job that files what you type to an AI"
# Added 2026-08-10. The hub keeps a drawer of everything its owner has typed to an
# assistant, and filling it needs a job on each machine. Nothing installed that job:
# one computer had one because somebody typed it into that computer's schedule by
# hand, and every other computer quietly kept nothing. These are the Windows twins of
# the cases in test.sh. When you change one side, change both.
$TaskForTests = 'Hub prompt archive TEST'
# KB_HOME points every case here at a scratch home folder. Without it, a PC that
# already has the kit's programs under its real ~\.local\bin (the author's does)
# would take the installed-program branch in cases that are about the fallback,
# and "a hub with no harvester" would find a harvester after all.
Check "a hub with no harvester stays quiet" {
    try {
        $env:KB_HOME = New-TestDir 'noharvest-home'
        $bare = New-TestDir 'noharvest'
        $out = Install-KitPromptHarvest -Hub $bare -TaskName $TaskForTests 3>&1 4>&1 | Out-String
        ($out.Trim() -eq '') -and -not (Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue)
    } finally { $env:KB_HOME = $null }
}
Check "a hub with a harvester gets a job that runs it, and only once a day" {
    $hub = New-TestDir 'harvest'
    New-Item -ItemType Directory -Force (Join-Path $hub 'bin') | Out-Null
    Set-Content (Join-Path $hub 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest-home'
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        $args = if ($task) { ($task.Actions | ForEach-Object { $_.Arguments }) -join ' ' } else { '' }
        [bool]$task -and ($args -match 'prompt-harvest\.js') -and ($args -match '--once-a-day')
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "running the installer twice does not stack up two jobs" {
    $hub = New-TestDir 'harvest2'
    New-Item -ItemType Directory -Force (Join-Path $hub 'bin') | Out-Null
    Set-Content (Join-Path $hub 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest2-home'
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        @(Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue).Count -eq 1
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "a daily job for a hub that moved is re-pointed at this hub (D-179)" {
    $old = New-TestDir 'harvest-old'; $new = New-TestDir 'harvest-new'
    foreach ($h in $old, $new) {
        New-Item -ItemType Directory -Force (Join-Path $h 'bin') | Out-Null
        Set-Content (Join-Path $h 'bin\prompt-harvest.js') 'console.log(1)'
    }
    try {
        $env:KB_HOME = New-TestDir 'harvest-move-home'
        Install-KitPromptHarvest -Hub $old -TaskName $TaskForTests | Out-Null
        $out = Install-KitPromptHarvest -Hub $new -TaskName $TaskForTests 3>&1 4>&1 6>&1 | Out-String
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        [bool]$task -and ($task.Actions[0].WorkingDirectory -eq $new) -and ($task.Actions[0].Arguments -like "*`"$new`"*") -and
            ($out -like '*Re-pointing*') -and (@(Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue).Count -eq 1)
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "a daily job that already runs in this hub is left alone" {
    $hub = New-TestDir 'harvest-same'
    New-Item -ItemType Directory -Force (Join-Path $hub 'bin') | Out-Null
    Set-Content (Join-Path $hub 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest-same-home'
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        $out = Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests 3>&1 4>&1 6>&1 | Out-String
        $out -like '*already scheduled*'
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "device.env is re-pointed when HUB_DIR names another folder (D-179)" {
    try {
        $env:KB_HOME = New-TestDir 'devenv-home'
        New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.hub') | Out-Null
        Set-Content (Join-Path $env:KB_HOME '.hub\device.env') "HUB_DIR=C:\gone\hub`nHUB_PROMPT_SOURCES=claude"
        $hub = New-TestDir 'devenv-hub'
        Set-KitHubDirRecord -Hub $hub | Out-Null
        $lines = @(Get-Content (Join-Path $env:KB_HOME '.hub\device.env'))
        ($lines -contains "HUB_DIR=$hub") -and ($lines -contains 'HUB_PROMPT_SOURCES=claude') -and
            (@($lines | Where-Object { $_ -like 'HUB_DIR=*' }).Count -eq 1)
    } finally { $env:KB_HOME = $null }
}
Check "device.env that already names this hub is left exactly as it was" {
    try {
        $env:KB_HOME = New-TestDir 'devenv-home2'
        $hub = New-TestDir 'devenv-hub2'
        New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.hub') | Out-Null
        Set-Content (Join-Path $env:KB_HOME '.hub\device.env') "HUB_DIR=$hub"
        $before = Get-Content (Join-Path $env:KB_HOME '.hub\device.env') -Raw
        Set-KitHubDirRecord -Hub $hub | Out-Null
        (Get-Content (Join-Path $env:KB_HOME '.hub\device.env') -Raw) -eq $before
    } finally { $env:KB_HOME = $null }
}
Check "THE REGRESSION: the program installed under .local\bin is found and scheduled" {
    # This exact branch was dead on every reader's PC: the path carried a literal
    # BACKSPACE byte (".local<0x08>in"), so the installed program was never found
    # and the function returned without registering anything. The suite never saw
    # it because every case above hand-creates the hub-copy fallback instead. This
    # case builds the REAL layout: the program under <home>\.local\bin and a hub
    # that ships no copy of its own.
    $hub = New-TestDir 'harvest3'
    try {
        $env:KB_HOME = New-TestDir 'harvest3-home'
        $bin = Join-Path $env:KB_HOME '.local\bin'
        New-Item -ItemType Directory -Force $bin | Out-Null
        Set-Content (Join-Path $bin 'prompt-harvest.js') 'console.log(1)'
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        $args = if ($task) { ($task.Actions | ForEach-Object { $_.Arguments }) -join ' ' } else { '' }
        [bool]$task -and ($args -match '\.local\\bin\\prompt-harvest\.js')
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}


Write-Host ""
Write-Host "-- your notebook: connecting it once, and the connection travelling"
# Added 2026-08-16. The installer had no credential step at all before this, and a
# reader-facing step with no test is how the invisible backspace byte survived. These
# are the Windows twins of the cases in test.sh. When you change one, change both.
# Every one runs with a SCRATCH home, so the suite never reads or writes the real one.
$NotebookTask = 'Hub notebook sync TEST'
function Invoke-NotebookCase([scriptblock]$Body) {
    $home0 = $HOME; $envHome0 = $env:HOME; $keyEnv0 = $env:HUB_AGE_KEY
    try {
        $h = New-TestDir ('nb-home-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $env:HOME = $h
        $env:KB_HOME = $h
        Set-Variable -Name HOME -Value $h -Scope Global -Force
        New-Item -ItemType Directory -Force (Join-Path $h '.hub') | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $h '.local\bin') | Out-Null
        & $Body $h
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $envHome0
        $env:KB_HOME = $null
        $env:HUB_AGE_KEY = $keyEnv0
    }
}
function New-NotebookHub([string]$Name) {
    $hub = New-TestDir $Name
    New-Item -ItemType Directory -Force (Join-Path $hub 'secrets') | Out-Null
    return $hub
}

Check "a hub with no notebook reports 'none'" {
    Invoke-NotebookCase { param($h) (Get-KitNotebookState -Hub (New-NotebookHub 'nb1')) -eq 'none' }
}
Check "a folder carrying a sealed key reports 'sealed'" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb2'
        Set-Content (Join-Path $hub 'secrets\hub-key.age') 'x'
        (Get-KitNotebookState -Hub $hub) -eq 'sealed'
    }
}
Check "unsealing does nothing when the folder carries no key" {
    Invoke-NotebookCase { param($h) (Unlock-KitHubKey -Hub (New-NotebookHub 'nb3')) -eq $false }
}
Check "sealing does nothing when this PC has no key" {
    Invoke-NotebookCase { param($h) (Protect-KitHubKey -Hub (New-NotebookHub 'nb4')) -eq $false }
}
Check "unsealing is a no-op when this PC already has a key" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb5'
        Set-Content (Join-Path $hub 'secrets\hub-key.age') 'x'
        Set-Content (Join-Path $h '.hub\age-key.txt') 'k'
        (Unlock-KitHubKey -Hub $hub) -eq $true
    }
}

Check "Claude Code is given an .mcp.json, and it is valid JSON" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb6'
        Write-KitMcpConfig -Hub $hub | Out-Null
        $f = Join-Path $hub '.mcp.json'
        (Test-Path $f) -and ((Get-Content $f -Raw | ConvertFrom-Json).mcpServers.menerio.url -eq 'https://mcp.menerio.com')
    }
}
# Not "the assistant": Hermes never reads a folder .mcp.json, checked in its source. A
# kit that says otherwise is telling a reader their hub carries configuration it does
# not carry, which is the exact shape of the workspace line this batch already removed.
Check "the file says plainly that Hermes does not read it, and names what does tell Hermes" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb6b'
        $out = (Write-KitMcpConfig -Hub $hub 3>&1 6>&1 | Out-String)
        $j = Get-Content (Join-Path $hub '.mcp.json') -Raw
        $j.Contains('Hermes does not read it') -and $j.Contains('hermes mcp add') -and
            -not $j.Contains('tells your assistant') -and
            $out.Contains('for Claude Code') -and $out.Contains('Hermes does not read that file')
    }
}
Check "the connection NAMES the credential rather than carrying one" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb7'
        Write-KitMcpConfig -Hub $hub | Out-Null
        $auth = (Get-Content (Join-Path $hub '.mcp.json') -Raw | ConvertFrom-Json).mcpServers.menerio.headers.Authorization
        $auth -eq 'Bearer ${MENERIO_API_KEY}'
    }
}
Check "a reader's own .mcp.json is never overwritten" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb8'
        Set-Content (Join-Path $hub '.mcp.json') 'mine'
        Write-KitMcpConfig -Hub $hub | Out-Null
        (Get-Content (Join-Path $hub '.mcp.json') -Raw).Trim() -eq 'mine'
    }
}

# WHEN A KEY RUNS OUT: the record beside the keys. The Windows twin of the same block in
# test.sh. A key is a thing with a lifespan, and the day it dies nothing announces it.
Check "a hub with no record gets one, and it explains its own columns" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nbx1'
        Write-KitExpiryRecord -Hub $hub | Out-Null
        $f = Join-Path $hub 'secrets\expires.txt'
        $raw = if (Test-Path $f) { Get-Content $f -Raw } else { '' }
        (Test-Path $f) -and $raw.Contains('the page you get a new one from') -and
            $raw.Contains('NEVER PUT A KEY ITSELF IN HERE')
    }
}
Check "the record holds no key of its own: every line in it is a comment" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nbx2'
        Write-KitExpiryRecord -Hub $hub | Out-Null
        $live = @(Get-Content (Join-Path $hub 'secrets\expires.txt') |
                  Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') })
        $live.Count -eq 0
    }
}
Check "running the installer again never touches what the reader wrote in it" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nbx3'
        Write-KitExpiryRecord -Hub $hub | Out-Null
        $f = Join-Path $hub 'secrets\expires.txt'
        Add-Content $f 'MY_KEY  2027-01-01  https://example.com  # mine'
        Write-KitExpiryRecord -Hub $hub | Out-Null
        @(Get-Content $f | Where-Object { $_ -like 'MY_KEY*' }).Count -eq 1
    }
}

Check "no sync program on this PC means nothing is scheduled and nothing is said" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb9'
        $out = Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask 3>&1 4>&1 | Out-String
        ($out.Trim() -eq '') -and -not (Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue)
    }
}
Check "a change that is saved updates the notebook, and the hook cannot fail the save" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb10'
        git -C $hub init -q
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            $hook = Join-Path $hub '.git\hooks\post-commit'
            $body = if (Test-Path $hook) { Get-Content $hook -Raw } else { '' }
            $body.Contains('hub-notebook-sync') -and $body.Contains('exit 0') -and -not $body.Contains('\')
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "running the installer twice does not stack up two hourly jobs" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb11'
        git -C $hub init -q
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            @(Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue).Count -le 1
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "an hourly job for a hub that moved is re-pointed at this hub (D-179)" {
    Invoke-NotebookCase {
        param($h)
        $old = New-NotebookHub 'nb-old'; $new = New-NotebookHub 'nb-new'
        git -C $old init -q; git -C $new init -q
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            Install-KitNotebookSync -Hub $old -TaskName $NotebookTask | Out-Null
            Install-KitNotebookSync -Hub $new -TaskName $NotebookTask | Out-Null
            $task = Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue
            [bool]$task -and ($task.Actions[0].WorkingDirectory -eq $new) -and
                (@(Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue).Count -eq 1)
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "the hourly job never opens a terminal window at the reader" {
    # A scheduled task whose own program is bash.exe opens a console window every time
    # it fires. The prompt archive step learned that on 2026-08-18 and went through
    # wscript; this step was written afterwards and did not, so between then and
    # 2026-08-21 every Windows reader got a window flashing at :37 past every hour.
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb14'
        git -C $hub init -q
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            if (-not (Get-KitGitBash)) { return $true }  # nothing to schedule without Git Bash
            $t = Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue
            ($null -ne $t) -and ($t.Actions[0].Execute -match 'wscript') -and
                (Test-Path (Join-Path $h '.local\bin\run-hidden.vbs'))
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "an hourly job from before that fix is replaced, not left flashing" {
    # The readers who already installed are the ones who cannot fix it themselves.
    # Re-running the installer has to take the window away.
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb15'
        git -C $hub init -q
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            $bash = Get-KitGitBash
            if (-not $bash) { return $true }
            Register-ScheduledTask -TaskName $NotebookTask -Force `
                -Action (New-ScheduledTaskAction -Execute $bash -Argument '-lc "exit 0"') `
                -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(1)) | Out-Null
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            $t = Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue
            ($null -ne $t) -and ($t.Actions[0].Execute -match 'wscript')
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "a hook the reader wrote themselves is left exactly as it was" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb12'
        git -C $hub init -q
        New-Item -ItemType Directory -Force (Join-Path $hub '.git\hooks') | Out-Null
        Set-Content (Join-Path $hub '.git\hooks\post-commit') "#!/bin/sh`n# someone elses hook"
        Set-Content (Join-Path $h '.local\bin\hub-notebook-sync') "#!/bin/sh`nexit 0"
        try {
            Install-KitNotebookSync -Hub $hub -TaskName $NotebookTask | Out-Null
            (Get-Content (Join-Path $hub '.git\hooks\post-commit') -Raw).Contains('someone elses hook')
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "a reader who says no is not asked again and nothing is written" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb13'
        $env:KB_NOTEBOOK = 'skip'
        try {
            $out = Connect-KitNotebook -Hub $hub 3>&1 4>&1 | Out-String
            ($out.Trim() -eq '') -and -not (Test-Path (Join-Path $hub '.mcp.json'))
        } finally { $env:KB_NOTEBOOK = $null }
    }
}

# The real lock-and-unlock, where age is installed. It is the mechanism the whole
# promise rests on, so it is proven rather than assumed - and skipped OUT LOUD
# where it cannot be. `age -p` needs a real terminal by design, so the passphrase
# half is proven separately; what runs here is everything either side of it.
if ((Get-Command age -ErrorAction SilentlyContinue) -and (Get-Command age-keygen -ErrorAction SilentlyContinue)) {
    Check "pasting a token makes a key and locks the token inside the folder" {
        Invoke-NotebookCase {
            param($h)
            $hub = New-NotebookHub 'nb14'
            $env:HUB_AGE_KEY = Join-Path $h '.hub\age-key.txt'
            (Save-KitNotebookToken -Hub $hub -Token 'test-token-not-a-real-one-0123456789') -and
            (Test-Path (Join-Path $hub 'secrets\hub-secrets.env.age')) -and
            (Get-KitNotebookState -Hub $hub) -eq 'connected'
        }
    }
    Check "the key reads back exactly as it was pasted, once, because one key does both jobs" {
        Invoke-NotebookCase {
            param($h)
            $hub = New-NotebookHub 'nb15'
            $env:HUB_AGE_KEY = Join-Path $h '.hub\age-key.txt'
            [void](Save-KitNotebookToken -Hub $hub -Token 'test-token-not-a-real-one-0123456789')
            $lines = @(& age -d -i $env:HUB_AGE_KEY (Join-Path $hub 'secrets\hub-secrets.env.age'))
            ($lines -contains 'MENERIO_API_KEY=test-token-not-a-real-one-0123456789') -and
            (@($lines | Where-Object { $_ -like 'MENERIO_*' }).Count -eq 1)
        }
    }
    Check "connecting again replaces the credential instead of keeping two" {
        Invoke-NotebookCase {
            param($h)
            $hub = New-NotebookHub 'nb16'
            $env:HUB_AGE_KEY = Join-Path $h '.hub\age-key.txt'
            [void](Save-KitNotebookToken -Hub $hub -Token 'first-token-not-real-0123456789')
            [void](Save-KitNotebookToken -Hub $hub -Token 'second-token-not-real-98765432')
            $lines = @(& age -d -i $env:HUB_AGE_KEY (Join-Path $hub 'secrets\hub-secrets.env.age'))
            (@($lines | Where-Object { $_ -like 'MENERIO_API_KEY=*' }).Count -eq 1) -and
            ($lines -contains 'MENERIO_API_KEY=second-token-not-real-98765432')
        }
    }
    Check "a folder this PC cannot open reports 'locked-out', and is never rewritten" {
        # THE CASE THAT ALMOST DESTROYED A REAL HUB. A folder carrying credentials this
        # computer cannot open must be REFUSED, never rewritten: re-locking it to this
        # machine's key shuts every other computer out of every credential at once,
        # silently. It happened on 2026-08-16, to a live hub, during a test run.
        Invoke-NotebookCase {
            param($h)
            $hub = New-NotebookHub 'nb18'
            $other = Join-Path $h 'other-key.txt'
            & age-keygen -o $other 2>$null | Out-Null
            $recip = (& age-keygen -y $other | Select-Object -First 1)
            $plain = Join-Path $h 'plain.txt'
            Set-KbTextFile -Path $plain -Lines @('MENERIO_API_KEY=belongs-to-someone-else-0123456789')
            & age -r $recip -o (Join-Path $hub 'secrets\hub-secrets.env.age') $plain
            $env:HUB_AGE_KEY = Join-Path $h '.hub\age-key.txt'
            & age-keygen -o $env:HUB_AGE_KEY 2>$null | Out-Null
            $store = Join-Path $hub 'secrets\hub-secrets.env.age'
            $before = (Get-FileHash $store).Hash
            $state = Get-KitNotebookState -Hub $hub
            $refused = (Save-KitNotebookToken -Hub $hub -Token 'a-new-token-0123456789') -eq $false
            Connect-KitNotebook -Hub $hub 3>&1 4>&1 | Out-Null
            ($state -eq 'locked-out') -and $refused -and ((Get-FileHash $store).Hash -eq $before)
        }
    }
    Check "a key that does not open the folder's credentials is refused, not sealed" {
        Invoke-NotebookCase {
            param($h)
            $hub = New-NotebookHub 'nb17'
            $env:HUB_AGE_KEY = Join-Path $h '.hub\age-key.txt'
            [void](Save-KitNotebookToken -Hub $hub -Token 'a-token-not-real-0123456789')
            # A DIFFERENT key. age-keygen refuses to write over a file that is already
            # there, so without the removal the key never changes, the guard passes, and
            # this case walks straight into `age -p` and waits for a human forever. That
            # is exactly how the missing terminal guard was found on 2026-08-16.
            Remove-Item $env:HUB_AGE_KEY -Force -ErrorAction SilentlyContinue
            & age-keygen -o $env:HUB_AGE_KEY 2>$null | Out-Null
            $r = Protect-KitHubKey -Hub $hub
            ($r -eq $false) -and -not (Test-Path (Join-Path $hub 'secrets\hub-key.age'))
        }
    }
} else {
    Write-Host "  skip  the real lock-and-unlock cases (age is not on this PC: winget install --id FiloSottile.age)"
}

Write-Host ""
Write-Host "-- the installer's own files"
Check "setup-hub.ps1 parses"       { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'setup-hub.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "join.ps1 parses"            { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\join.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "build-installer.ps1 parses" { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-installer.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "no CODE uses utf8NoBOM, which PowerShell 5.1 has never heard of" {
    # Reads the parsed tokens rather than the raw text, because the comment that
    # explains why not to use it says the word too, and a test that cannot tell a
    # warning from the mistake it warns about is a test that cries wolf.
    $hits = 0
    foreach ($f in (Join-Path $PSScriptRoot '..\join.ps1'), (Join-Path $PSScriptRoot 'setup-hub.ps1')) {
        $tokens = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
        $hits += @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'utf8NoBOM' }).Count
    }
    $hits -eq 0
}
Check "the wizard asks the library where the hub is, rather than searching again" {
    Select-String -Path (Join-Path $PSScriptRoot 'hub-setup.iss') -Pattern 'Find-KitHub' -Quiet
}
Check "the wizard asks for no administrator rights of its own" {
    Select-String -Path (Join-Path $PSScriptRoot 'hub-setup.iss') -Pattern 'PrivilegesRequired=lowest' -Quiet
}
Check "the wizard asks the library which AI tools are here" {
    Select-String -Path (Join-Path $PSScriptRoot 'hub-setup.iss') -Pattern 'Find-KitAiTools' -Quiet
}
Check "the wizard hands the person's choice to the engine" {
    (Select-String -Path (Join-Path $PSScriptRoot 'hub-setup.iss') -Pattern 'GetPromptSources' -Quiet) -and
    (Select-String -Path (Join-Path $PSScriptRoot 'setup-hub.ps1') -Pattern 'PromptSources' -Quiet)
}
Check "no source file carries a stray control byte" {
    # The harvest task was dead on every reader's PC because one path carried a
    # literal backspace character - the corpse of a '\b' interpreted on its way
    # into the file. It rendered invisibly, so no eye and no text search could
    # see it. Bytes do not lie.
    $hits = 0
    foreach ($f in (Join-Path $PSScriptRoot '..\join.ps1'), (Join-Path $PSScriptRoot '..\lib.sh'),
                    (Join-Path $PSScriptRoot 'setup-hub.ps1'), (Join-Path $PSScriptRoot 'hub-setup.iss')) {
        foreach ($b in [System.IO.File]::ReadAllBytes($f)) {
            if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13) { $hits++ }
        }
    }
    $hits -eq 0
}


Write-Host ""
Write-Host "-- the things with a last day (due/), the twin of the same block in test.sh"

# A calendar reminder fires on a date and knows nothing else, so it goes off about something
# already done and a person stops reading reminders. This room is the other shape, and the
# installer has to deliver it to BOTH kinds of hub: a brand new one and one somebody has had
# for months.
Check "a hub with no due room gets one, and it teaches the window rather than a due date" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'due1'
        Write-KitDueFolder -Hub $hub | Out-Null
        $f = Join-Path $hub 'due\README.md'
        $raw = if (Test-Path $f) { Get-Content $f -Raw } else { '' }
        (Test-Path $f) -and
            $raw.Contains('the first day you can do the thing, and the last day you') -and
            $raw.Contains('No date, not eligible')
    }
}
Check "and it says a reader needs no calendar for any of it" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'due2'
        Write-KitDueFolder -Hub $hub | Out-Null
        (Get-Content (Join-Path $hub 'due\README.md') -Raw).Contains('You do not need a calendar')
    }
}
Check "running the installer again never touches a deadline the reader wrote" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'due3'
        Write-KitDueFolder -Hub $hub | Out-Null
        Set-Content (Join-Path $hub 'due\car-service.md') 'mine'
        Write-KitDueFolder -Hub $hub | Out-Null
        ((Get-Content (Join-Path $hub 'due\car-service.md') -Raw).Trim() -eq 'mine')
    }
}
Check "a brand new hub carries the due room from day one, not after an upgrade" {
    Invoke-NotebookCase {
        param($h)
        $hub = Join-Path (New-TestDir 'due4') 'hub'
        New-KitHub -Path $hub 3>&1 4>&1 6>&1 | Out-Null
        Test-Path (Join-Path $hub 'due\README.md')
    }
}
# THE TWO ROADS MUST LAY DOWN THE SAME WORDS. Compared line by line rather than byte for byte,
# because this side writes Windows line endings and the bash twin writes Unix ones: that is the
# one difference allowed, and comparing raw bytes would fail forever on a difference nobody can
# see or should care about. Every other difference is a typo fixed in one copy and not the other.
Check "the words are the same as the reader kit's own copy, line for line" {
    Invoke-NotebookCase {
        param($h)
        $kit = Join-Path $PSScriptRoot '..\..\teach-it-once-kit\starter-hub\due\README.md'
        if (-not (Test-Path $kit)) { Write-Host "        (the reader kit is not on this PC to compare with)"; return $true }
        $hub = New-NotebookHub 'due5'
        Write-KitDueFolder -Hub $hub | Out-Null
        $mine  = @(Get-Content (Join-Path $hub 'due\README.md'))
        $theirs = @(Get-Content $kit)
        if ($mine.Count -ne $theirs.Count) { Write-Host "        line counts differ: $($mine.Count) vs $($theirs.Count)"; return $false }
        for ($i = 0; $i -lt $mine.Count; $i++) {
            if ($mine[$i] -cne $theirs[$i]) { Write-Host "        line $($i+1) differs"; return $false }
        }
        return $true
    }
}

# AND THE SAME CHECK FOR THE KEY EXPIRY PAGE, which did not have one. There were THREE
# copies of that file and two had drifted: the bash twin and this one both predated the @
# convention that hub-check-keys implements, so a reader with an established hub was handed
# a page that did not document what their own tool was doing. Only the new-hub path, which
# copies from the kit, was current. The bash suite caught its copy; nothing watched this one.
Check "the expiry page matches the reader kit's own copy, line for line" {
    Invoke-NotebookCase {
        param($h)
        $kit = Join-Path $PSScriptRoot '..\..\teach-it-once-kit\starter-hub\secrets\expires.txt'
        if (-not (Test-Path $kit)) { Write-Host "        (the reader kit is not on this PC to compare with)"; return $true }
        $hub = New-NotebookHub 'exp1'
        Write-KitExpiryRecord -Hub $hub | Out-Null
        $mine   = @(Get-Content (Join-Path $hub 'secrets\expires.txt'))
        $theirs = @(Get-Content $kit)
        if ($mine.Count -ne $theirs.Count) { Write-Host "        line counts differ: $($mine.Count) vs $($theirs.Count)"; return $false }
        for ($i = 0; $i -lt $mine.Count; $i++) {
            if ($mine[$i] -cne $theirs[$i]) { Write-Host "        line $($i+1) differs"; return $false }
        }
        return $true
    }
}

Write-Host ""
Write-Host "-- one room, one name"
#
# THE BUG THESE EXIST FOR. Measured on a real existing hub during Run 2: the top-up found
# no profile\, so it copied the starter's in beside a context\ that already held the same
# four filenames. The next run then warned "you have both, delete the empty one" at a
# reader whose folders both had four files in them. The installer built the duplicate and
# then complained about it, and the complaint was not true either.

Check "a hub with context\ is told profile\ is the same room" {
    $d = New-TestDir 'twin1'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    (Get-KitRoomTwin -Hub $d -Name 'profile') -eq 'context'
}
Check "memory\ and observations\ are the same pair, asked either way round" {
    $d = New-TestDir 'twin2'
    New-Item -ItemType Directory -Force (Join-Path $d 'observations') | Out-Null
    ((Get-KitRoomTwin -Hub $d -Name 'memory') -eq 'observations') -and
        ((Get-KitRoomTwin -Hub $d -Name 'rules') -eq '')
}
Check "context\ becomes profile\ rather than gaining a sibling" {
    $d = New-TestDir 'rooms1'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Set-Content (Join-Path $d 'context\about-me.md') 'mine'
    Update-KitFolderNames -Hub $d 3>&1 6>&1 | Out-Null
    (Test-Path (Join-Path $d 'profile\about-me.md')) -and -not (Test-Path (Join-Path $d 'context'))
}
# THE LINE THAT MADE THE DUPLICATE. It used to be an unconditional New-Item.
Check "a hub that really has both keeps both, and is told what is in each" {
    $d = New-TestDir 'rooms2'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $d 'profile') | Out-Null
    Set-Content (Join-Path $d 'context\a.md') 'a'
    Set-Content (Join-Path $d 'profile\b.md') 'b'
    $out = (Update-KitFolderNames -Hub $d 3>&1 6>&1 | Out-String)
    (Test-Path (Join-Path $d 'context\a.md')) -and (Test-Path (Join-Path $d 'profile\b.md')) -and
        -not $out.Contains('delete the empty one') -and $out.Contains('1 inside') -and
        $out.Contains('your assistant reads profile')
}
Check "rules\ is made whatever else is going on" {
    $d = New-TestDir 'rooms3'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Update-KitFolderNames -Hub $d 3>&1 6>&1 | Out-Null
    (Test-Path (Join-Path $d 'rules')) -and -not (Test-Path (Join-Path $d 'context'))
}
Check "the top-up does NOT drop profile\ beside an existing context\" {
    $starter = New-TestDir 'rooms-starter'
    foreach ($r in 'profile', 'observations') {
        New-Item -ItemType Directory -Force (Join-Path $starter "starter-hub\$r") | Out-Null
    }
    Set-Content (Join-Path $starter 'starter-hub\profile\about-me.md') 'starter'
    Set-Content (Join-Path $starter 'starter-hub\observations\MEMORY.md') 'starter'
    Set-Content (Join-Path $starter 'starter-hub\AGENTS.md') 'starter'
    git -C $starter init -q 2>&1 | Out-Null
    git -C $starter add -A 2>&1 | Out-Null
    git -C $starter -c user.email='t@t' -c user.name='t' commit -q -m s 2>&1 | Out-Null

    $d = New-TestDir 'rooms4'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Set-Content (Join-Path $d 'context\about-me.md') 'mine'
    Copy-KitStarterHub -Path $d -StarterRepo $starter 3>&1 6>&1 | Out-Null
    $script:RoomsStarter = $starter
    -not (Test-Path (Join-Path $d 'profile')) -and
        ((Get-Content (Join-Path $d 'context\about-me.md') -Raw).Trim() -eq 'mine') -and
        (Test-Path (Join-Path $d 'AGENTS.md')) -and (Test-Path (Join-Path $d 'observations'))
}
Check "but a hub with neither name still gets profile\, or the guard went too far" {
    $d = New-TestDir 'rooms5'
    Copy-KitStarterHub -Path $d -StarterRepo $script:RoomsStarter 3>&1 6>&1 | Out-Null
    Test-Path (Join-Path $d 'profile')
}

Write-Host ""
Write-Host "-- a kit ships products, not its own test suite"
#
# Measured on a real install during Run 2: test-notebook-sync.sh and test-prompt-archive.sh
# were copied onto the reader's PATH beside hub-due and hub-check-keys.
Check "the products are installed and the kit's own tests are not" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'tools-kit'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        foreach ($f in 'due.js', 'check-keys.js', 'hub-notebook-sync', 'test-notebook-sync.sh',
                        'test-prompt-archive.sh', 'README.md') {
            Set-Content (Join-Path $kit "tools\$f") "// $f"
        }
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        Install-KitHubTools -Hub (New-NotebookHub 'tools-hub') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        $bin = Join-Path $h '.local\bin'
        $shipped = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'test-*' })
        if ($shipped) { Write-Host "        shipped to the reader: $($shipped.Name -join ', ')" }
        (Test-Path (Join-Path $bin 'due.js')) -and
            (Test-Path (Join-Path $bin 'hub-notebook-sync')) -and
            (Test-Path (Join-Path $bin 'hub-due.cmd')) -and
            -not (Test-Path (Join-Path $bin 'README.md')) -and
            $shipped.Count -eq 0
    }
}

Write-Host ""
Write-Host "-- a launcher for every command the book prints"

# Before 2026-08-29 only the prompt collector got a .cmd here, so on Windows hub-check-keys and
# hub-compile-rules were extension-less shell scripts nothing could run, while the book printed
# both as commands a reader types.
Check "every .js the book names as a command gets a .cmd launcher" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'launch-kit'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        foreach ($f in 'prompt-harvest.js', 'compile-rules.js', 'check-keys.js', 'due.js') {
            Set-Content (Join-Path $kit "tools\$f") "// $f"
        }
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        $hub = New-NotebookHub 'launch-hub'
        Install-KitHubTools -Hub $hub -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        $bin = Join-Path $h '.local\bin'
        $missing = @('hub-prompt-harvest', 'hub-compile-rules', 'hub-check-keys', 'hub-due') |
                   Where-Object { -not (Test-Path (Join-Path $bin ($_ + '.cmd'))) }
        if ($missing) { Write-Host "        no launcher for: $($missing -join ', ')" }
        $missing.Count -eq 0
    }
}
Check "a launcher runs the program beside it, not a path baked in at install time" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'launch-kit2'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        Set-Content (Join-Path $kit 'tools\due.js') '// due'
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        Install-KitHubTools -Hub (New-NotebookHub 'launch-hub2') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        (Get-Content (Join-Path $h '.local\bin\hub-due.cmd') -Raw).Contains('%~dp0due.js')
    }
}
Check "a kit that ships no due.js gets no hub-due, and says nothing about it" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'launch-kit3'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        Set-Content (Join-Path $kit 'tools\prompt-harvest.js') '// ph'
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        Install-KitHubTools -Hub (New-NotebookHub 'launch-hub3') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        -not (Test-Path (Join-Path $h '.local\bin\hub-due.cmd'))
    }
}

Write-Host ""
Write-Host "-- one skills room, and the installer proves it wired something"
#
# THE BUG THESE EXIST FOR. Until 2026-09-01 both installers junctioned .agents\skills to
# .claude\skills whenever .claude\skills existed. On a hub whose recipes live in the
# visible skills\ room, which is the arrangement the book teaches, the starter top-up had
# just created .claude\skills EMPTY, so every non-Claude assistant was pointed at an empty
# folder while six recipes sat unreachable, under a green tick. Measured on a real
# reader-shaped hub during Run 2, not imagined.
#
# EVERY CASE BELOW DRIVES HERMES THROUGH A STUB, and that is not tidiness. Hermes is on
# the author's own PATH. An early run of the bash twin, exercised from a scratch folder,
# wrote a temporary path into his live config because the function found the real hermes.
# KB_HERMES_BIN is the hook that makes that impossible from in here, and this block sets
# it before the first call that could reach outside.

function New-HermesStub {
    <#  A fake hermes that consumes ARGV, the way the real one does.

        The first version was pure cmd echoing %*, which is the RAW command line,
        quotes intact. The real hermes.exe never sees that line: it sees what
        CommandLineToArgvW makes of it, and measured against a real Hermes 0.20.6
        that is a different thing entirely - PowerShell 5.1's binder does NOT
        escape an embedded quote, so a JSON array passed with & arrived with
        every quote eaten and Hermes stored a STRING it then ignored. A stub
        reading the raw line agreed with the broken call for a whole session.

        So this stub is cmd handing %* to powershell -File, whose $args IS the
        argv view, and it behaves like the real thing: `config set` of a list
        value must arrive as valid JSON or it is stored as an inert string, and
        `config set` REPLACES the list. #>
    param([string]$Dir, [string]$Log, [string[]]$Configured = @())
    New-Item -ItemType Directory -Force $Dir | Out-Null
    Set-KbTextFile -Path (Join-Path $Dir 'stub.ps1') -Lines @(
        'if ($env:STUB_SK_LOG) { Add-Content -LiteralPath $env:STUB_SK_LOG -Value (@($args) -join " ") }',
        '$store = $env:STUB_SK_STORE',
        'if ($args[0] -eq "config" -and $args[1] -eq "get") {',
        '    if ($store -and (Test-Path -LiteralPath $store)) {',
        '        $raw = (Get-Content -LiteralPath $store -Raw).Trim()',
        '        # STUB_OLD_HERMES mimics 0.20.0, which echoes a stored string RAW.',
        '        if ($env:STUB_OLD_HERMES -eq "1") { $raw }',
        '        elseif ($raw.StartsWith("[")) { (ConvertFrom-Json $raw) | ForEach-Object { "- $_" } }',
        '        else { $raw }',
        '    }',
        '}',
        'if ($args[0] -eq "config" -and $args[1] -eq "set") {',
        '    $val = [string]$args[3]',
        '    # STUB_OLD_HERMES mimics 0.20.0, which stores the text verbatim, never a list.',
        '    if ($env:STUB_OLD_HERMES -ne "1") {',
        '        try { ConvertFrom-Json $val -ErrorAction Stop | Out-Null }',
        '        catch { $val = "STRING:" + $val }',
        '    }',
        '    if ($store) { [System.IO.File]::WriteAllText($store, $val) }',
        '}',
        'exit 0'
    )
    $stub = Join-Path $Dir 'hermes.cmd'
    # PowerShell by absolute path, for the reason in New-HermesCwdStub.
    Set-KbTextFile -Path $stub -Lines @(
        '@echo off',
        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stub.ps1" %*'
    )
    $env:STUB_SK_LOG   = $Log
    $env:STUB_SK_STORE = Join-Path $Dir 'external-dirs.json'
    if ($Configured.Count -gt 0) {
        [System.IO.File]::WriteAllText($env:STUB_SK_STORE,
            ('[' + (($Configured | ForEach-Object { ConvertTo-KbJsonString $_ }) -join ',') + ']'))
    } else {
        Remove-Item -LiteralPath $env:STUB_SK_STORE -Force -ErrorAction SilentlyContinue
    }
    Set-KbTextFile -Path $Log -Lines @()
    return $stub
}

function Add-Recipes {
    param([string]$Dir, [string[]]$Names)
    New-Item -ItemType Directory -Force $Dir | Out-Null
    foreach ($n in $Names) { Set-Content -LiteralPath (Join-Path $Dir "$n.md") -Value "# $n" }
}

function Get-RealSkillsFolders {
    <#  Every REAL folder named skills under $Root.

        Walked by hand rather than with -Recurse, and that is the Windows half of the
        lesson the bash twin learned with `find -L`. On Windows a junction IS a
        directory, so Get-ChildItem -Recurse walks straight through one and would count
        the very links this block creates as further rooms - hiding the exact thing the
        assertion exists to see. #>
    param([string]$Root, [int]$Depth = 4)
    if ($Depth -lt 0) { return @() }
    $found = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.LinkType) { continue }
        if ($d.Name -eq 'skills') { $found += $d.FullName }
        $found += @(Get-RealSkillsFolders -Root $d.FullName -Depth ($Depth - 1))
    }
    return $found
}

$SkRoot  = New-TestDir 'skills'
$SkLog   = Join-Path $SkRoot 'calls.log'
$Existing = 'C:\existing\team-skills'
$env:KB_HERMES_BIN = New-HermesStub -Dir (Join-Path $SkRoot 'bin') -Log $SkLog -Configured @($Existing)

foreach ($fn in 'ConvertTo-KbJsonString', 'Get-KitRealPath', 'Get-KitRecipeCount',
                 'Get-KitSkillsRoom', 'Set-KitRoomLink', 'Set-KitHermesSkillsDir',
                 'Connect-KitSkills') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}

Check "an empty folder holds no recipes" { (Get-KitRecipeCount (Join-Path $SkRoot 'nope')) -eq 0 }
Check "flat .md recipes are counted" {
    $d = Join-Path $SkRoot 'flat'; Add-Recipes $d @('a', 'b')
    (Get-KitRecipeCount $d) -eq 2
}
Check "a folder recipe with a SKILL.md counts" {
    $d = Join-Path $SkRoot 'nested'
    New-Item -ItemType Directory -Force (Join-Path $d 'deep') | Out-Null
    Set-Content (Join-Path $d 'deep\SKILL.md') '# deep'
    (Get-KitRecipeCount $d) -eq 1
}

# A Windows path is the reason the JSON has to be escaped at all: C:\hub\skills goes out
# as C:\\hub\\skills or Hermes reads a path full of escape sequences.
Check "a Windows path goes into the JSON with its backslashes doubled" {
    (ConvertTo-KbJsonString 'C:\hub\skills') -eq '"C:\\hub\\skills"'
}

# Which room is the real one. Detected, never assumed.
Check "the visible room wins when it holds the recipes" {
    $d = New-TestDir 'sk-visible'
    Add-Recipes (Join-Path $d 'skills') @('a')
    New-Item -ItemType Directory -Force (Join-Path $d '.claude\skills') | Out-Null
    (Get-KitSkillsRoom -Hub $d) -eq (Join-Path $d 'skills')
}
Check "a Claude-era hub keeps its recipes where they are" {
    $d = New-TestDir 'sk-claudeera'
    Add-Recipes (Join-Path $d '.claude\skills') @('a')
    (Get-KitSkillsRoom -Hub $d) -eq (Join-Path $d '.claude\skills')
}
Check "a brand new hub is given the visible room" {
    $d = New-TestDir 'sk-new'
    (Get-KitSkillsRoom -Hub $d) -eq (Join-Path $d 'skills')
}

# The merge. `hermes config set` REPLACES a list, so this is how a reader loses a team
# folder they added themselves.
Check "an entry already in external_dirs survives, and the hub's room is added after it" {
    Set-KbTextFile -Path $SkLog -Lines @()
    $script:SkMergeDir = New-TestDir 'sk-merge'
    Add-Recipes (Join-Path $script:SkMergeDir 'skills') @('a')
    Connect-KitSkills -Hub $script:SkMergeDir 3>&1 6>&1 | Out-Null
    # The log records argv, where the JSON still carries its doubled backslashes, so
    # the assertion reads the two escaped PATHS, which no amount of quoting changes.
    $log  = Get-Content -LiteralPath $SkLog -Raw
    $keep = $Existing.Replace('\', '\\')
    $room = (Get-KitRealPath (Join-Path $script:SkMergeDir 'skills')).Replace('\', '\\')
    ($log -like "*$keep*") -and ($log -like "*$room*") -and
        ($log.IndexOf($keep) -lt $log.IndexOf($room))
}
Check "the room's path survives the trip: stored as JSON, single backslashes" {
    # The stub stores what argv handed it, exactly as the real hermes.exe does.
    # Measured on a real Hermes 0.20.6: the & operator ate the JSON's quotes, the
    # value arrived as [C:\\...] and was stored with the doubled backslashes baked
    # in, so the read-back never matched and every run added the room again.
    $raw = (Get-Content -LiteralPath $env:STUB_SK_STORE -Raw).Trim()
    # Assignment first: @(ConvertFrom-Json ...) around the cmdlet call collects the
    # array as ONE nested element under 5.1 and -contains then matches nothing.
    $stored = ConvertFrom-Json $raw
    $raw.StartsWith('[') -and ($stored -contains (Get-KitRealPath (Join-Path $script:SkMergeDir 'skills')))
}
Check "and a second run does not add the room again" {
    Set-KbTextFile -Path $SkLog -Lines @()
    Connect-KitSkills -Hub $script:SkMergeDir 3>&1 6>&1 | Out-Null
    -not ((Get-Content -LiteralPath $SkLog -Raw) -like '*config set*')
}
# THE VERSION THAT STORES A LIST AS TEXT. Hermes 0.20.0 does not parse a JSON list
# on `config set`: it stores the whole text as one string, which its own readers
# then ignore, and `config get` echoes the string back RAW. Measured on the book's
# own rehearsal server. A string is not a list, and a success line over an inert
# setting is the workspace lie again.
Check "a raw string read back is no list entry at all" {
    try { $env:STUB_OLD_HERMES = '1'
          [System.IO.File]::WriteAllText($env:STUB_SK_STORE, '["C:\\existing\\team-skills"]')
          @(Get-KitHermesList -Key 'skills.external_dirs').Count -eq 0 }
    finally { $env:STUB_OLD_HERMES = $null }
}
Check "a Hermes that stores the room as text is told on, not celebrated" {
    try { $env:STUB_OLD_HERMES = '1'
          $d = New-TestDir 'sk-oldhermes'
          Add-Recipes (Join-Path $d 'skills') @('a')
          $txt = (Connect-KitSkills -Hub $d 3>&1 6>&1 | Out-String)
          $txt -like '*text it does not read*' }
    finally { $env:STUB_OLD_HERMES = $null }
}

# Never write when nothing needs writing.
Check "a room Hermes already reads is not written again" {
    $d = New-TestDir 'sk-noop'
    Add-Recipes (Join-Path $d 'skills') @('a')
    $log2 = Join-Path $SkRoot 'calls2.log'
    $env:KB_HERMES_BIN = New-HermesStub -Dir (Join-Path $SkRoot 'bin2') -Log $log2 `
                            -Configured @((Get-KitRealPath (Join-Path $d 'skills')))
    Connect-KitSkills -Hub $d 3>&1 6>&1 | Out-Null
    $r = -not ((Get-Content -LiteralPath $log2 -Raw) -like '*config set*')
    # Both halves of the first stub's state come back, or the cases above this
    # one leak into the cases below it.
    $env:KB_HERMES_BIN   = Join-Path $SkRoot 'bin\hermes.cmd'
    $env:STUB_SK_LOG     = $SkLog
    $env:STUB_SK_STORE   = Join-Path $SkRoot 'bin\external-dirs.json'
    $r
}
Check "a PC with no Hermes is told so, and nothing else breaks" {
    $d = New-TestDir 'sk-nohermes'
    Add-Recipes (Join-Path $d 'skills') @('a')
    $env:KB_HERMES_BIN = Join-Path $SkRoot 'bin\no-such-hermes.cmd'
    $r = Connect-KitSkills -Hub $d 3>&1 6>&1 | Select-Object -Last 1
    $env:KB_HERMES_BIN = Join-Path $SkRoot 'bin\hermes.cmd'
    ($r -eq $true) -and ((Get-KitRecipeCount (Join-Path $d '.claude\skills')) -eq 1)
}

# The exact shipped defect: recipes visible, .claude\skills empty. Unlike the bash suite,
# where Git Bash turns ln -s into a copy and the link cases can only run on Linux, a
# junction is real here, so every one of these runs on the platform it ships to.
Check "the empty placeholder becomes a junction, not a second room" {
    $script:SkD1 = New-TestDir 'sk-defect'
    Add-Recipes (Join-Path $script:SkD1 'skills') @('a', 'b', 'c', 'd', 'e', 'f')
    New-Item -ItemType Directory -Force (Join-Path $script:SkD1 '.claude\skills') | Out-Null
    Set-Content (Join-Path $script:SkD1 '.claude\skills\.gitkeep') ''
    Connect-KitSkills -Hub $script:SkD1 3>&1 6>&1 | Out-Null
    [bool](Get-Item -LiteralPath (Join-Path $script:SkD1 '.claude\skills') -Force).LinkType
}
Check "and it resolves to the room the reader can see" {
    (Get-KitRealPath (Join-Path $script:SkD1 '.claude\skills')) -eq
        (Get-KitRealPath (Join-Path $script:SkD1 'skills'))
}
Check "so Claude Code reaches all six recipes, which was the bug" {
    (Get-KitRecipeCount (Join-Path $script:SkD1 '.claude\skills')) -eq 6
}
Check "and so does everything that is not Claude Code" {
    (Get-KitRecipeCount (Join-Path $script:SkD1 '.agents\skills')) -eq 6
}
Check "exactly one real skills folder exists in the hub" {
    (@(Get-RealSkillsFolders -Root $script:SkD1)).Count -eq 1
}

# A hub whose recipes really do live in .claude\skills must not be fed to itself. Getting
# this wrong copies a folder into itself and then moves it aside.
Check "a Claude-era hub keeps its three recipes" {
    $script:SkD2 = New-TestDir 'sk-aj'
    Add-Recipes (Join-Path $script:SkD2 '.claude\skills') @('x', 'y', 'z')
    Connect-KitSkills -Hub $script:SkD2 3>&1 6>&1 | Out-Null
    (Get-KitRecipeCount (Join-Path $script:SkD2 '.claude\skills')) -eq 3
}
Check "and nothing was moved aside behind its back" {
    @(Get-ChildItem -LiteralPath (Join-Path $script:SkD2 '.claude') -Force -Filter '*.replaced-*' `
        -ErrorAction SilentlyContinue).Count -eq 0
}

# The old backwards junction, already on disk, must be repaired rather than trusted.
Check "before: the old junction reached nothing" {
    $script:SkD3 = New-TestDir 'sk-repair'
    Add-Recipes (Join-Path $script:SkD3 'skills') @('a', 'b', 'c', 'd', 'e', 'f')
    New-Item -ItemType Directory -Force (Join-Path $script:SkD3 '.claude\skills') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $script:SkD3 '.agents') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $script:SkD3 '.agents\skills') `
             -Target (Join-Path $script:SkD3 '.claude\skills') | Out-Null
    (Get-KitRecipeCount (Join-Path $script:SkD3 '.agents\skills')) -eq 0
}
Check "after: the same junction reaches every recipe" {
    Connect-KitSkills -Hub $script:SkD3 3>&1 6>&1 | Out-Null
    (Get-KitRecipeCount (Join-Path $script:SkD3 '.agents\skills')) -eq 6
}

# THE WINDOWS FOOTGUN, and it gets its own case. Remove-Item -Recurse on a junction walks
# through it and deletes what it points at, which is why Set-KitRoomLink calls .Delete()
# on the reparse point instead. If that ever regresses, a reader loses recipes rather than
# a link, so this proves the target is untouched.
Check "repointing a junction never touches what it pointed at" {
    $d = New-TestDir 'sk-safe'
    Add-Recipes (Join-Path $d 'skills') @('a', 'b', 'c')
    Add-Recipes (Join-Path $d 'elsewhere') @('keep1', 'keep2')
    New-Item -ItemType Directory -Force (Join-Path $d '.agents') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $d '.agents\skills') `
             -Target (Join-Path $d 'elsewhere') | Out-Null
    Connect-KitSkills -Hub $d 3>&1 6>&1 | Out-Null
    ((Get-KitRecipeCount (Join-Path $d 'elsewhere')) -eq 2) -and
        ((Get-KitRecipeCount (Join-Path $d '.agents\skills')) -eq 3)
}

# Twice equals once, or re-running the installer is a thing people fear.
Check "a second run changes nothing on disk" {
    $d = New-TestDir 'sk-twice'
    Add-Recipes (Join-Path $d 'skills') @('a')
    Connect-KitSkills -Hub $d 3>&1 6>&1 | Out-Null
    $before = (@(Get-ChildItem -LiteralPath $d -Recurse -Force -Name | Sort-Object) -join "`n")
    Connect-KitSkills -Hub $d 3>&1 6>&1 | Out-Null
    $after  = (@(Get-ChildItem -LiteralPath $d -Recurse -Force -Name | Sort-Object) -join "`n")
    $before -eq $after
}

# A real folder with real work standing where the link belongs is never deleted.
Check "a recipe found in the hidden folder is carried into the visible room" {
    $script:SkD5 = New-TestDir 'sk-carry'
    Add-Recipes (Join-Path $script:SkD5 'skills') @('mine')
    Add-Recipes (Join-Path $script:SkD5 '.claude\skills') @('theirs')
    Connect-KitSkills -Hub $script:SkD5 3>&1 6>&1 | Out-Null
    Test-Path -LiteralPath (Join-Path $script:SkD5 'skills\theirs.md')
}
Check "and the folder it came from is kept, not deleted" {
    @(Get-ChildItem -LiteralPath (Join-Path $script:SkD5 '.claude') -Force -Filter '*.replaced-*' `
        -ErrorAction SilentlyContinue).Count -eq 1
}

$env:KB_HERMES_BIN = $null
$env:STUB_SK_LOG   = $null
$env:STUB_SK_STORE = $null

Write-Host ""
Write-Host "-- where Hermes works, and proving it rather than reading the setting back"
#
# WHAT THESE GUARD. The kit shipped `hermes config set workspace "$HUB"`, which is not a
# recognised key: Hermes warned, the warning went to /dev/null, and the reader was told
# the workspace was set. Four of the six known ways to point Hermes at a folder are
# silent no-ops like that one, so v2 sets terminal.cwd and then PROVES the folder is
# readable by having Hermes read a file in it.
#
# The stub below is a faithful little Hermes rather than a yes-man. Its -z reads the
# marker file RELATIVE to whatever terminal.cwd says, which is exactly the behaviour
# measured on hardware, so STUB_MODE=ignore reproduces the half-connected failure and
# the check can be proved to catch it. A stub that always said yes would test nothing.

function New-HermesCwdStub {
    <#  A .cmd shim onto a PowerShell emulator, because the emulator has to be readable
        and cmd's own string handling is not. The shim is what gets called, so this is
        still an external program with a real exit code, which is what the code under
        test talks to. #>
    param([string]$Dir)
    New-Item -ItemType Directory -Force $Dir | Out-Null
    Set-KbTextFile -Path (Join-Path $Dir 'stub.ps1') -Lines @(
        '$log = $env:STUB_LOG',
        '# Each argument in its own brackets, so a prompt that arrived as sixteen',
        '# arguments instead of one is visible in the log rather than invisible.',
        'if ($log) { Add-Content -LiteralPath $log -Value ((@($args) | ForEach-Object { "[$_]" }) -join " ") }',
        '$mode = if ($env:STUB_MODE) { $env:STUB_MODE } else { "honour" }',
        'if ($args[0] -eq "auth" -and $args[1] -eq "list") {',
        '    if ($env:STUB_NO_CREDENTIAL -ne "1") { "openai-codex (1 credentials):" }',
        '}',
        'if ($args[0] -eq "config" -and $args[1] -eq "get" -and $args[2] -eq "terminal.cwd") {',
        '    if (Test-Path -LiteralPath $env:STUB_CWDFILE) { (Get-Content -LiteralPath $env:STUB_CWDFILE -Raw).Trim() } else { "." }',
        '}',
        'if ($args[0] -eq "config" -and $args[1] -eq "set" -and $args[2] -eq "terminal.cwd") {',
        '    [System.IO.File]::WriteAllText($env:STUB_CWDFILE, [string]$args[3])',
        '}',
        'if ($args[0] -eq "-z") {',
        '    if ($mode -eq "parrot") { [string]$args[1]; exit 0 }',
        '    # A one-shot that reached no model at all, and still exits 0. Measured.',
        '    if ($mode -eq "http400") { ''HTTP 400: {"detail":"The model is not supported when using Codex with a ChatGPT account."}''; exit 0 }',
        '    # Hermes 0.20.0 wording for the same condition. Measured on the rehearsal server.',
        '    if ($mode -eq "noprovider") { "hermes -z: agent failed: No inference provider configured. Run ''hermes model'' to choose a provider and model, or set an API key."; exit 0 }',
        '    if ($mode -eq "ignore") { $d = $env:STUB_ELSEWHERE }',
        '    elseif (Test-Path -LiteralPath $env:STUB_CWDFILE) { $d = (Get-Content -LiteralPath $env:STUB_CWDFILE -Raw).Trim() }',
        '    else { $d = "." }',
        '    $f = ""',
        '    if ([string]$args[1] -match "Read the file (\S+) in") { $f = $Matches[1] }',
        '    $p = Join-Path $d $f',
        '    if ($f -and (Test-Path -LiteralPath $p)) { Get-Content -LiteralPath $p -Raw } else { "File not found: $f" }',
        '}',
        'exit 0'
    )
    $cmd = Join-Path $Dir 'hermes.cmd'
    # PowerShell BY ABSOLUTE PATH, and it has to be. The Install-KitHubTools cases
    # further up rebuild this process's own PATH, and by the time these cases run
    # 'powershell' no longer resolves by name: the shim was reached, cmd could not find
    # its interpreter, and every assertion below turned red for a reason that had
    # nothing to do with the code under test.
    Set-KbTextFile -Path $cmd -Lines @(
        '@echo off',
        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stub.ps1" %*'
    )
    return $cmd
}

function Invoke-HubCase {
    <#  Run Set-KitHermesHub and hand back both halves: everything it said, and what it
        returned. The return value is last on the pipeline, after the prints. #>
    param([string]$Hub)
    $all = @(Set-KitHermesHub -Hub $Hub 3>&1 6>&1)
    $ret = $false
    if ($all.Count -gt 0) { $ret = $all[$all.Count - 1] }
    $txt = ((@($all) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    return [pscustomobject]@{ Text = $txt; Ok = ($ret -eq $true) }
}

$CwdRoot = New-TestDir 'hermescwd'
$env:STUB_LOG       = Join-Path $CwdRoot 'calls.log'
$env:STUB_CWDFILE   = Join-Path $CwdRoot 'terminal-cwd'
$env:STUB_ELSEWHERE = New-TestDir 'hermescwd-elsewhere'
$env:KB_HERMES_BIN  = New-HermesCwdStub -Dir (Join-Path $CwdRoot 'bin')
Set-KbTextFile -Path $env:STUB_LOG -Lines @()

foreach ($fn in 'Get-KitHermesBin', 'Test-KitHermesHere', 'Test-KitHermesCredential',
                 'ConvertFrom-KbYamlScalar', 'Get-KitHermesList',
                 'Invoke-KitHermesOneShot', 'Test-KitHermesReadsHub', 'Set-KitHermesHub') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}

$HubOk = New-TestDir 'hermescwd-hub'
$HubRes = Invoke-HubCase -Hub $HubOk

Check "terminal.cwd is set to the hub's absolute path" {
    (Get-Content -LiteralPath $env:STUB_CWDFILE -Raw).Trim() -eq (Get-KitRealPath $HubOk)
}
Check "and the whole thing succeeds when the folder is readable" { $HubRes.Ok }
Check "workspace is never set, because it is not a key" {
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]workspace[]]*')
}
# THE BUG THIS CAUGHT, and it was found by running the thing rather than reading it.
# Start-Process -ArgumentList joins an array with spaces and quotes nothing, so the
# prompt reached hermes.exe as sixteen arguments and -z got the word "Read".
Check "the prompt reaches Hermes as ONE argument, not one per word" {
    (Get-Content -LiteralPath $env:STUB_LOG -Raw) -like `
        '*[[]Read the file .hub-reachable-check in your current folder and reply with its contents and nothing else.[]]*'
}
Check "the proof asks for the file by a RELATIVE name, or it proves nothing" {
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]Read the file ?:\*')
}
Check "the marker file is not left behind in the reader's hub" {
    -not (Test-Path -LiteralPath (Join-Path $HubOk '.hub-reachable-check'))
}
Check "a second run does not set terminal.cwd again" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    Invoke-HubCase -Hub $HubOk | Out-Null
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]set[]] [[]terminal.cwd[]]*')
}

# THE CASE THAT MATTERS MOST. The setting reads back perfectly and the agent still
# cannot open the folder. Before this check that shipped as a green tick.
Check "an agent that ignores terminal.cwd is caught, not congratulated" {
    $env:STUB_MODE = 'ignore'
    $script:IgnoreRes = Invoke-HubCase -Hub (New-TestDir 'hermescwd-ignored')
    $env:STUB_MODE = ''
    -not $script:IgnoreRes.Ok
}
Check "and it is named as the half-connected shape rather than as a mystery" {
    $script:IgnoreRes.Text -like '*could not read a file*'
}
Check "and the reader is shown what Hermes answered, not left to guess" {
    # "Half connected" and "the model ignored the ask" look identical from the
    # outside; only the reply itself tells them apart. A real Windows e2e burned
    # a round trip on exactly this.
    $script:IgnoreRes.Text -like '*File not found: .hub-reachable-check*'
}

# A PROVIDER FAILURE IS NOT A FOLDER FAILURE, and telling a reader their hub is half
# connected because their model is misconfigured is the workspace lie pointed the other
# way. Found by running the installer on hardware: the test server's account default was a
# model its own subscription cannot serve, so every one-shot came back HTTP 400 and the
# installer blamed terminal.cwd.
Check "a one-shot that reached no model is unreachable, not a failed read" {
    $env:STUB_MODE = 'http400'
    $script:UnreachRes = Invoke-HubCase -Hub (New-TestDir 'hermescwd-nomodel')
    $r = Test-KitHermesReadsHub -Hub (New-TestDir 'hermescwd-nomodel2')
    $env:STUB_MODE = ''
    $r -eq 'unreachable'
}
Check "and that is not reported as a broken hub, but as a provider problem" {
    $script:UnreachRes.Ok -and
        ($script:UnreachRes.Text -like '*provider problem and not a folder problem*') -and
        ($script:UnreachRes.Text -like '*HTTP 400*') -and
        -not ($script:UnreachRes.Text -like '*could not read a file*')
}
Check "a missing inference provider is unreachable, not a broken folder" {
    # Hermes 0.20.0's wording for the same condition. A credential can be present
    # (a gh CLI token is auto-detected as one) while no model is configured, so
    # the credential gate passes and only this net catches it. Measured on the
    # book's own rehearsal server, where the miss called a wired hub broken.
    $env:STUB_MODE = 'noprovider'
    $r = Test-KitHermesReadsHub -Hub (New-TestDir 'hermescwd-noprov')
    $env:STUB_MODE = ''
    $r -eq 'unreachable'
}

# A parrot passes nothing. The token lives only in the file, never in the prompt, so an
# agent that echoes the prompt straight back cannot fake a read.
Check "an agent that only echoes the prompt back does not count as reading the file" {
    $env:STUB_MODE = 'parrot'
    $r = Test-KitHermesReadsHub -Hub (New-TestDir 'hermescwd-parrot')
    $env:STUB_MODE = ''
    $r -eq 'no'
}

# A first install, before the reader has signed in anywhere. Crying wolf here is how an
# installer teaches people to ignore it.
Check "no provider yet is not a failure, and the setting still lands" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    [System.IO.File]::Delete($env:STUB_CWDFILE)
    $env:STUB_NO_CREDENTIAL = '1'
    $r = Invoke-HubCase -Hub (New-TestDir 'hermescwd-nocred')
    $log = Get-Content -LiteralPath $env:STUB_LOG -Raw
    $env:STUB_NO_CREDENTIAL = ''
    $r.Ok -and ($log -like '*[[]set[]] [[]terminal.cwd[]]*') -and -not ($log -like '*[[]-z[]]*')
}
Check "a folder cannot be proved readable with no credential" {
    $env:STUB_NO_CREDENTIAL = '1'
    $r = Test-KitHermesReadsHub -Hub (New-TestDir 'hermescwd-nocred2')
    $env:STUB_NO_CREDENTIAL = ''
    $r -eq 'unavailable'
}

# The escape hatch, for the test matrix and for a reader on a metered plan.
Check "KB_SKIP_HUB_PROOF spends no request but still sets the folder" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    [System.IO.File]::Delete($env:STUB_CWDFILE)
    $env:KB_SKIP_HUB_PROOF = '1'
    $r = Invoke-HubCase -Hub (New-TestDir 'hermescwd-skip')
    $log = Get-Content -LiteralPath $env:STUB_LOG -Raw
    $env:KB_SKIP_HUB_PROOF = ''
    $r.Ok -and ($log -like '*[[]set[]] [[]terminal.cwd[]]*') -and -not ($log -like '*[[]-z[]]*')
}

Check "a folder that is not there is unavailable, not a failed read" {
    (Test-KitHermesReadsHub -Hub (Join-Path $CwdRoot 'no-such-hub')) -eq 'unavailable'
}
Check "no Hermes on the PC is not a failure, and it says so plainly" {
    $keep = $env:KB_HERMES_BIN
    $env:KB_HERMES_BIN = Join-Path $CwdRoot 'bin\no-such-hermes.cmd'
    $r = Invoke-HubCase -Hub $HubOk
    $env:KB_HERMES_BIN = $keep
    $r.Ok -and ($r.Text -like '*Hermes is not on this PC yet*')
}

foreach ($v in 'KB_HERMES_BIN', 'STUB_LOG', 'STUB_CWDFILE', 'STUB_ELSEWHERE', 'STUB_MODE',
                'STUB_NO_CREDENTIAL', 'KB_SKIP_HUB_PROOF') {
    Set-Item -Path "env:$v" -Value '' -ErrorAction SilentlyContinue
}


Write-Host ""
Write-Host "-- the leash, translated rather than renamed"
#
# The shape of these rules was measured on stock Hermes 0.21.0 before any of it was
# written, because an approvals.deny entry is a glob over the WHOLE normalised command
# and the obvious spelling stops nothing: "iptables" does not even deny `iptables -F`.
# The stub below does the same glob matching with -like, so a rule that would be inert
# on the real thing is inert here too.

function New-HermesApprovalsStub {
    param([string]$Dir)
    New-Item -ItemType Directory -Force $Dir | Out-Null
    Set-KbTextFile -Path (Join-Path $Dir 'stub.ps1') -Lines @(
        'if ($env:STUB_LOG) { Add-Content -LiteralPath $env:STUB_LOG -Value ((@($args) | ForEach-Object { "[$_]" }) -join " ") }',
        'function Get-Rules {',
        '    if (-not (Test-Path -LiteralPath $env:STUB_DENY)) { return @() }',
        '    $raw = (Get-Content -LiteralPath $env:STUB_DENY -Raw).Trim()',
        '    if (-not $raw -or $raw -eq "[]") { return @() }',
        '    # A value stored as a string is INERT, exactly as on the real thing:',
        '    # "most isinstance-gated readers will ignore a string here".',
        '    if ($raw.StartsWith("STRING:")) { return @() }',
        '    return @($raw.Trim("[","]") -split ''","'' | ForEach-Object { $_.Trim(''"'') } | Where-Object { $_ })',
        '}',
        'if ($args[0] -eq "config" -and $args[1] -eq "get" -and $args[2] -eq "approvals.deny") {',
        '    # STUB_OLD_HERMES mimics 0.20.0: whatever was stored comes back RAW.',
        '    if ($env:STUB_OLD_HERMES -eq "1") {',
        '        if ((Test-Path -LiteralPath $env:STUB_DENY) -and (Get-Content -LiteralPath $env:STUB_DENY -Raw).Trim()) {',
        '            (Get-Content -LiteralPath $env:STUB_DENY -Raw).Trim(); exit 0',
        '        }',
        '        "Config key not set: approvals.deny"; exit 1',
        '    }',
        '    if ((Test-Path -LiteralPath $env:STUB_DENY) -and (Get-Content -LiteralPath $env:STUB_DENY -Raw).Trim().StartsWith("STRING:")) {',
        '        # The real hermes prints the stored string back, no list dashes.',
        '        (Get-Content -LiteralPath $env:STUB_DENY -Raw).Trim().Substring(7); exit 0',
        '    }',
        '    $r = Get-Rules',
        '    if ($r.Count -eq 0) { "Config key not set: approvals.deny"; exit 1 }',
        '    # QUOTED, the way a real YAML writer hands them back. Every rule starts with',
        '    # a * , which YAML reads as an alias, so Hermes quotes all of them. The stub',
        '    # echoed them back bare, which is exactly why it missed the bug where a second',
        '    # run added all eighteen again with the quote characters baked in.',
        '    $r | ForEach-Object { "- " + [char]39 + $_.Replace([string][char]39, [string][char]39 + [char]39) + [char]39 }',
        '}',
        'if ($args[0] -eq "config" -and $args[1] -eq "set" -and $args[2] -eq "approvals.deny") {',
        '    # $args IS the argv view, which is what the real hermes.exe reads. An earlier',
        '    # version of this stub read cmd raw argument line instead, believing that',
        '    # "PowerShell escapes an inner quote for a native process". Measured against a',
        '    # real Hermes 0.20.6, it does NOT: the & operator ate every quote, hermes',
        '    # called the value invalid YAML/JSON and stored a STRING, and all eighteen',
        '    # rules shipped as decoration. The stub now does what the real thing does:',
        '    # valid JSON becomes the list, anything else is stored inert.',
        '    $val = [string]$args[3]',
        '    # STUB_OLD_HERMES mimics 0.20.0, which stores the text verbatim, never a list.',
        '    if ($env:STUB_OLD_HERMES -ne "1") {',
        '        try { ConvertFrom-Json $val -ErrorAction Stop | Out-Null }',
        '        catch { $val = "STRING:" + $val }',
        '    }',
        '    [System.IO.File]::WriteAllText($env:STUB_DENY, $val)',
        '}',
        'if ($args[0] -eq "approvals" -and $args[1] -eq "test") {',
        '    $rest = @($args[2..($args.Count-1)])',
        '    if ($rest.Count -gt 0 -and $rest[0] -eq "--") { $rest = @($rest[1..($rest.Count-1)]) }',
        '    $cmd = $rest -join " "',
        '    if ($env:STUB_TOOTIGHT -eq "1" -and $cmd -eq "git status") { exit 2 }',
        '    if ($env:STUB_TOOTIGHT -eq "2") { exit 0 }',
        '    foreach ($p in (Get-Rules)) { if ($cmd -like $p) { exit 3 } }',
        '    exit 0',
        '}',
        'exit 0'
    )
    $cmd = Join-Path $Dir 'hermes.cmd'
    # PowerShell by absolute path, for the reason in New-HermesCwdStub.
    Set-KbTextFile -Path $cmd -Lines @(
        '@echo off',
        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stub.ps1" %*'
    )
    return $cmd
}

function Invoke-ApprovalsCase {
    $all = @(Set-KitHermesApprovals 3>&1 6>&1)
    $ret = $false
    if ($all.Count -gt 0) { $ret = $all[$all.Count - 1] }
    $txt = ((@($all) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    return [pscustomobject]@{ Text = $txt; Ok = ($ret -eq $true) }
}

$ApRoot = New-TestDir 'approvals'
$env:STUB_LOG  = Join-Path $ApRoot 'calls.log'
$env:STUB_DENY = Join-Path $ApRoot 'deny.json'
$env:KB_HERMES_BIN = New-HermesApprovalsStub -Dir (Join-Path $ApRoot 'bin')
Set-KbTextFile -Path $env:STUB_LOG -Lines @()

foreach ($fn in 'Get-KitHermesDenyRules', 'Set-KitHermesApprovals', 'Test-KitHermesApprovals') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}

$ApRes = Invoke-ApprovalsCase
Check "the leash goes on, and says so" { $ApRes.Ok }
Check "every shipped rule reaches the config" {
    $d = Get-Content -LiteralPath $env:STUB_DENY -Raw
    @(Get-KitHermesDenyRules | Where-Object { -not $d.Contains($_) }).Count -eq 0
}
Check "the list ARRIVES at Hermes as real JSON, quotes and all" {
    # The stub stores what argv handed it, which is what the real hermes.exe reads.
    # Measured on a real Hermes 0.20.6: PowerShell 5.1's & operator ate every embedded
    # quote, the value arrived as [*shred *,...], Hermes called it invalid YAML/JSON
    # and stored a STRING, and all eighteen rules shipped as decoration.
    $d = Get-Content -LiteralPath $env:STUB_DENY -Raw
    (-not $d.StartsWith('STRING:')) -and $d.Contains('"*shred *"')
}
Check "the Unix rules are what ships, because this PC is what drives the server" {
    (Get-KitHermesDenyRules) -contains '*systemctl stop ssh*'
}
Check "approvals.mode is never written, because the shipped default is the right one" {
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*approvals.mode*')
}
Check "and no allowlist is written, because Hermes already allows the kit's own work" {
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*command_allowlist*')
}
Check "the check runs both ways, not just the scary one" {
    $ApRes.Text -like '*checked both ways*'
}
# THE BUG THE STUB USED TO HIDE. Hermes hands a rule starting with * back QUOTED, so a
# read that does not unquote sees eighteen rules it does not recognise and adds them all
# again, quote characters and all. Measured on hardware: the list reached thirty-six
# entries, half of them matching no command at all, after a single second run.
Check "a second run adds nothing, even though Hermes quotes every rule back" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    Invoke-ApprovalsCase | Out-Null
    (-not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]set[]] [[]approvals.deny[]]*')) -and
        (@(Get-KitHermesList -Key 'approvals.deny').Count -eq @(Get-KitHermesDenyRules).Count)
}
Check "and a quoted value is read back as the rule itself, not as a new one" {
    ((ConvertFrom-KbYamlScalar "'*shred *'") -eq '*shred *') -and
        ((ConvertFrom-KbYamlScalar "'''''*shred *'''''") -eq '*shred *') -and
        ((ConvertFrom-KbYamlScalar '*shred *') -eq '*shred *')
}
# `hermes config set` REPLACES a list, so without read, merge, write this is how a
# reader loses the rule they added themselves.
Check "a rule the reader added themselves survives, with the shipped ones beside it" {
    [System.IO.File]::WriteAllText($env:STUB_DENY, '["*my own rule*"]')
    Invoke-ApprovalsCase | Out-Null
    $d = Get-Content -LiteralPath $env:STUB_DENY -Raw
    $d.Contains('*my own rule*') -and $d.Contains('*ufw --force reset*')
}

# THE TWO WAYS THE SELF-CHECK EARNS ITS PLACE.
Check "rules that do not bite are reported, not celebrated" {
    [System.IO.File]::WriteAllText($env:STUB_DENY, '')
    $env:STUB_TOOTIGHT = '2'
    $script:ApLoose = Invoke-ApprovalsCase
    $env:STUB_TOOTIGHT = ''
    (-not $script:ApLoose.Ok) -and ($script:ApLoose.Text -like '*not biting*')
}
Check "rules that went too far are caught as well" {
    [System.IO.File]::WriteAllText($env:STUB_DENY, '')
    $env:STUB_TOOTIGHT = '1'
    $r = Invoke-ApprovalsCase
    $env:STUB_TOOTIGHT = ''
    (-not $r.Ok) -and ($r.Text -like '*went too far*')
}
Check "no Hermes is not a failure here either" {
    $keep = $env:KB_HERMES_BIN
    $env:KB_HERMES_BIN = Join-Path $ApRoot 'bin\no-such-hermes.cmd'
    $r = Invoke-ApprovalsCase
    $env:KB_HERMES_BIN = $keep
    $r.Ok -and ($r.Text -like '*no rules to give it*')
}
# THE VERSION THAT STORES THE LIST AS TEXT. Hermes 0.20.0 stores a JSON list as
# one plain string, its readers ignore a string, and before Get-KitHermesList
# learnt to filter, the raw echo fed the next merge and nested the whole list
# one level deeper on every run. Measured on the book's own rehearsal server.
Check "a Hermes that stores the rules as text is caught: the leash is NOT on" {
    try { $env:STUB_OLD_HERMES = '1'
          [System.IO.File]::WriteAllText($env:STUB_DENY, '')
          $script:ApOld = Invoke-ApprovalsCase
          (-not $script:ApOld.Ok) -and ($script:ApOld.Text -like '*NOT on*') }
    finally { $env:STUB_OLD_HERMES = $null }
}
Check "and a second run does not nest the list deeper" {
    try { $env:STUB_OLD_HERMES = '1'
          $s1 = (Get-Item -LiteralPath $env:STUB_DENY).Length
          Invoke-ApprovalsCase | Out-Null
          (Get-Item -LiteralPath $env:STUB_DENY).Length -eq $s1 }
    finally { $env:STUB_OLD_HERMES = $null
              [System.IO.File]::WriteAllText($env:STUB_DENY, '') }
}

# A healthy `hermes approvals test` answers 3, so the last thing join.ps1 does leaves 3
# in $LASTEXITCODE. Without an explicit exit, PowerShell hands that back and a completely
# successful join reports failure to whatever ran it.
Check "join.ps1 ends with an explicit exit, so a good run cannot report 3" {
    $tail = (Get-Content (Join-Path $PSScriptRoot '..\join.ps1') -Tail 1).Trim()
    $tail -eq 'exit 0'
}

foreach ($v in 'KB_HERMES_BIN', 'STUB_LOG', 'STUB_DENY', 'STUB_TOOTIGHT') {
    Set-Item -Path "env:$v" -Value '' -ErrorAction SilentlyContinue
}

# Put the real user PATH back, whatever the cases above did to it. See $UserPath0 at the top.
try { [Environment]::SetEnvironmentVariable('Path', $UserPath0, 'User') } catch { }

# --- WHERE A HUB MAY GO (D-179, 2026-09-02) -------------------------------------------
# Twins of the cases in test.sh. The default is the top of the user folder; the folders
# OneDrive backs up are refused with a sentence; C:\hub stays allowed as the power option.
foreach ($fn in 'Get-KitDefaultHubDir', 'Get-KitCloudSyncedParents', 'Get-KitHubPathRefusal') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}
Check "the default is the top of the user folder" {
    (Get-KitDefaultHubDir) -eq (Join-Path $HOME 'hub')
}
Check "the user folder itself is allowed" {
    $null -eq (Get-KitHubPathRefusal -Path (Join-Path $HOME 'hub'))
}
Check "the drive root stays allowed, as the power option" {
    $null -eq (Get-KitHubPathRefusal -Path 'C:\hub')
}
foreach ($k in 'MyDocuments', 'Desktop', 'MyPictures', 'MyMusic', 'MyVideos') {
    $base = [Environment]::GetFolderPath($k)
    if (-not $base) { continue }
    $p = Join-Path $base 'hub'
    Check "$k is refused ($p)" { [bool](Get-KitHubPathRefusal -Path $p) }.GetNewClosure()
}
Check "deeper inside Documents is still refused" {
    [bool](Get-KitHubPathRefusal -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'work\hub'))
}
Check "a folder merely named like one is allowed" {
    $null -eq (Get-KitHubPathRefusal -Path (Join-Path $HOME 'Documents-old\hub'))
}
Check "the refusal says where to go instead" {
    (Get-KitHubPathRefusal -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'hub')) -like "*$(Get-KitDefaultHubDir)*"
}
$od0 = $env:OneDrive
try {
    $env:OneDrive = New-TestDir 'onedrive-root'
    Check "a path typed straight into the OneDrive root is refused" {
        [bool](Get-KitHubPathRefusal -Path (Join-Path $env:OneDrive 'hub'))
    }
} finally { $env:OneDrive = $od0 }
Check "Find-KitHub looks in the user folder before the drive root" {
    $src = (Get-Command Find-KitHub).ScriptBlock.ToString()
    $src.IndexOf("(Join-Path `$HOME 'hub')") -lt $src.IndexOf("'C:\hub'")
}

Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($Fail -eq 0) {
    Write-Host "  $Pass passed, 0 failed" -ForegroundColor Green
    Write-Host ""
    Write-Host "ALL PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  $Pass passed, $Fail failed" -ForegroundColor Red
    exit 1
}
