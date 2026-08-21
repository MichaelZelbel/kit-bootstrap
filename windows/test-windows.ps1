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
                 'Set-KitPromptSources', 'Write-KitSyncReport', 'Get-KitHome') {
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
                    'procedures.md', 'decisions.md', 'observations\MEMORY.md', 'skills\plan-my-day.md') {
        if (-not (Test-Path (Join-Path $d $f))) { $missing += $f }
    }
    if ($missing.Count) { Write-Host "        missing: $($missing -join ', ')" }
    $missing.Count -eq 0
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
Check "the two programs land on the PC and a README does not" {
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
        -not (Test-Path (Join-Path $bin 'README.md')) -and
        # THE ONE THAT MATTERS: nothing was put inside the hub folder.
        (@(Get-ChildItem $hub -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -in 'hub-prompt-archive', 'prompt-harvest.js' }).Count -eq 0) -and
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

Check "the assistant is given an .mcp.json, and it is valid JSON" {
    Invoke-NotebookCase {
        param($h)
        $hub = New-NotebookHub 'nb6'
        Write-KitMcpConfig -Hub $hub | Out-Null
        $f = Join-Path $hub '.mcp.json'
        (Test-Path $f) -and ((Get-Content $f -Raw | ConvertFrom-Json).mcpServers.menerio.url -eq 'https://mcp.menerio.com')
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
