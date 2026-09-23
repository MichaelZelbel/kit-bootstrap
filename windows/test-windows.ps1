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
# never touches a real mission control.
# =============================================================================
$ErrorActionPreference = 'Continue'

$Pass = 0
$Fail = 0
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

# THE SUITE PUTS THE USER'S REAL PATH BACK WHEN IT FINISHES, AND IT HAS TO.
#
# Install-KitGodspeedTools prepends its bin folder to the PERSISTED user PATH, and skips doing so when
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

# AND THE SAME MISTAKE, ONE FLOOR DOWN: THE SUITE HAD NO HOME OF ITS OWN.
#
# The header above says this file "never touches a real mission control". It did. Found on 2026-09-03 by
# `mission control demo status`, which reported that the GODSPEED_DIR line in the real ~\.godspeed\device.env and the
# real GODSPEED_DIR user variable both named a kb-test-* temporary folder that no longer existed. The
# daily jobs read that line to find the mission control, so the suite had quietly pointed them at nothing.
#
# The case that did it is "no kit named means nothing installed and nothing said". Passing
# -ToolsRepo '' does not mean "do nothing": Install-KitGodspeedTools then reads the recorded
# GODSPEED_TOOLS_REPO out of device.env and uses that, which is deliberate (a join does not retype the
# product). On a machine with no recorded kit, as in CI, the case is honest. On the author's own
# machine it ran a full install against a temporary mission control, wrote the real device.env, and still
# passed, because its assertion captured streams 3 and 4 while Write-KbOk speaks on 6.
#
# Faking KB_HOME per case was never enough either: most cases end with `$env:KB_HOME = $null`, so
# the case after each of them saw the real home again. $HOME is what Get-KitHome falls back to and
# what join.ps1 uses directly in a dozen places, so $HOME is what has to be false for the whole
# run. Individual cases still fake their own on top of this; they now fall back to a fake.
$Home0    = $HOME
$EnvHome0 = $env:HOME
$KbHome0  = $env:KB_HOME
$GodspeedDir0  = [Environment]::GetEnvironmentVariable('GODSPEED_DIR', 'User')
$SuiteHome = Join-Path $Root 'suite-home'
New-Item -ItemType Directory -Force (Join-Path $SuiteHome '.godspeed') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $SuiteHome '.local\bin') | Out-Null
$env:HOME = $SuiteHome
$env:KB_HOME = $SuiteHome
Set-Variable -Name HOME -Value $SuiteHome -Scope Global -Force

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

function New-SourceGodspeed {
    <# A committed git repo that looks like a mission control, to clone from. #>
    param([string]$Path)
    New-Item -ItemType Directory -Force $Path | Out-Null
    git -C $Path init -q
    Set-Content (Join-Path $Path 'AGENTS.md') '# source mission control'
    New-Item -ItemType Directory -Force (Join-Path $Path 'observations') | Out-Null
    Set-Content (Join-Path $Path 'observations\MEMORY.md') '# What I remember'
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path -c user.email='t@t' -c user.name='t' commit -q -m 'godspeed' 2>&1 | Out-Null
}

Write-Host ""
Write-Host "PowerShell $($PSVersionTable.PSVersion) - $($PSVersionTable.PSEdition)" -ForegroundColor Cyan
Write-Host "scratch: $Root"
Write-Host ""

New-Item -ItemType Directory -Force $Root | Out-Null
. (Join-Path $PSScriptRoot '..\join.ps1') -AsLibrary

Write-Host "-- the library loads and offers what the installer calls"
foreach ($fn in 'Find-KitGodspeed', 'Test-KitGodspeed', 'Update-KitGodspeed', 'Join-KitMemory', 'Install-KitGodspeedCli',
                 'Install-KitPrereqs', 'New-KitGodspeed', 'Update-KitPath', 'Set-KbTextFile', 'Test-KitCommand',
                 'Install-KitPromptHarvest', 'Install-KitGodspeedTools',
                 'Test-KitAiTool', 'Get-KitAiToolInfo', 'Find-KitAiTools', 'Get-KitEnabledSources',
                 'Get-KitNotebookState', 'Unlock-KitGodspeedKey', 'Protect-KitGodspeedKey',
                 'Save-KitNotebookToken', 'Write-KitMcpConfig', 'Install-KitNotebookSync',
                 'Set-KitNotebookEnv', 'Connect-KitNotebook', 'Test-KitInteractive',
                 'Install-KitAge', 'Connect-KitAssistants', 'Connect-KitMenerioOnly',
                 'Set-KitDeviceEnvValue', 'Get-KitNotebookMirror', 'Test-KitNotebookRunnerAsks',
                 'Test-KitNotebookJobHere', 'Select-KitNotebookMirror', 'Request-KitPassphrase',
                 'Set-KitPromptSources', 'Write-KitSyncReport', 'Get-KitHome',
                 'Write-KitExpiryRecord', 'Write-KitDueFolder', 'Get-KitRoomTwin',
                 'Connect-KitMail', 'Write-KitMailNote',
                 'Request-KitGmail', 'Show-KitGmailRetired', 'Connect-KitGmailOnly') {
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
Write-Host "-- telling a mission control from a folder that merely looks like one"
Check "a folder that does not exist is not a mission control"      { -not (Test-KitGodspeed (Join-Path $Root 'ghost')) }
Check "an empty folder is not a mission control"                   { -not (Test-KitGodspeed (New-TestDir 'empty')) }
Check "a git folder with no mission control files is not a mission control"    {
    $d = New-TestDir 'bare'; git -C $d init -q; -not (Test-KitGodspeed $d)
}
Check "a git folder with memory/ IS a mission control"             {
    $d = New-TestDir 'real'; git -C $d init -q
    New-Item -ItemType Directory -Force (Join-Path $d 'memory') | Out-Null
    Test-KitGodspeed $d
}
Check "a hint pointing at a real mission control is used"          {
    $d = New-TestDir 'hinted'; git -C $d init -q; Set-Content (Join-Path $d 'AGENTS.md') 'x'
    (Find-KitGodspeed -Hint $d) -eq (Resolve-Path $d).Path
}
Check "a hint pointing at rubbish is not trusted"      {
    (Find-KitGodspeed -Hint (Join-Path $Root 'ghost')) -ne (Join-Path $Root 'ghost')
}

Write-Host ""
Write-Host "-- making a mission control when the PC has none"
Check "a fresh mission control is created and recognised" {
    $d = Join-Path $Root 'fresh'
    New-KitGodspeed -Path $d | Out-Null
    (Test-KitGodspeed $d) -and (Test-Path (Join-Path $d 'AGENTS.md')) -and (Test-Path (Join-Path $d 'observations\MEMORY.md'))
}
Check "making one twice is safe and keeps what is there" {
    $d = Join-Path $Root 'fresh'
    Set-Content (Join-Path $d 'AGENTS.md') '# mine, edited'
    New-KitGodspeed -Path $d | Out-Null
    (Get-Content (Join-Path $d 'AGENTS.md') -Raw).Contains('mine, edited')
}
Check "a folder with somebody else's files in it is refused" {
    $d = New-TestDir 'occupied'; Set-Content (Join-Path $d 'holiday.jpg') 'x'
    try { New-KitGodspeed -Path $d | Out-Null; $false } catch { $true }
}
Check "an existing mission control is cloned from its repository" {
    $src = Join-Path $Root 'src'; New-SourceGodspeed -Path $src
    $dst = Join-Path $Root 'cloned'
    New-KitGodspeed -Path $dst -RepoUrl $src | Out-Null
    (Test-KitGodspeed $dst) -and (Test-Path (Join-Path $dst 'AGENTS.md'))
}
Check "an address that is not a repository is refused, not half-done" {
    try { New-KitGodspeed -Path (Join-Path $Root 'bad') -RepoUrl (Join-Path $Root 'ghost') | Out-Null; $false }
    catch { $_.Exception.Message -like '*Could not copy that repository*' }
}

Write-Host ""
Write-Host "-- a new mission control copies the product's starter folder, it never invents one"
Check "the starter folder's files are laid down" {
    # A local fixture, so this case does not need the network to mean anything.
    $sr = Join-Path $Root 'starter-src'
    # Deliberately the OLD name: a starter from before the rename must come out renamed,
    # which is what a reader who downloaded the kit months ago actually has.
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-godspeed\context') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-godspeed\skills') | Out-Null
    Set-Content (Join-Path $sr 'starter-godspeed\AGENTS.md') '# the real one'
    Set-Content (Join-Path $sr 'starter-godspeed\context\about-me.md') 'about'
    Set-Content (Join-Path $sr 'starter-godspeed\skills\plan-my-day.md') 'plan'
    git -C $sr init -q
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'starter' 2>&1 | Out-Null

    $d = Join-Path $Root 'fromstarter'
    New-KitGodspeed -Path $d -StarterRepo $sr | Out-Null
    (Test-Path (Join-Path $d 'profile\about-me.md')) -and (Test-Path (Join-Path $d 'skills\plan-my-day.md'))
}
Check "the starter's own AGENTS.md wins, no invented one overwrites it" {
    (Get-Content (Join-Path $Root 'fromstarter\AGENTS.md') -Raw).Contains('the real one')
}
Check "the starter's own memory page is kept, not replaced by a blank one" {
    $sr = Join-Path $Root 'starter-src'
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-godspeed\observations') | Out-Null
    Set-Content (Join-Path $sr 'starter-godspeed\observations\MEMORY.md') '# the product wrote this'
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'memory' 2>&1 | Out-Null
    $d = Join-Path $Root 'keepindex'
    New-KitGodspeed -Path $d -StarterRepo $sr | Out-Null
    (Get-Content (Join-Path $d 'observations\MEMORY.md') -Raw).Contains('the product wrote this')
}
# The recipes the starter ships (next-action and work-item since 2026-09-15) reach every mission control:
# a new one whole, and one made before they shipped by a top-up into its skills room, which
# never touches a recipe folder the reader already has. Twins of the cases in test.sh.
Check "a new mission control has the recipe the starter ships" {
    $sr = Join-Path $Root 'starter-src'
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-godspeed\skills\next-action') | Out-Null
    Set-Content (Join-Path $sr 'starter-godspeed\skills\next-action\SKILL.md') 'the recipe'
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'recipe' 2>&1 | Out-Null
    $d = Join-Path $Root 'withrecipe'
    New-KitGodspeed -Path $d -StarterRepo $sr | Out-Null
    (Get-Content (Join-Path $d 'skills\next-action\SKILL.md') -Raw).Contains('the recipe')
}
Check "a mission control made before the recipe shipped gets it on the next run" {
    $d = Join-Path $Root 'fromstarter'   # made above, before the recipe existed
    Copy-KitStarterGodspeed -Path $d -StarterRepo (Join-Path $Root 'starter-src') | Out-Null
    (Get-Content (Join-Path $d 'skills\next-action\SKILL.md') -Raw).Contains('the recipe')
}
Check "a recipe the reader has edited is never overwritten" {
    $d = Join-Path $Root 'fromstarter'
    Set-Content (Join-Path $d 'skills\next-action\SKILL.md') 'my own version'
    Copy-KitStarterGodspeed -Path $d -StarterRepo (Join-Path $Root 'starter-src') | Out-Null
    (Get-Content (Join-Path $d 'skills\next-action\SKILL.md') -Raw).Contains('my own version')
}
Check "a starter that cannot be fetched still leaves a usable mission control, and warns" {
    $d = Join-Path $Root 'nostarter'
    $warned = $false
    try { New-KitGodspeed -Path $d -StarterRepo (Join-Path $Root 'ghost-repo') -WarningVariable w -WarningAction SilentlyContinue | Out-Null
          $warned = @($w).Count -gt 0 } catch { }
    (Test-KitGodspeed $d) -and $warned
}
Check "the real book kit's starter folder is reachable and has what the book names" {
    # The one case that must hit the network: it checks the DEFAULT a reader gets.
    $d = Join-Path $Root 'realstarter'
    $got = Copy-KitStarterGodspeed -Path $d -StarterRepo 'https://github.com/MichaelZelbel/godspeed-mission-control.git'
    if (-not $got) { Write-Host "        (skipped: no network)"; return $true }
    $missing = @()
    foreach ($f in 'AGENTS.md', 'profile\about-me.md', 'profile\people.md', 'profile\voice.md',
                    'procedures.md', 'decisions.md', 'observations\MEMORY.md', 'rules', 'skills') {
        if (-not (Test-Path (Join-Path $d $f))) { $missing += $f }
    }
    if ($missing.Count) { Write-Host "        missing: $($missing -join ', ')" }
    # skills/ must ARRIVE holding exactly the two recipes the mission control runs by itself,
    # next-action and work-item (in the starter since 2026-09-15, Chapter 7), and no
    # loose file: the five starter recipes moved out of starter-godspeed/ on 2026-08-20 so
    # the first recipe a reader puts there is one they wrote themselves.
    $loose = @(Get-ChildItem (Join-Path $d 'skills') -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -eq '.md' }).Count
    if ($loose -gt 0) { Write-Host "        skills/ arrived with $loose loose recipe file(s) in it" }
    $shipped = (Test-Path (Join-Path $d 'skills\next-action\SKILL.md')) -and
               (Test-Path (Join-Path $d 'skills\work-item\SKILL.md'))
    if (-not $shipped) { Write-Host "        skills/ arrived without next-action and work-item" }
    ($missing.Count -eq 0) -and ($loose -eq 0) -and $shipped
}

Write-Host ""
Write-Host "-- updating one that is already here"
Check "updating a folder that is not git is a warning, not a crash" {
    Update-KitGodspeed -Godspeed (New-TestDir 'notgit') 3>$null; $true
}
Check "an offline update still lets the rest of the run finish" {
    $d = New-TestDir 'nogit-remote'; git -C $d init -q
    Set-Content (Join-Path $d 'AGENTS.md') 'x'
    Update-KitGodspeed -Godspeed $d 3>$null; $true
}
Check "a mission control with no remote is not called out of date" {
    # A mission control made five minutes ago has nowhere to be out of date FROM, so
    # "could not pull, this may be out of date" is alarming and untrue.
    $d = New-TestDir 'noremote'; git -C $d init -q
    Set-Content (Join-Path $d 'AGENTS.md') 'x'
    # 6>&1 as well as 3>&1: Write-Host goes to the INFORMATION stream, not the
    # output or warning ones, so a test that only catches warnings sees nothing
    # and calls a working message a failure.
    $out = (Update-KitGodspeed -Godspeed $d 3>&1 6>&1 | Out-String)
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
Check "a tool this kit cannot copy is reported as such, with no reason to misread" {
    try { $env:KB_ASSUME_TOOLS = 'cursor'
          (@(Find-KitAiTools) -join ';') -eq 'cursor|none|Cursor|' }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "a tool keeping its conversations only online is not on the roster at all" {
    try { $env:KB_ASSUME_TOOLS = 'comet,claude-desktop'; @(Find-KitAiTools).Count -eq 0 }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "OpenCode is a tool this kit can copy" {
    try { $env:KB_ASSUME_TOOLS = 'opencode'
          (@(Find-KitAiTools) -join ';') -eq 'opencode|prompts|OpenCode|' }
    finally { $env:KB_ASSUME_TOOLS = $null }
}
# REAL DETECTION, on a pretend home, with a PATH and app folders holding none of the
# tools. The wizard of 2026-09-21 listed Gemini CLI, GitHub Copilot and OpenCode on a PC
# where a skill installer had merely made a skills folder for each (and Google
# Antigravity keeps its settings in .gemini). A folder with a tool's name is not the tool.
Check "skills folders and Antigravity's settings are not tools; each tool's own store is" {
    $save = @{ PATH = $env:PATH; LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA
               XDG_DATA_HOME = $env:XDG_DATA_HOME; HERMES_HOME = $env:HERMES_HOME }
    try {
        $h = New-TestDir 'detect-home'
        foreach ($d in '.copilot\skills\x', '.gemini\skills\x', '.gemini\antigravity', '.cursor\skills\x',
                       '.config\opencode\skills\x', '.claude\skills\x', '.codex\skills\x', '.openclaw\skills\x') {
            New-Item -ItemType Directory -Force (Join-Path $h $d) | Out-Null
        }
        $env:KB_HOME = $h; $env:KB_ASSUME_TOOLS = $null
        $env:PATH = Join-Path $env:SystemRoot 'System32'
        $env:LOCALAPPDATA = Join-Path $h 'AppData\Local'; $env:APPDATA = Join-Path $h 'AppData\Roaming'
        $env:XDG_DATA_HOME = $null; $env:HERMES_HOME = $null
        $none = @(Find-KitAiTools).Count -eq 0
        foreach ($d in '.local\share\opencode', '.gemini\tmp', '.claude\projects', '.codex\sessions',
                       'AppData\Roaming\Cursor\User') {
            New-Item -ItemType Directory -Force (Join-Path $h $d) | Out-Null
        }
        Set-Content (Join-Path $h '.local\share\opencode\opencode.db') '' -Encoding ascii
        $ids = (@(Find-KitAiTools) | ForEach-Object { ($_ -split '\|')[0] }) -join ' '
        $none -and ($ids -eq 'claude codex opencode cursor gemini')
    } finally {
        foreach ($k in $save.Keys) { Set-Item "env:$k" $save[$k] -ErrorAction SilentlyContinue
                                     if ($null -eq $save[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } }
        $env:KB_HOME = $null
    }
}
Check "no flag and no record means what every PC read before there was a choice" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex,cursor'; $env:KB_HOME = New-TestDir 'src-home1'
          (Get-KitEnabledSources) -eq 'claude,codex' }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HOME = $null }
}
Check "and never a tool this kit learned to copy later" {
    try { $env:KB_ASSUME_TOOLS = 'claude,opencode'; $env:KB_HOME = New-TestDir 'src-home1b'
          (Get-KitEnabledSources) -eq 'claude' }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_HOME = $null }
}
Check "the choice recorded on the device wins over detection" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex'; $env:KB_HOME = New-TestDir 'src-home2'
          New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.godspeed') | Out-Null
          Set-Content (Join-Path $env:KB_HOME '.godspeed\device.env') 'GODSPEED_PROMPT_SOURCES=claude' -Encoding ascii
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
          New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.godspeed') | Out-Null
          Set-Content (Join-Path $env:KB_HOME '.godspeed\device.env') 'GODSPEED_DIR=C:\somewhere' -Encoding ascii
          Set-KitPromptSources -Value 'claude,codex' | Out-Null
          Set-KitPromptSources -Value 'claude' | Out-Null
          $lines = @(Get-Content (Join-Path $env:KB_HOME '.godspeed\device.env'))
          (@($lines | Where-Object { $_ -eq 'GODSPEED_PROMPT_SOURCES=claude' }).Count -eq 1) -and
          (@($lines | Where-Object { $_ -match '^GODSPEED_PROMPT_SOURCES=' }).Count -eq 1) -and
          (@($lines | Where-Object { $_ -eq 'GODSPEED_DIR=C:\somewhere' }).Count -eq 1) }
    finally { $env:KB_HOME = $null }
}
Check "the report says what is copied, what was left off, and what still works with the mission control" {
    try { $env:KB_ASSUME_TOOLS = 'claude,codex,cursor'; $env:KB_SYNC_SOURCES = 'claude'
          $rep = (Write-KitSyncReport 6>&1 | Out-String)
          $rep.Contains('Claude Code: its memory folder') -and
          $rep.Contains('Not copied, because you left it off: Codex.') -and
          $rep.Contains('run the installer again and tick it') -and
          $rep.Contains('Also on this PC: Cursor. You can open your mission control folder in it') -and
          ($rep -notmatch 'cannot sync|not syncable|format yet') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}
Check "several such tools are one sentence, in the plural" {
    try { $env:KB_ASSUME_TOOLS = 'cursor,gemini'; $env:KB_SYNC_SOURCES = '-'
          (Write-KitSyncReport 6>&1 | Out-String).Contains('Cursor, Gemini CLI. You can open your mission control folder in them') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}
Check "a PC copying nothing is told so" {
    try { $env:KB_ASSUME_TOOLS = '-'; $env:KB_SYNC_SOURCES = '-'
          (Write-KitSyncReport 6>&1 | Out-String).Contains('No conversations are copied') }
    finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}
# THE WIZARD PAGE, as Michael met it on 2026-09-21: "Your AI tools", greyed boxes reading
# "cannot sync", and no way to act on any of them. Checked in the source, because the page
# only exists inside the compiled .exe.
Check "the wizard gives no tool a box it cannot tick, and names those tools in words" {
    $iss = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
    ($iss -notmatch 'ItemEnabled') -and ($iss -notmatch "cannot sync:") -and
    ($iss -match "Also on this PC: ' \+ Others") -and
    ($iss -match 'Every AI tool on this PC can work with your mission control, ticked or not')
}
Check "the wizard's boxes start unticked on a PC getting its first mission control" {
    $iss = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
    $iss -match "if RecordedSources = '\(auto\)' then\s+SyncPage\.Values\[row\] := \(FoundGodspeed <> ''\)"
}
Check "a page with nothing to tick is not shown" {
    $iss = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
    $iss -match 'if PageID = SyncPage\.ID then\s+Result := \(ToolCount = 0\)'
}
Check "the engine run without the wizard copies nothing on a PC getting its first mission control" {
    $eng = Get-Content (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Raw
    $eng -match "if \(\`$PromptSources -eq '\(auto\)' -and \`$isNew -and -not \`$Beside -and\s+\`$null -eq \(Get-KitDeviceEnvValue 'GODSPEED_PROMPT_SOURCES'\)\) \{ \`$PromptSources = '-' \}"
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
Check "the memory path is derived from the mission control folder" {
    (Get-KitMemoryLinkPath -Godspeed 'C:\godspeed') -eq (Join-Path $HOME '.claude\projects\c--godspeed\memory')
}
Check "linking a mission control makes a junction that points back at it" {
    try {
        $env:KB_ASSUME_TOOLS = 'claude'
        $d = Join-Path $Root 'linkme'
        New-KitGodspeed -Path $d | Out-Null
        Join-KitMemory -Godspeed $d | Out-Null
        $link = Get-KitMemoryLinkPath -Godspeed $d
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
        New-KitGodspeed -Path $d | Out-Null
        $link = Get-KitMemoryLinkPath -Godspeed $d
        New-Item -ItemType Directory -Force $link | Out-Null
        Set-Content (Join-Path $link 'precious.md') 'do not lose me'
        Join-KitMemory -Godspeed $d 3>$null | Out-Null
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
        New-KitGodspeed -Path $d | Out-Null
        Join-KitMemory -Godspeed $d | Out-Null
        $link = Get-KitMemoryLinkPath -Godspeed $d
        (-not (Test-Path $link)) -and (Test-Path (Join-Path $d 'observations\MEMORY.md'))
    } finally { $env:KB_ASSUME_TOOLS = $null }
}
Check "Claude Code switched off means its folder is left alone" {
    try {
        $env:KB_ASSUME_TOOLS = 'claude'
        $env:KB_SYNC_SOURCES = 'codex'
        $d = Join-Path $Root 'offgate'
        New-KitGodspeed -Path $d | Out-Null
        Join-KitMemory -Godspeed $d | Out-Null
        -not (Test-Path (Get-KitMemoryLinkPath -Godspeed $d))
    } finally { $env:KB_ASSUME_TOOLS = $null; $env:KB_SYNC_SOURCES = $null }
}

Write-Host ""
Write-Host "-- the kit's own programs, installed on the machine"
# Added 2026-08-10. The collector used to exist in exactly one person's own mission control, so the
# program the book promises its readers ("a program fills it") was nowhere they could get
# it. It lives in the kit now and is installed ON THE PC, never copied into the mission control folder,
# because Chapter 4 promises the mission control is a folder of text files and that nothing in it needs
# a terminal. These are the Windows twins of the cases in test.sh. Change one, change both.
function New-TestKit {
    param([string]$Path)
    New-Item -ItemType Directory -Force (Join-Path $Path 'tools') | Out-Null
    Set-Content (Join-Path $Path 'tools\prompt-harvest.js')   'console.log(1)'
    Set-Content (Join-Path $Path 'tools\compile-rules.js')    'console.log(1)'
    Set-Content (Join-Path $Path 'tools\mc-prompt-archive')  'print(1)'
    Set-Content (Join-Path $Path 'tools\mc-notebook-sync')   "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
    Set-Content (Join-Path $Path 'tools\mc-notebook-env')    "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
    Set-Content (Join-Path $Path 'tools\README.md')           '# not a program'
    git -C $Path init -q
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path -c user.email='t@t' -c user.name='t' commit -q -m 'tools' 2>&1 | Out-Null
}
Check "no kit named means nothing installed and nothing said" {
    # The assertion is now what the name claims. It used to capture streams 3 and 4 only,
    # while Write-KbOk speaks on 6, so this case passed on the author's machine while
    # actually running a full install: -ToolsRepo '' falls back to the GODSPEED_TOOLS_REPO
    # recorded in device.env, which is deliberate, and the suite had no home of its own so
    # it read (and rewrote) the real one. Both halves are fixed: the run has a fake home,
    # and this counts the programs as well as the words.
    $bin = Join-Path (Get-KitHome) '.local\bin'
    $before = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue).Count
    $out = Install-KitGodspeedTools -Godspeed (New-TestDir 'tools-none') -ToolsRepo '' 3>&1 4>&1 6>&1 | Out-String
    $after = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue).Count
    ($out.Trim() -eq '') -and ($after -eq $before)
}
Check "the three programs land on the PC and a README does not" {
    $kit = New-TestDir 'kit'; New-TestKit -Path $kit
    $godspeed = New-TestDir 'tools-godspeed'
    $home0 = $HOME
    try {
        $env:HOME = New-TestDir 'tools-home'
        Set-Variable -Name HOME -Value $env:HOME -Scope Global -Force
        Install-KitGodspeedTools -Godspeed $godspeed -ToolsRepo $kit | Out-Null
        $bin = Join-Path $HOME '.local\bin'
        (Test-Path (Join-Path $bin 'mc-prompt-archive')) -and
        (Test-Path (Join-Path $bin 'prompt-harvest.js')) -and
        (Test-Path (Join-Path $bin 'mc-prompt-harvest.cmd')) -and
        # The rules compiler is the one program in here a reader types by hand. Until
        # 2026-08-21 it was Python and the book named a path inside the mission control that nobody
        # has. Without the .cmd, a bare compile-rules.js silently does nothing in
        # PowerShell, which is worse than an error.
        (Test-Path (Join-Path $bin 'compile-rules.js')) -and
        (Test-Path (Join-Path $bin 'mc-compile-rules.cmd')) -and
        -not (Test-Path (Join-Path $bin 'README.md')) -and
        # THE ONE THAT MATTERS: nothing was put inside the mission control folder.
        (@(Get-ChildItem $godspeed -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -in 'mc-prompt-archive', 'prompt-harvest.js', 'compile-rules.js' }).Count -eq 0) -and
        # A scheduled job gets almost no environment, so where the mission control is must be written down.
        (@(Get-Content (Join-Path $HOME '.godspeed\device.env') | Where-Object { $_ -match '^GODSPEED_DIR=' }).Count -eq 1)
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $home0
    }
}
Check "the notebook runner lands with them, and a join refreshes from the kit written down" {
    # The notebook step schedules ~\.local\bin\mc-notebook-sync and silently does
    # nothing when it is missing, so this install is what decides whether a reader's
    # notebook ever updates itself. And a JOIN names no kit, so a later run with an
    # empty -ToolsRepo must refresh from the repo written down at install time.
    $kit = New-TestDir 'kit2'; New-TestKit -Path $kit
    $godspeed = New-TestDir 'tools-godspeed2'
    $home0 = $HOME
    try {
        $env:HOME = New-TestDir 'tools-home2'
        Set-Variable -Name HOME -Value $env:HOME -Scope Global -Force
        Install-KitGodspeedTools -Godspeed $godspeed -ToolsRepo $kit | Out-Null
        $bin = Join-Path $HOME '.local\bin'
        $landed = Test-Path (Join-Path $bin 'mc-notebook-sync')
        Remove-Item (Join-Path $bin 'mc-notebook-sync') -Force -ErrorAction SilentlyContinue
        Install-KitGodspeedTools -Godspeed $godspeed -ToolsRepo '' | Out-Null
        $landed -and
        (Test-Path (Join-Path $bin 'mc-notebook-sync')) -and
        (@(Get-Content (Join-Path $HOME '.godspeed\device.env') | Where-Object { $_ -match '^GODSPEED_TOOLS_REPO=' }).Count -eq 1)
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $home0
    }
}
Check "the standalone join offers the notebook connection" {
    # Until 2026-08-18 only setup-godspeed.ps1 called the connect step: a joined second
    # machine got the runner installed and the credentials sitting in the folder,
    # and nothing introduced them.
    $joinText = Get-Content (Join-Path $PSScriptRoot '..\join.ps1') -Raw
    $joinText -match '(?m)^Connect-KitNotebook -Godspeed \$Godspeed'
}

Write-Host ""
Write-Host "-- the daily job that files what you type to an AI"
# Added 2026-08-10. The mission control keeps a drawer of everything its owner has typed to an
# assistant, and filling it needs a job on each machine. Nothing installed that job:
# one computer had one because somebody typed it into that computer's schedule by
# hand, and every other computer quietly kept nothing. These are the Windows twins of
# the cases in test.sh. When you change one side, change both.
$TaskForTests = 'Godspeed prompt archive TEST'
# KB_HOME points every case here at a scratch home folder. Without it, a PC that
# already has the kit's programs under its real ~\.local\bin (the author's does)
# would take the installed-program branch in cases that are about the fallback,
# and "a mission control with no harvester" would find a harvester after all.
Check "a mission control with no harvester stays quiet" {
    try {
        $env:KB_HOME = New-TestDir 'noharvest-home'
        $bare = New-TestDir 'noharvest'
        $out = Install-KitPromptHarvest -Godspeed $bare -TaskName $TaskForTests 3>&1 4>&1 | Out-String
        ($out.Trim() -eq '') -and -not (Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue)
    } finally { $env:KB_HOME = $null }
}
Check "a mission control with a harvester gets a job that runs it, and only once a day" {
    $godspeed = New-TestDir 'harvest'
    New-Item -ItemType Directory -Force (Join-Path $godspeed 'bin') | Out-Null
    Set-Content (Join-Path $godspeed 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest-home'
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests | Out-Null
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        $args = if ($task) { ($task.Actions | ForEach-Object { $_.Arguments }) -join ' ' } else { '' }
        [bool]$task -and ($args -match 'prompt-harvest\.js') -and ($args -match '--once-a-day')
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "running the installer twice does not stack up two jobs" {
    $godspeed = New-TestDir 'harvest2'
    New-Item -ItemType Directory -Force (Join-Path $godspeed 'bin') | Out-Null
    Set-Content (Join-Path $godspeed 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest2-home'
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests | Out-Null
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests | Out-Null
        @(Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue).Count -eq 1
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "a daily job for a mission control that moved is re-pointed at this mission control (D-179)" {
    $old = New-TestDir 'harvest-old'; $new = New-TestDir 'harvest-new'
    foreach ($h in $old, $new) {
        New-Item -ItemType Directory -Force (Join-Path $h 'bin') | Out-Null
        Set-Content (Join-Path $h 'bin\prompt-harvest.js') 'console.log(1)'
    }
    try {
        $env:KB_HOME = New-TestDir 'harvest-move-home'
        Install-KitPromptHarvest -Godspeed $old -TaskName $TaskForTests | Out-Null
        $out = Install-KitPromptHarvest -Godspeed $new -TaskName $TaskForTests 3>&1 4>&1 6>&1 | Out-String
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        [bool]$task -and ($task.Actions[0].WorkingDirectory -eq $new) -and ($task.Actions[0].Arguments -like "*`"$new`"*") -and
            ($out -like '*Re-pointing*') -and (@(Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue).Count -eq 1)
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "a daily job that already runs in this mission control is left alone" {
    $godspeed = New-TestDir 'harvest-same'
    New-Item -ItemType Directory -Force (Join-Path $godspeed 'bin') | Out-Null
    Set-Content (Join-Path $godspeed 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        $env:KB_HOME = New-TestDir 'harvest-same-home'
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests | Out-Null
        $out = Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests 3>&1 4>&1 6>&1 | Out-String
        $out -like '*already scheduled*'
    } finally {
        $env:KB_HOME = $null
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "device.env is re-pointed when GODSPEED_DIR names another folder (D-179)" {
    try {
        $env:KB_HOME = New-TestDir 'devenv-home'
        New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.godspeed') | Out-Null
        Set-Content (Join-Path $env:KB_HOME '.godspeed\device.env') "GODSPEED_DIR=C:\gone\godspeed`nGODSPEED_PROMPT_SOURCES=claude"
        $godspeed = New-TestDir 'devenv-godspeed'
        Set-KitGodspeedDirRecord -Godspeed $godspeed | Out-Null
        $lines = @(Get-Content (Join-Path $env:KB_HOME '.godspeed\device.env'))
        ($lines -contains "GODSPEED_DIR=$godspeed") -and ($lines -contains 'GODSPEED_PROMPT_SOURCES=claude') -and
            (@($lines | Where-Object { $_ -like 'GODSPEED_DIR=*' }).Count -eq 1)
    } finally { $env:KB_HOME = $null }
}
Check "device.env that already names this mission control is left exactly as it was" {
    try {
        $env:KB_HOME = New-TestDir 'devenv-home2'
        $godspeed = New-TestDir 'devenv-godspeed2'
        New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.godspeed') | Out-Null
        Set-Content (Join-Path $env:KB_HOME '.godspeed\device.env') "GODSPEED_DIR=$godspeed"
        $before = Get-Content (Join-Path $env:KB_HOME '.godspeed\device.env') -Raw
        Set-KitGodspeedDirRecord -Godspeed $godspeed | Out-Null
        (Get-Content (Join-Path $env:KB_HOME '.godspeed\device.env') -Raw) -eq $before
    } finally { $env:KB_HOME = $null }
}
Check "THE REGRESSION: the program installed under .local\bin is found and scheduled" {
    # This exact branch was dead on every reader's PC: the path carried a literal
    # BACKSPACE byte (".local<0x08>in"), so the installed program was never found
    # and the function returned without registering anything. The suite never saw
    # it because every case above hand-creates the mc-copy fallback instead. This
    # case builds the REAL layout: the program under <home>\.local\bin and a mission control
    # that ships no copy of its own.
    $godspeed = New-TestDir 'harvest3'
    try {
        $env:KB_HOME = New-TestDir 'harvest3-home'
        $bin = Join-Path $env:KB_HOME '.local\bin'
        New-Item -ItemType Directory -Force $bin | Out-Null
        Set-Content (Join-Path $bin 'prompt-harvest.js') 'console.log(1)'
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $TaskForTests | Out-Null
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
$NotebookTask = 'Godspeed notebook sync TEST'
function Invoke-NotebookCase([scriptblock]$Body) {
    $home0 = $HOME; $envHome0 = $env:HOME; $keyEnv0 = $env:GODSPEED_AGE_KEY
    try {
        $h = New-TestDir ('nb-home-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $env:HOME = $h
        $env:KB_HOME = $h
        Set-Variable -Name HOME -Value $h -Scope Global -Force
        New-Item -ItemType Directory -Force (Join-Path $h '.godspeed') | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $h '.local\bin') | Out-Null
        & $Body $h
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $envHome0
        $env:KB_HOME = $null
        $env:GODSPEED_AGE_KEY = $keyEnv0
    }
}
function New-NotebookGodspeed([string]$Name) {
    $godspeed = New-TestDir $Name
    New-Item -ItemType Directory -Force (Join-Path $godspeed 'secrets') | Out-Null
    return $godspeed
}

Check "a mission control with no notebook reports 'none'" {
    Invoke-NotebookCase { param($h) (Get-KitNotebookState -Godspeed (New-NotebookGodspeed 'nb1')) -eq 'none' }
}
Check "a folder carrying a sealed key reports 'sealed'" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb2'
        Set-Content (Join-Path $godspeed 'secrets\mc-key.age') 'x'
        (Get-KitNotebookState -Godspeed $godspeed) -eq 'sealed'
    }
}
Check "unsealing does nothing when the folder carries no key" {
    Invoke-NotebookCase { param($h) (Unlock-KitGodspeedKey -Godspeed (New-NotebookGodspeed 'nb3')) -eq $false }
}
Check "sealing does nothing when this PC has no key" {
    Invoke-NotebookCase { param($h) (Protect-KitGodspeedKey -Godspeed (New-NotebookGodspeed 'nb4')) -eq $false }
}
Check "unsealing is a no-op when this PC already has a key" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb5'
        Set-Content (Join-Path $godspeed 'secrets\mc-key.age') 'x'
        Set-Content (Join-Path $h '.godspeed\age-key.txt') 'k'
        (Unlock-KitGodspeedKey -Godspeed $godspeed) -eq $true
    }
}

Check "Claude Code is given an .mcp.json, and it is valid JSON" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb6'
        Write-KitMcpConfig -Godspeed $godspeed | Out-Null
        $f = Join-Path $godspeed '.mcp.json'
        (Test-Path $f) -and ((Get-Content $f -Raw | ConvertFrom-Json).mcpServers.menerio.url -eq 'https://mcp.menerio.com')
    }
}
# Not "the assistant": Hermes never reads a folder .mcp.json, checked in its source. A
# kit that says otherwise is telling a reader their mission control carries configuration it does
# not carry, which is the exact shape of the workspace line this batch already removed.
#
# Until 2026-09-20 the file and the installer both went on to tell the reader to run
# `hermes mcp add` by hand. mc-menerio-connect does that now, from the same stored key,
# so the file names THAT and nobody is handed a command to type.
Check "the file says plainly that Hermes and Codex do not read it, and names the program that connects them" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb6b'
        $out = (Write-KitMcpConfig -Godspeed $godspeed 3>&1 6>&1 | Out-String)
        $j = Get-Content (Join-Path $godspeed '.mcp.json') -Raw
        $j.Contains('Hermes and Codex do not read this file') -and $j.Contains('mc-menerio-connect') -and
            -not $j.Contains('hermes mcp') -and
            -not $j.Contains('tells your assistant') -and
            $out.Contains('for Claude Code') -and -not ($out -match '(?i)hermes')
    }
}
Check "the connection NAMES the credential rather than carrying one" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb7'
        Write-KitMcpConfig -Godspeed $godspeed | Out-Null
        $auth = (Get-Content (Join-Path $godspeed '.mcp.json') -Raw | ConvertFrom-Json).mcpServers.menerio.headers.Authorization
        $auth -eq 'Bearer ${MENERIO_API_KEY}'
    }
}
Check "a reader's own .mcp.json is never overwritten" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb8'
        Set-Content (Join-Path $godspeed '.mcp.json') 'mine'
        Write-KitMcpConfig -Godspeed $godspeed | Out-Null
        (Get-Content (Join-Path $godspeed '.mcp.json') -Raw).Trim() -eq 'mine'
    }
}

# WHEN A KEY RUNS OUT: the record beside the keys. The Windows twin of the same block in
# test.sh. A key is a thing with a lifespan, and the day it dies nothing announces it.
Check "a mission control with no record gets one, and it explains its own columns" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nbx1'
        Write-KitExpiryRecord -Godspeed $godspeed | Out-Null
        $f = Join-Path $godspeed 'secrets\expires.txt'
        $raw = if (Test-Path $f) { Get-Content $f -Raw } else { '' }
        (Test-Path $f) -and $raw.Contains('the page you get a new one from') -and
            $raw.Contains('NEVER PUT A KEY ITSELF IN HERE')
    }
}
Check "the record holds no key of its own: every line in it is a comment" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nbx2'
        Write-KitExpiryRecord -Godspeed $godspeed | Out-Null
        $live = @(Get-Content (Join-Path $godspeed 'secrets\expires.txt') |
                  Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') })
        $live.Count -eq 0
    }
}
Check "running the installer again never touches what the reader wrote in it" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nbx3'
        Write-KitExpiryRecord -Godspeed $godspeed | Out-Null
        $f = Join-Path $godspeed 'secrets\expires.txt'
        Add-Content $f 'MY_KEY  2027-01-01  https://example.com  # mine'
        Write-KitExpiryRecord -Godspeed $godspeed | Out-Null
        @(Get-Content $f | Where-Object { $_ -like 'MY_KEY*' }).Count -eq 1
    }
}

Check "no sync program on this PC means nothing is scheduled and nothing is said" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb9'
        $out = Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask 3>&1 4>&1 | Out-String
        ($out.Trim() -eq '') -and -not (Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue)
    }
}
Check "a change that is saved updates the notebook, and the hook cannot fail the save" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb10'
        git -C $godspeed init -q
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
            $hook = Join-Path $godspeed '.git\hooks\post-commit'
            $body = if (Test-Path $hook) { Get-Content $hook -Raw } else { '' }
            $body.Contains('mc-notebook-sync') -and $body.Contains('exit 0') -and -not $body.Contains('\')
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "running the installer twice does not stack up two hourly jobs" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb11'
        git -C $godspeed init -q
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
            @(Get-ScheduledTask -TaskName $NotebookTask -ErrorAction SilentlyContinue).Count -le 1
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "an hourly job for a mission control that moved is re-pointed at this mission control (D-179)" {
    Invoke-NotebookCase {
        param($h)
        $old = New-NotebookGodspeed 'nb-old'; $new = New-NotebookGodspeed 'nb-new'
        git -C $old init -q; git -C $new init -q
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            Install-KitNotebookSync -Godspeed $old -TaskName $NotebookTask | Out-Null
            Install-KitNotebookSync -Godspeed $new -TaskName $NotebookTask | Out-Null
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
        $godspeed = New-NotebookGodspeed 'nb14'
        git -C $godspeed init -q
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
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
        $godspeed = New-NotebookGodspeed 'nb15'
        git -C $godspeed init -q
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            $bash = Get-KitGitBash
            if (-not $bash) { return $true }
            Register-ScheduledTask -TaskName $NotebookTask -Force `
                -Action (New-ScheduledTaskAction -Execute $bash -Argument '-lc "exit 0"') `
                -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(1)) | Out-Null
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
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
        $godspeed = New-NotebookGodspeed 'nb12'
        git -C $godspeed init -q
        New-Item -ItemType Directory -Force (Join-Path $godspeed '.git\hooks') | Out-Null
        Set-Content (Join-Path $godspeed '.git\hooks\post-commit') "#!/bin/sh`n# someone elses hook"
        Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
        try {
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $NotebookTask | Out-Null
            (Get-Content (Join-Path $godspeed '.git\hooks\post-commit') -Raw).Contains('someone elses hook')
        } finally {
            Unregister-ScheduledTask -TaskName $NotebookTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
Check "a reader who says no is not asked again and nothing is written" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'nb13'
        $env:KB_NOTEBOOK = 'skip'
        try {
            $out = Connect-KitNotebook -Godspeed $godspeed 3>&1 4>&1 | Out-String
            ($out.Trim() -eq '') -and -not (Test-Path (Join-Path $godspeed '.mcp.json'))
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
            $godspeed = New-NotebookGodspeed 'nb14'
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            (Save-KitNotebookToken -Godspeed $godspeed -Token 'test-token-not-a-real-one-0123456789') -and
            (Test-Path (Join-Path $godspeed 'secrets\mc-secrets.env.age')) -and
            (Get-KitNotebookState -Godspeed $godspeed) -eq 'connected'
        }
    }
    Check "the key reads back exactly as it was pasted, once, because one key does both jobs" {
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-NotebookGodspeed 'nb15'
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            [void](Save-KitNotebookToken -Godspeed $godspeed -Token 'test-token-not-a-real-one-0123456789')
            $lines = @(& age -d -i $env:GODSPEED_AGE_KEY (Join-Path $godspeed 'secrets\mc-secrets.env.age'))
            ($lines -contains 'MENERIO_API_KEY=test-token-not-a-real-one-0123456789') -and
            (@($lines | Where-Object { $_ -like 'MENERIO_*' }).Count -eq 1)
        }
    }
    Check "connecting again replaces the credential instead of keeping two" {
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-NotebookGodspeed 'nb16'
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            [void](Save-KitNotebookToken -Godspeed $godspeed -Token 'first-token-not-real-0123456789')
            [void](Save-KitNotebookToken -Godspeed $godspeed -Token 'second-token-not-real-98765432')
            $lines = @(& age -d -i $env:GODSPEED_AGE_KEY (Join-Path $godspeed 'secrets\mc-secrets.env.age'))
            (@($lines | Where-Object { $_ -like 'MENERIO_API_KEY=*' }).Count -eq 1) -and
            ($lines -contains 'MENERIO_API_KEY=second-token-not-real-98765432')
        }
    }
    Check "a folder this PC cannot open reports 'locked-out', and is never rewritten" {
        # THE CASE THAT ALMOST DESTROYED A REAL GODSPEED. A folder carrying credentials this
        # computer cannot open must be REFUSED, never rewritten: re-locking it to this
        # machine's key shuts every other computer out of every credential at once,
        # silently. It happened on 2026-08-16, to a live mission control, during a test run.
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-NotebookGodspeed 'nb18'
            $other = Join-Path $h 'other-key.txt'
            & age-keygen -o $other 2>$null | Out-Null
            $recip = (& age-keygen -y $other | Select-Object -First 1)
            $plain = Join-Path $h 'plain.txt'
            Set-KbTextFile -Path $plain -Lines @('MENERIO_API_KEY=belongs-to-someone-else-0123456789')
            & age -r $recip -o (Join-Path $godspeed 'secrets\mc-secrets.env.age') $plain
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            & age-keygen -o $env:GODSPEED_AGE_KEY 2>$null | Out-Null
            $store = Join-Path $godspeed 'secrets\mc-secrets.env.age'
            $before = (Get-FileHash $store).Hash
            $state = Get-KitNotebookState -Godspeed $godspeed
            $refused = (Save-KitNotebookToken -Godspeed $godspeed -Token 'a-new-token-0123456789') -eq $false
            Connect-KitNotebook -Godspeed $godspeed 3>&1 4>&1 | Out-Null
            ($state -eq 'locked-out') -and $refused -and ((Get-FileHash $store).Hash -eq $before)
        }
    }
    Check "a key that does not open the folder's credentials is refused, not sealed" {
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-NotebookGodspeed 'nb17'
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            [void](Save-KitNotebookToken -Godspeed $godspeed -Token 'a-token-not-real-0123456789')
            # A DIFFERENT key. age-keygen refuses to write over a file that is already
            # there, so without the removal the key never changes, the guard passes, and
            # this case walks straight into `age -p` and waits for a human forever. That
            # is exactly how the missing terminal guard was found on 2026-08-16.
            Remove-Item $env:GODSPEED_AGE_KEY -Force -ErrorAction SilentlyContinue
            & age-keygen -o $env:GODSPEED_AGE_KEY 2>$null | Out-Null
            $r = Protect-KitGodspeedKey -Godspeed $godspeed
            ($r -eq $false) -and -not (Test-Path (Join-Path $godspeed 'secrets\mc-key.age'))
        }
    }
} else {
    Write-Host "  skip  the real lock-and-unlock cases (age is not on this PC: winget install --id FiloSottile.age)"
}

Write-Host ""
Write-Host "-- the installer's own files"
Check "setup-godspeed.ps1 parses"       { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'setup-godspeed.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "join.ps1 parses"            { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\join.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "build-installer.ps1 parses" { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-installer.ps1'), [ref]$null, [ref]$e); $e.Count -eq 0 }
Check "no CODE uses utf8NoBOM, which PowerShell 5.1 has never heard of" {
    # Reads the parsed tokens rather than the raw text, because the comment that
    # explains why not to use it says the word too, and a test that cannot tell a
    # warning from the mistake it warns about is a test that cries wolf.
    $hits = 0
    foreach ($f in (Join-Path $PSScriptRoot '..\join.ps1'), (Join-Path $PSScriptRoot 'setup-godspeed.ps1')) {
        $tokens = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
        $hits += @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'utf8NoBOM' }).Count
    }
    $hits -eq 0
}
Check "the wizard asks the library where the mission control is, rather than searching again" {
    Select-String -Path (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Pattern 'Find-KitGodspeed' -Quiet
}
Check "the wizard asks for no administrator rights of its own" {
    Select-String -Path (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Pattern 'PrivilegesRequired=lowest' -Quiet
}
Check "the wizard asks the library which AI tools are here" {
    Select-String -Path (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Pattern 'Find-KitAiTools' -Quiet
}
Check "the wizard hands the person's choice to the engine" {
    (Select-String -Path (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Pattern 'GetPromptSources' -Quiet) -and
    (Select-String -Path (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Pattern 'PromptSources' -Quiet)
}
# THE WIZARD STARTS THE ENGINE WITH -File UNDER WINDOWS POWERSHELL 5.1, so that is how this
# starts it. Every other case here calls functions directly, and 333 of them passed while a
# clean machine with nothing ticked got no mission control at all: 5.1 read the value '-' as a parameter
# name and the engine stopped before its first line, while the wizard said Finished.
Check "the engine starts when the wizard says nothing was ticked, launched the way the wizard launches it" {
    $iss = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
    if ($iss -notmatch "if Result = '' then Result := '([^']*)';") { return $false }
    $none = $Matches[1]
    $engine = Get-Content (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Raw
    if ($engine -notmatch '(?s)(param\(.*?\r?\n\))') { return $false }
    $stub = Join-Path (New-TestDir 'wizard-args') 'stub.ps1'
    Set-Content -Path $stub -Value ($Matches[1] + "`r`n" + '"BOUND:[$PromptSources]"') -Encoding ascii
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $out = & $ps51 -NoProfile -ExecutionPolicy Bypass -File $stub -NoPause -Godspeed 'C:\x' -PromptSources $none -KbBranch 'v0' 2>&1 | Out-String
    if ($out -notmatch ("BOUND:\[" + [regex]::Escape($none) + "\]")) { Write-Host "        $($out.Trim())"; return $false }
    $engine.Contains("-eq '$none'")
}
Check "no source file carries a stray control byte" {
    # The harvest task was dead on every reader's PC because one path carried a
    # literal backspace character - the corpse of a '\b' interpreted on its way
    # into the file. It rendered invisibly, so no eye and no text search could
    # see it. Bytes do not lie.
    $hits = 0
    foreach ($f in (Join-Path $PSScriptRoot '..\join.ps1'), (Join-Path $PSScriptRoot '..\lib.sh'),
                    (Join-Path $PSScriptRoot 'setup-godspeed.ps1'), (Join-Path $PSScriptRoot 'godspeed-setup.iss')) {
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
# installer has to deliver it to BOTH kinds of mission control: a brand new one and one somebody has had
# for months.
Check "a mission control with no due room gets one, and it teaches the window rather than a due date" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'due1'
        Write-KitDueFolder -Godspeed $godspeed | Out-Null
        $f = Join-Path $godspeed 'due\README.md'
        $raw = if (Test-Path $f) { Get-Content $f -Raw } else { '' }
        (Test-Path $f) -and
            $raw.Contains('the first day you can do the thing, and the last day you') -and
            $raw.Contains('No date, not eligible')
    }
}
Check "and it says a reader needs no calendar for any of it" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'due2'
        Write-KitDueFolder -Godspeed $godspeed | Out-Null
        (Get-Content (Join-Path $godspeed 'due\README.md') -Raw).Contains('You do not need a calendar')
    }
}
Check "running the installer again never touches a deadline the reader wrote" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'due3'
        Write-KitDueFolder -Godspeed $godspeed | Out-Null
        Set-Content (Join-Path $godspeed 'due\car-service.md') 'mine'
        Write-KitDueFolder -Godspeed $godspeed | Out-Null
        ((Get-Content (Join-Path $godspeed 'due\car-service.md') -Raw).Trim() -eq 'mine')
    }
}
Check "a brand new mission control carries the due room from day one, not after an upgrade" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = Join-Path (New-TestDir 'due4') 'godspeed'
        New-KitGodspeed -Path $godspeed 3>&1 4>&1 6>&1 | Out-Null
        Test-Path (Join-Path $godspeed 'due\README.md')
    }
}
# THE TWO ROADS MUST LAY DOWN THE SAME WORDS. Compared line by line rather than byte for byte,
# because this side writes Windows line endings and the bash twin writes Unix ones: that is the
# one difference allowed, and comparing raw bytes would fail forever on a difference nobody can
# see or should care about. Every other difference is a typo fixed in one copy and not the other.
Check "the words are the same as the reader kit's own copy, line for line" {
    Invoke-NotebookCase {
        param($h)
        $kit = Join-Path $PSScriptRoot '..\..\teach-it-once-kit\starter-godspeed\due\README.md'
        if (-not (Test-Path $kit)) { Write-Host "        (the reader kit is not on this PC to compare with)"; return $true }
        $godspeed = New-NotebookGodspeed 'due5'
        Write-KitDueFolder -Godspeed $godspeed | Out-Null
        $mine  = @(Get-Content (Join-Path $godspeed 'due\README.md'))
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
# convention that mc-check-keys implements, so a reader with an established mission control was handed
# a page that did not document what their own tool was doing. Only the new-godspeed path, which
# copies from the kit, was current. The bash suite caught its copy; nothing watched this one.
Check "the expiry page matches the reader kit's own copy, line for line" {
    Invoke-NotebookCase {
        param($h)
        $kit = Join-Path $PSScriptRoot '..\..\teach-it-once-kit\starter-godspeed\secrets\expires.txt'
        if (-not (Test-Path $kit)) { Write-Host "        (the reader kit is not on this PC to compare with)"; return $true }
        $godspeed = New-NotebookGodspeed 'exp1'
        Write-KitExpiryRecord -Godspeed $godspeed | Out-Null
        $mine   = @(Get-Content (Join-Path $godspeed 'secrets\expires.txt'))
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
# THE BUG THESE EXIST FOR. Measured on a real existing mission control during Run 2: the top-up found
# no profile\, so it copied the starter's in beside a context\ that already held the same
# four filenames. The next run then warned "you have both, delete the empty one" at a
# reader whose folders both had four files in them. The installer built the duplicate and
# then complained about it, and the complaint was not true either.

Check "a mission control with context\ is told profile\ is the same room" {
    $d = New-TestDir 'twin1'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    (Get-KitRoomTwin -Godspeed $d -Name 'profile') -eq 'context'
}
Check "memory\ and observations\ are the same pair, asked either way round" {
    $d = New-TestDir 'twin2'
    New-Item -ItemType Directory -Force (Join-Path $d 'observations') | Out-Null
    ((Get-KitRoomTwin -Godspeed $d -Name 'memory') -eq 'observations') -and
        ((Get-KitRoomTwin -Godspeed $d -Name 'rules') -eq '')
}
Check "context\ becomes profile\ rather than gaining a sibling" {
    $d = New-TestDir 'rooms1'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Set-Content (Join-Path $d 'context\about-me.md') 'mine'
    Update-KitFolderNames -Godspeed $d 3>&1 6>&1 | Out-Null
    (Test-Path (Join-Path $d 'profile\about-me.md')) -and -not (Test-Path (Join-Path $d 'context'))
}
# THE LINE THAT MADE THE DUPLICATE. It used to be an unconditional New-Item.
Check "a mission control that really has both keeps both, and is told what is in each" {
    $d = New-TestDir 'rooms2'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $d 'profile') | Out-Null
    Set-Content (Join-Path $d 'context\a.md') 'a'
    Set-Content (Join-Path $d 'profile\b.md') 'b'
    $out = (Update-KitFolderNames -Godspeed $d 3>&1 6>&1 | Out-String)
    (Test-Path (Join-Path $d 'context\a.md')) -and (Test-Path (Join-Path $d 'profile\b.md')) -and
        -not $out.Contains('delete the empty one') -and $out.Contains('1 inside') -and
        $out.Contains('your assistant reads profile')
}
Check "rules\ is made whatever else is going on" {
    $d = New-TestDir 'rooms3'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Update-KitFolderNames -Godspeed $d 3>&1 6>&1 | Out-Null
    (Test-Path (Join-Path $d 'rules')) -and -not (Test-Path (Join-Path $d 'context'))
}
Check "the top-up does NOT drop profile\ beside an existing context\" {
    $starter = New-TestDir 'rooms-starter'
    foreach ($r in 'profile', 'observations') {
        New-Item -ItemType Directory -Force (Join-Path $starter "starter-godspeed\$r") | Out-Null
    }
    Set-Content (Join-Path $starter 'starter-godspeed\profile\about-me.md') 'starter'
    Set-Content (Join-Path $starter 'starter-godspeed\observations\MEMORY.md') 'starter'
    Set-Content (Join-Path $starter 'starter-godspeed\AGENTS.md') 'starter'
    git -C $starter init -q 2>&1 | Out-Null
    git -C $starter add -A 2>&1 | Out-Null
    git -C $starter -c user.email='t@t' -c user.name='t' commit -q -m s 2>&1 | Out-Null

    $d = New-TestDir 'rooms4'
    New-Item -ItemType Directory -Force (Join-Path $d 'context') | Out-Null
    Set-Content (Join-Path $d 'context\about-me.md') 'mine'
    Copy-KitStarterGodspeed -Path $d -StarterRepo $starter 3>&1 6>&1 | Out-Null
    $script:RoomsStarter = $starter
    -not (Test-Path (Join-Path $d 'profile')) -and
        ((Get-Content (Join-Path $d 'context\about-me.md') -Raw).Trim() -eq 'mine') -and
        (Test-Path (Join-Path $d 'AGENTS.md')) -and (Test-Path (Join-Path $d 'observations'))
}
Check "but a mission control with neither name still gets profile\, or the guard went too far" {
    $d = New-TestDir 'rooms5'
    Copy-KitStarterGodspeed -Path $d -StarterRepo $script:RoomsStarter 3>&1 6>&1 | Out-Null
    Test-Path (Join-Path $d 'profile')
}

Write-Host ""
Write-Host "-- a kit ships products, not its own test suite"
#
# Measured on a real install during Run 2: test-notebook-sync.sh and test-prompt-archive.sh
# were copied onto the reader's PATH beside mc-due and mc-check-keys.
Check "the products are installed and the kit's own tests are not" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'tools-kit'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        foreach ($f in 'due.js', 'check-keys.js', 'mc-notebook-sync', 'test-notebook-sync.sh',
                        'test-prompt-archive.sh', 'README.md') {
            Set-Content (Join-Path $kit "tools\$f") "// $f"
        }
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        Install-KitGodspeedTools -Godspeed (New-NotebookGodspeed 'tools-godspeed') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        $bin = Join-Path $h '.local\bin'
        $shipped = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'test-*' })
        if ($shipped) { Write-Host "        shipped to the reader: $($shipped.Name -join ', ')" }
        (Test-Path (Join-Path $bin 'due.js')) -and
            (Test-Path (Join-Path $bin 'mc-notebook-sync')) -and
            (Test-Path (Join-Path $bin 'mc-due.cmd')) -and
            -not (Test-Path (Join-Path $bin 'README.md')) -and
            $shipped.Count -eq 0
    }
}

Write-Host ""
Write-Host "-- a launcher for every command the book prints"

# Before 2026-08-29 only the prompt collector got a .cmd here, so on Windows mc-check-keys and
# mc-compile-rules were extension-less shell scripts nothing could run, while the book printed
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
        $godspeed = New-NotebookGodspeed 'launch-godspeed'
        Install-KitGodspeedTools -Godspeed $godspeed -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        $bin = Join-Path $h '.local\bin'
        $missing = @('mc-prompt-harvest', 'mc-compile-rules', 'mc-check-keys', 'mc-due') |
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
        Install-KitGodspeedTools -Godspeed (New-NotebookGodspeed 'launch-godspeed2') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        (Get-Content (Join-Path $h '.local\bin\mc-due.cmd') -Raw).Contains('%~dp0due.js')
    }
}
Check "a kit that ships no due.js gets no mc-due, and says nothing about it" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-TestDir 'launch-kit3'
        New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
        Set-Content (Join-Path $kit 'tools\prompt-harvest.js') '// ph'
        git -C $kit init -q 2>&1 | Out-Null
        git -C $kit add -A 2>&1 | Out-Null
        git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
        Install-KitGodspeedTools -Godspeed (New-NotebookGodspeed 'launch-godspeed3') -ToolsRepo $kit 3>&1 4>&1 6>&1 | Out-Null
        -not (Test-Path (Join-Path $h '.local\bin\mc-due.cmd'))
    }
}

Write-Host ""
Write-Host "-- connect Menerio once: every assistant, and a way back in"
#
# Twins of the block with the same name in test.sh. Before 2026-09-20 the connect step
# stored the key, wrote .mcp.json for Claude Code, and printed a `hermes mcp add` command
# for the reader to type. Codex got nothing. The work now belongs to the kit's
# mc-menerio-connect, and what is tested here is everything the installer owns around it.
# The program itself is a stand-in, because the kit's own suite tests the real one.
function New-MenerioKit {
    <# A committed kit whose tools folder holds exactly the named files. #>
    param([string]$Name, [hashtable]$Files)
    $kit = New-TestDir $Name
    New-Item -ItemType Directory -Force (Join-Path $kit 'tools') | Out-Null
    foreach ($k in $Files.Keys) {
        [System.IO.File]::WriteAllText((Join-Path $kit "tools\$k"), ($Files[$k] -replace "`r`n", "`n"))
    }
    git -C $kit init -q 2>&1 | Out-Null
    git -C $kit add -A 2>&1 | Out-Null
    git -C $kit -c user.email='t@t' -c user.name='t' commit -q -m tools 2>&1 | Out-Null
    return $kit
}
function Install-MenerioKit {
    <#  Install-KitGodspeedTools, with BOTH copies of PATH put straight back around it.

        Every case in this file has a fresh temporary home, and every install does two
        things to PATH. It prepends its bin folder to the persisted user PATH (see
        $UserPath0 at the top). And Update-KitPath rebuilds THIS PROCESS's PATH as
        machine + user + whatever it already was, so inside one long run the process copy
        grows by the whole registry PATH at every install. The five cases below were the
        ones that carried it past the 32,767 characters Windows allows a variable:
        "Environment variable name or value is too long", in cases that had nothing to do
        with PATH. A real install calls it a handful of times and is nowhere near.

        So the process copy goes in de-duplicated, which loses nothing and is short, and
        comes out exactly as it was, so the cases after these see what they always saw. #>
    param([string]$Godspeed, [string]$Kit)
    $procPath0 = $env:Path
    try {
        $env:Path = (@($procPath0 -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $UserPath0, 'User')
        Install-KitGodspeedTools -Godspeed $Godspeed -ToolsRepo $Kit 3>&1 4>&1 6>&1 | Out-String
    } finally {
        $env:Path = $procPath0
        try { [Environment]::SetEnvironmentVariable('Path', $UserPath0, 'User') } catch { }
    }
}
function New-ConnectStub {
    <# A stand-in mc-menerio-connect.cmd that reports, and writes down how it was called. #>
    param([string]$HomeDir, [int]$ExitCode = 0)
    $bin = Join-Path $HomeDir '.local\bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $seen = Join-Path $HomeDir 'called.txt'
    @('@echo off',
      ">`"$seen`" echo args=%*",
      ">>`"$seen`" echo cwd=%CD%",
      ">>`"$seen`" echo godspeeddir=%GODSPEED_DIR%",
      'echo Claude Code: connected',
      'echo Hermes: connected',
      'echo Codex: not on this computer',
      'echo a line on stderr 1>&2',
      "exit /b $ExitCode") | Set-Content -Path (Join-Path $bin 'mc-menerio-connect.cmd') -Encoding ascii
    return $seen
}

Check "a launcher that says 'exec node' becomes a .cmd that starts that program with node" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit1' @{
            'mc-menerio-connect' = "#!/bin/sh`nexec node `"`$(dirname `"`$0`")/menerio-connect.js`" `"`$@`"`n"
            'menerio-connect.js'  = "console.log('ran ' + process.argv.slice(2).join(' '))`n"
            'mc-search'          = "#!/bin/sh`nexec node `"`$(dirname `"`$0`")/mc-search-impl.js`" `"`$@`"`n"
            'mc-search-impl.js'  = "// s`n"
        }
        $out = Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed1') -Kit $kit
        $bin = Join-Path $h '.local\bin'
        $c = Get-Content (Join-Path $bin 'mc-menerio-connect.cmd') -Raw
        $s = Get-Content (Join-Path $bin 'mc-search.cmd') -Raw
        # And it really starts, where there is a node to start it with: a .cmd that reads
        # correctly and does nothing when typed is the failure mc-check-keys once had.
        # Run with the short PATH too (see Install-MenerioKit): cmd.exe cannot find node on a
        # PATH of thirty thousand characters, and answers nothing at all.
        $ran = 'ran --check'
        if (Get-Command node -ErrorAction SilentlyContinue) {
            $procPath0 = $env:Path
            try {
                $env:Path = (@($procPath0 -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';')
                $ran = (& (Join-Path $bin 'mc-menerio-connect.cmd') --check 2>$null | Out-String).Trim()
            } finally { $env:Path = $procPath0 }
        }
        $c.Contains('node "%~dp0menerio-connect.js" %*') -and
            $s.Contains('node "%~dp0mc-search-impl.js" %*') -and
            ($ran -eq 'ran --check') -and
            -not $out.Contains('does not have')
    }
}
# THE HALF NEITHER LAUNCHER NAMES. The real programs both start with
# require("./mc-notebook.js"), a module with no launcher and no mc- command of its own. It
# arrives only because the copy takes every file in tools\, so a copy narrowed one day to
# "the programs in the table" would install two commands that cannot start. The case runs
# the installed command, because a file list would not notice.
Check "the module both programs share is installed beside them, so they can start" {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Write-Host "  skip  no node on this PC to start the program with"; return $true }
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit1b' @{
            'mc-menerio-connect' = "#!/bin/sh`nexec node `"`$(dirname `"`$0`")/menerio-connect.js`" `"`$@`"`n"
            'menerio-connect.js'  = "const nb = require('./mc-notebook.js');`nconsole.log(nb.hello + ' ' + process.argv.slice(2).join(' '));`n"
            'mc-notebook.js'     = "module.exports = { hello: 'shared-module-found' };`n"
        }
        [void](Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed1b') -Kit $kit)
        $procPath0 = $env:Path
        try {
            $env:Path = (@($procPath0 -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';')
            $ran = (& (Join-Path $h '.local\bin\mc-menerio-connect.cmd') --check 2>&1 | Out-String).Trim()
        } finally { $env:Path = $procPath0 }
        $ran -eq 'shared-module-found --check'
    }
}
# A KEY MENERIO REFUSES HAD NO WAY OUT: a connected mission control is never asked for a key again. With
# somebody at the keyboard the single step offers to store a new one, and connects again.
Check "with a problem and a reader at the keyboard, a yes stores a new key and connects again" {
    $script:steps = @()
    function Test-KitInteractive { $true }
    function Read-Host { param($Prompt, [switch]$AsSecureString) if ($AsSecureString) { 'a-new-key-not-real-0123456789' } else { $script:steps += "ASKED:$Prompt"; 'y' } }
    function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) }
    function Get-KitNotebookState { 'connected' }
    function Save-KitNotebookToken { param($Godspeed, $Token) $script:steps += "STORED:$($Token.Length)"; $true }
    function Set-KitNotebookEnv { param($Godspeed) $script:steps += 'ENV' }
    function Connect-KitAssistants { param($Godspeed) $script:steps += 'CONNECT'; $global:KbMenerioProblem = (@($script:steps | Where-Object { $_ -eq 'CONNECT' }).Count -eq 1) }
    function Connect-KitNotebook { param($Godspeed, $Token) Connect-KitAssistants -Godspeed $Godspeed }
    $out = Connect-KitMenerioOnly -Godspeed (New-TestDir 'only-newkey') 3>&1 4>&1 6>&1 | Out-String
    (($script:steps -join '|') -eq 'CONNECT|ASKED:Store a new Menerio key? (y/N)|STORED:29|ENV|CONNECT') -and
        $out.Contains('Menerio: connected') -and -not $out.Contains('a-new-key-not-real')
}
Check "a no stores nothing, and with nobody at the keyboard it asks nothing at all" {
    $script:steps = @()
    function Read-Host { param($Prompt, [switch]$AsSecureString) $script:steps += 'ASKED'; 'n' }
    function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) }
    function Get-KitNotebookState { 'connected' }
    function Save-KitNotebookToken { param($Godspeed, $Token) $script:steps += 'STORED'; $true }
    function Connect-KitNotebook { param($Godspeed, $Token) $global:KbMenerioProblem = $true }
    function Test-KitInteractive { $true }
    Connect-KitMenerioOnly -Godspeed (New-TestDir 'only-nokey') 3>&1 4>&1 6>&1 | Out-Null
    $saidNo = (($script:steps -join '|') -eq 'ASKED')
    $script:steps = @()
    function Test-KitInteractive { $false }
    Connect-KitMenerioOnly -Godspeed (New-TestDir 'only-nokey2') 3>&1 4>&1 6>&1 | Out-Null
    $saidNo -and ($script:steps.Count -eq 0)
}
Check "a launcher that is a real shell program goes to Git Bash, never to the bash on PATH" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit2' @{ 'mc-menerio-connect' = "#!/bin/sh`necho hello`n" }
        [void](Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed2') -Kit $kit)
        $c = Get-Content (Join-Path $h '.local\bin\mc-menerio-connect.cmd') -Raw
        $c.Contains((Get-KitGitBash)) -and $c.Contains('%~dp0mc-menerio-connect')
    }
}
Check "a program shipped without its launcher is given one" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit3' @{ 'menerio-connect.js' = "// mc`n" }
        [void](Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed3') -Kit $kit)
        (Get-Content (Join-Path $h '.local\bin\mc-menerio-connect.cmd') -Raw).Contains('node "%~dp0menerio-connect.js" %*')
    }
}
Check "an older book kit is told in one line each that the two are not in it yet, and carries on" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit4' @{ 'mc-notebook-sync' = "#!/bin/sh`nexit 0`n"; 'due.js' = "// due`n" }
        $out = Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed4') -Kit $kit
        $bin = Join-Path $h '.local\bin'
        (([regex]::Matches($out, 'does not have mc-[a-z-]+ yet, so it was skipped')).Count -eq 2) -and
            (Test-Path (Join-Path $bin 'mc-due.cmd')) -and
            -not (Test-Path (Join-Path $bin 'mc-menerio-connect.cmd')) -and
            -not (Test-Path (Join-Path $bin 'mc-search.cmd'))
    }
}
Check "a kit with no notebook programs hears nothing about Menerio" {
    Invoke-NotebookCase {
        param($h)
        $kit = New-MenerioKit 'mc-kit5' @{ 'due.js' = "// due`n" }
        $out = Install-MenerioKit -Godspeed (New-NotebookGodspeed 'mc-godspeed5') -Kit $kit
        -not ($out -match 'mc-menerio-connect|mc-search')
    }
}

Check "an older kit with no connect program still leaves Claude Code its file, and says what is missing" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed6'
        function Get-KitNotebookState { 'connected' }
        $out = Connect-KitAssistants -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
        (Test-Path (Join-Path $godspeed '.mcp.json')) -and
            $out.Contains('cannot connect Hermes and Codex for you yet') -and
            -not ($out -match 'hermes mcp')
    }
}
Check "the connect program runs, is told which mission control three ways, and its report reaches the reader" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed7'
        $seen = New-ConnectStub -HomeDir $h
        function Get-KitNotebookState { 'connected' }
        $godspeedDir0 = $env:GODSPEED_DIR
        $out = Connect-KitAssistants -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
        $called = Get-Content $seen -Raw
        $out.Contains('Claude Code: connected') -and $out.Contains('Hermes: connected') -and
            $out.Contains('Codex: not on this computer') -and
            $called.Contains("args=--godspeed $godspeed") -and $called.Contains("cwd=$godspeed") -and
            $called.Contains("godspeeddir=$godspeed") -and
            ($env:GODSPEED_DIR -eq $godspeedDir0) -and
            (Test-Path (Join-Path $godspeed '.mcp.json'))
    }
}
Check "a line on stderr cannot end the install, even under 'Stop', which is how setup-godspeed.ps1 runs" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed8'
        [void](New-ConnectStub -HomeDir $h)
        function Get-KitNotebookState { 'connected' }
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try { $out = Connect-KitAssistants -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String; $after = $ErrorActionPreference }
        finally { $ErrorActionPreference = $eap }
        $out.Contains('Hermes: connected') -and ($after -eq 'Stop')
    }
}
# The real program prints its whole report and THEN exits 1 when anything failed, a refused
# key included, so the sentence may not say it "stopped early": it did not.
Check "a connect program that reports a problem is heard, in words that fit a refused key" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed9'
        [void](New-ConnectStub -HomeDir $h -ExitCode 1)
        function Get-KitNotebookState { 'connected' }
        $out = Connect-KitAssistants -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
        $out.Contains('found a problem') -and $out.Contains('Hermes: connected') -and
            -not $out.Contains('stopped early') -and ($global:KbMenerioProblem -eq $true)
    }
}
Check "and the single step never says 'connected' straight under that problem" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed9b'
        [void](New-ConnectStub -HomeDir $h -ExitCode 1)
        function Get-KitNotebookState { 'connected' }
        function Test-KitInteractive { $false }   # or a real console would be asked a question
        function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) }
        function Connect-KitNotebook { param($Godspeed, $Token) Connect-KitAssistants -Godspeed $Godspeed }
        $out = Connect-KitMenerioOnly -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
        $out.Contains('your key is stored, and the check above found a problem') -and
            -not $out.Contains('Menerio: connected')
    }
}
Check "a mission control with no key on this PC does not run the connect program" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed10'
        $seen = New-ConnectStub -HomeDir $h
        function Get-KitNotebookState { 'none' }
        Connect-KitAssistants -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        -not (Test-Path $seen)
    }
}
Check "the starter's empty .mcp.json is filled in, and one naming the reader's own server is never touched" {
    Invoke-NotebookCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mc-godspeed11'
        $f = Join-Path $godspeed '.mcp.json'
        Set-KbTextFile -Path $f -Lines @('{', '  "mcpServers": {}', '}')
        Write-KitMcpConfig -Godspeed $godspeed 3>&1 6>&1 | Out-Null
        $filled = (Get-Content $f -Raw).Contains('mcp.menerio.com')
        Set-KbTextFile -Path $f -Lines @('{"mcpServers": {"mine": {"url": "https://example.invalid"}}}')
        Write-KitMcpConfig -Godspeed $godspeed 3>&1 6>&1 | Out-Null
        $filled -and -not (Get-Content $f -Raw).Contains('mcp.menerio.com')
    }
}

if ((Get-Command age -ErrorAction SilentlyContinue) -and (Get-Command age-keygen -ErrorAction SilentlyContinue)) {
    Check "a key just pasted, then a re-run: the connect program runs both times, after the key is stored" {
        # Set-KitNotebookEnv and Protect-KitGodspeedKey are stood in for ON PURPOSE. The first
        # writes every credential in the store into the REAL Windows account's environment,
        # which no fake home can redirect, so an unguarded case here would have replaced
        # the author's own MENERIO_API_KEY with a test string. The second waits for a
        # passphrase at a terminal. The last line proves the real variable never moved.
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-NotebookGodspeed 'mc-godspeed12'
            $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
            $seen = New-ConnectStub -HomeDir $h
            $real0 = [Environment]::GetEnvironmentVariable('MENERIO_API_KEY', 'User')
            function Set-KitNotebookEnv { param($Godspeed) }
            function Protect-KitGodspeedKey { param($Godspeed) $false }
            function Install-KitNotebookSync { param($Godspeed) }
            # The two questions are answered here and have their own cases further down. The
            # task name is a made-up one, so "was this PC already copying" never looks at
            # the real task on the PC running the suite.
            function Request-KitPassphrase { param($Godspeed) }
            function Test-KitNotebookJobHere { $false }
            function Test-KitInteractive { $false }
            $out1 = Connect-KitNotebook -Godspeed $godspeed -Token 'test-token-not-a-real-one-0123456789' 3>&1 4>&1 6>&1 | Out-String
            $ran1 = (Test-Path $seen) -and (Test-Path (Join-Path $godspeed 'secrets\mc-secrets.env.age'))
            Remove-Item $seen -ErrorAction SilentlyContinue
            $out2 = Connect-KitNotebook -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
            $ran1 -and $out1.Contains('Hermes: connected') -and
                -not $out1.Contains('test-token-not-a-real-one') -and
                (Test-Path $seen) -and $out2.Contains('already connected') -and
                ([Environment]::GetEnvironmentVariable('MENERIO_API_KEY', 'User') -eq $real0)
        }
    }
} else {
    Write-Host "  skip  the whole connect step on both roads (age is not on this PC)"
}

Check "age that is already here is not fetched again" {
    function Test-KitAge { $true }
    function Install-KitWingetPackage { throw 'must not fetch' }
    (Install-KitAge) -eq $true
}
Check "a missing age is fetched, at the moment a key needs locking" {
    $script:fetched = ''
    function Test-KitAge { $false }
    function Install-KitWingetPackage { param($Id, $Command, $Human) $script:fetched = $Id; $false }
    $a0 = $env:KB_AGE; $k0 = $env:KB_AGE_KEYGEN
    try { $env:KB_AGE = $null; $env:KB_AGE_KEYGEN = $null; $r = Install-KitAge }
    finally { $env:KB_AGE = $a0; $env:KB_AGE_KEYGEN = $k0 }
    ($r -eq $false) -and ($script:fetched -eq 'FiloSottile.age')
}
Check "a stand-in named by KB_AGE is never 'fixed' by installing the real one" {
    function Test-KitAge { $false }
    function Install-KitWingetPackage { throw 'must not fetch' }
    $a0 = $env:KB_AGE
    try { $env:KB_AGE = 'C:\nonexistent\age.exe'; (Install-KitAge) -eq $false }
    finally { $env:KB_AGE = $a0 }
}

$JoinSrc = Get-Content (Join-Path $PSScriptRoot '..\join.ps1') -Raw
Check "the Menerio question is asked in the new words, and no longer about 'a notebook'" {
    $JoinSrc.Contains('Menerio is optional. Everything in this book works on plain files without it.') -and
        $JoinSrc.Contains('A free account is enough to try it: https://menerio.com/auth?tab=signup') -and
        $JoinSrc.Contains('Read-Host "Connect Menerio now? (y/N)"') -and
        -not $JoinSrc.Contains('Connect a notebook now')
}
Check "and the installer no longer prints a Hermes command for the reader to type" {
    -not ($JoinSrc -match 'Write-Host\s+"[^"]*hermes mcp')
}

Check "THE WAY BACK IN: the single step installs the kit's programs, then connects, and nothing else" {
    $script:steps = @()
    function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) $script:steps += "tools:$ToolsRepo" }
    function Connect-KitNotebook { param($Godspeed, $Token) $script:steps += "connect:skip=[$($env:KB_NOTEBOOK)]" }
    function Get-KitNotebookState { 'none' }
    function Update-KitGodspeed { $script:steps += 'UPDATE' }
    function Install-KitPrereqs { $script:steps += 'PREREQS' }
    function Join-KitMemory { $script:steps += 'MEMORY' }
    function Set-KitHermesGodspeed { $script:steps += 'HERMES' }
    $s0 = $env:KB_NOTEBOOK
    try {
        $env:KB_NOTEBOOK = 'skip'
        $out = Connect-KitMenerioOnly -Godspeed (New-TestDir 'only-godspeed') -ToolsRepo 'kit-url' 3>&1 4>&1 6>&1 | Out-String
        $kept = ($env:KB_NOTEBOOK -eq 'skip')
    } finally { $env:KB_NOTEBOOK = $s0 }
    (($script:steps -join '|') -eq 'tools:kit-url|connect:skip=[]') -and $kept -and
        $out.Contains('not connected. Nothing else on this PC was changed')
}
$SetupSrcM = Get-Content (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Raw
Check "join.ps1 takes -Only, and refuses a step it does not know by name" {
    ($JoinSrc -match '\[string\]\$Only') -and ($JoinSrc -match '-Only knows two steps: menerio and gmail')
}
Check "setup-godspeed.ps1 takes -Only, and runs it before it checks a single prerequisite" {
    $a = $SetupSrcM.IndexOf('Connect-KitMenerioOnly -Godspeed $found')
    $b = $SetupSrcM.IndexOf('$missing = @(Install-KitPrereqs)')
    ($SetupSrcM -match '\[string\]\$Only') -and ($a -gt 0) -and ($b -gt 0) -and ($a -lt $b)
}
Check "-Only survives the library load, which wipes it the same way it wiped -Godspeed" {
    # join.ps1 declares $Only too, and dot-sourcing runs its param block in the caller's
    # scope, so without the save and the restore -Only would always arrive empty and the
    # whole installer would run instead. See $WantGodspeed in setup-godspeed.ps1.
    # The load is matched at the start of a line, because the comment above $WantGodspeed
    # quotes the same words and comes first.
    $save    = $SetupSrcM.IndexOf('$WantOnly = $Only')
    $load    = [regex]::Match($SetupSrcM, '(?m)^\. \$Join -AsLibrary').Index
    $restore = $SetupSrcM.IndexOf('$Only = $WantOnly')
    ($save -gt 0) -and ($save -lt $load) -and ($load -lt $restore)
}

Write-Host ""
Write-Host "-- the copy of the mission control is its own choice, and so is the passphrase"
#
# Twins of the block with the same name in test.sh. Two readers given the Menerio chapter
# cold both refused to connect, for one reason: connecting quietly started copying the whole
# mission control, client notes and patient notes included, into an online account. So the copy is its
# own question with "no" as its answer, recorded per PC as GODSPEED_NOTEBOOK_MIRROR in
# ~\.godspeed\device.env, and the passphrase for a second computer is a question too.
#
# KB_NOTEBOOK_TASK names a task that does not exist for every case here. Without it the
# "was this PC already copying" check would look at the REAL 'Godspeed notebook sync' task, and
# the author's PC has one, so the cases would pass or fail by whose PC they ran on.
$MirrorTask = 'Godspeed notebook sync TEST ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
function Invoke-MirrorCase([scriptblock]$Body) {
    $t0 = $env:KB_NOTEBOOK_TASK; $m0 = $env:KB_NOTEBOOK_MIRROR; $o0 = $env:KB_ONLY_MENERIO; $p0 = $env:KB_NOTEBOOK_PASSPHRASE
    try {
        $env:KB_NOTEBOOK_TASK = $MirrorTask; $env:KB_NOTEBOOK_MIRROR = $null; $env:KB_ONLY_MENERIO = $null; $env:KB_NOTEBOOK_PASSPHRASE = $null
        Invoke-NotebookCase $Body
    } finally {
        Unregister-ScheduledTask -TaskName $MirrorTask -Confirm:$false -ErrorAction SilentlyContinue
        $env:KB_NOTEBOOK_TASK = $t0; $env:KB_NOTEBOOK_MIRROR = $m0; $env:KB_ONLY_MENERIO = $o0; $env:KB_NOTEBOOK_PASSPHRASE = $p0
    }
}
function Get-MirrorLines([string]$HomeDir) {
    $f = Join-Path $HomeDir '.godspeed\device.env'
    if (-not (Test-Path $f)) { return '' }
    return (@(Get-Content $f | Where-Object { $_ -match '^GODSPEED_NOTEBOOK_MIRROR=' }) -join ',')
}
$NewRunner = "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR from device.env before it sends anything`nexit 0"
$OldRunner = "#!/bin/sh`n# an older job: it copies the mission control up whatever anybody said`nexit 0"

Check "the copy is its own question, Enter means no, and the no is written down beside the other lines" {
    Invoke-MirrorCase {
        param($h)
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_DIR=C:\somewhere\godspeed', 'GODSPEED_TOOLS_REPO=kit')
        $script:asked = @()
        function Get-KitNotebookState { 'connected' }
        function Test-KitInteractive { $true }
        function Read-Host { param($Prompt) $script:asked += $Prompt; '' }
        $out = (Select-KitNotebookMirror -Godspeed (New-NotebookGodspeed 'mir1') 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $kept = @(Get-Content (Join-Path $h '.godspeed\device.env') | Where-Object { $_ -eq 'GODSPEED_DIR=C:\somewhere\godspeed' -or $_ -eq 'GODSPEED_TOOLS_REPO=kit' }).Count
        (($script:asked -join '|') -eq "Copy your mission control's files to Menerio for search? (y/N)") -and
            ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=0') -and ($kept -eq 2) -and
            $out.Contains('nothing is copied in either direction') -and
            $out.Contains('nothing is sent to Menerio or fetched from it in the background') -and
            -not ($out.Substring($out.IndexOf('ok: notebook:')).Contains('safety copy'))   # the question names it, the answer must not
    }
}
Check "once answered a full install never asks again, and the Menerio step asks with the old answer as the default" {
    Invoke-MirrorCase {
        param($h)
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_NOTEBOOK_MIRROR=0')
        $script:asked = @()
        function Get-KitNotebookState { 'connected' }
        function Test-KitInteractive { $true }
        function Read-Host { param($Prompt) $script:asked += $Prompt; 'y' }
        $godspeed = New-NotebookGodspeed 'mir2'
        Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $quiet = ($script:asked.Count -eq 0) -and ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=0')
        $env:KB_ONLY_MENERIO = '1'
        $yesOut = (Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $first = ($script:asked[-1] -like '*(y/N)') -and ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=1') -and
                 $yesOut.Contains('copied to Menerio when your mission control saves a version and once an hour. The people and facts Menerio holds for you come down into world/ once an hour')
        function Read-Host { param($Prompt) $script:asked += $Prompt; '' }
        Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $quiet -and $first -and ($script:asked[-1] -like '*(Y/n)') -and ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=1')
    }
}
Check "KB_NOTEBOOK_MIRROR answers it with nobody at the keyboard, and with no answer nothing is written" {
    Invoke-MirrorCase {
        param($h)
        function Get-KitNotebookState { 'connected' }
        function Test-KitInteractive { $false }
        function Read-Host { throw 'must not ask' }
        $godspeed = New-NotebookGodspeed 'mir3'
        Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $nothing = -not (Test-Path (Join-Path $h '.godspeed\device.env'))
        $env:KB_NOTEBOOK_MIRROR = 'yes'
        Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $yes = (Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=1'
        $env:KB_NOTEBOOK_MIRROR = 'no'
        Select-KitNotebookMirror -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $nothing -and $yes -and ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=0')
    }
}
Check "a mission control with no notebook is never asked about a copy" {
    Invoke-MirrorCase {
        param($h)
        function Get-KitNotebookState { 'none' }
        function Test-KitInteractive { $true }
        function Read-Host { throw 'must not ask' }
        $out = Select-KitNotebookMirror -Godspeed (New-NotebookGodspeed 'mir4') 3>&1 4>&1 6>&1 | Out-String
        ($out.Trim() -eq '') -and -not (Test-Path (Join-Path $h '.godspeed\device.env'))
    }
}
Check "THE MIGRATION: a PC that was already copying is written down as 1 without being asked, and one line says so" {
    Invoke-MirrorCase {
        param($h)
        function Get-KitNotebookState { 'connected' }
        function Test-KitNotebookJobHere { $true }
        function Test-KitInteractive { $true }
        function Read-Host { throw 'must not ask' }
        $out = (Select-KitNotebookMirror -Godspeed (New-NotebookGodspeed 'mir5') 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        ((Get-MirrorLines $h) -eq 'GODSPEED_NOTEBOOK_MIRROR=1') -and
            $out.Contains("was already copying your mission control's files to Menerio for search, so that stays on")
    }
}
Check "and 'already copying' means the hourly task really is registered, by the name a test can change" {
    Invoke-MirrorCase {
        param($h)
        $before = Test-KitNotebookJobHere
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0'
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(5)
        Register-ScheduledTask -TaskName $MirrorTask -Action $action -Trigger $trigger -Force | Out-Null
        (-not $before) -and (Test-KitNotebookJobHere)
    }
}

Check "after a no the job is still installed, and nothing describes it as Menerio copying, in either direction" {
    Invoke-MirrorCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mir6'
        git -C $godspeed init -q 2>&1 | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $h '.local\bin\mc-notebook-sync'), $NewRunner)
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_NOTEBOOK_MIRROR=0')
        # Out-String folds a long line at the width of the window, so the fold is taken out again
        # before a sentence is looked for. Without it this case passes or fails by window size.
        $out = (Install-KitNotebookSync -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $no = (Test-Path (Join-Path $godspeed '.git\hooks\post-commit')) -and [bool](Get-ScheduledTask -TaskName $MirrorTask -ErrorAction SilentlyContinue) -and
              $out.Contains('It copies nothing to Menerio and fetches nothing from it') -and
              -not ($out -match '(?i)updates the notebook|copies your mission control|safety copy|down into world')
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_NOTEBOOK_MIRROR=1')
        $out2 = (Install-KitNotebookSync -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $no -and $out2.Contains("copies your mission control's files up to Menerio and brings your people and facts down into world/")
    }
}
Check "A NO HAS TO BE A NO: an older job that always copies is taken out, a reader's own hook is not" {
    Invoke-MirrorCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'mir7'
        git -C $godspeed init -q 2>&1 | Out-Null
        $runner = Join-Path $h '.local\bin\mc-notebook-sync'
        $hook = Join-Path $godspeed '.git\hooks\post-commit'
        # First a yes with the older job: scheduled as it always was.
        [System.IO.File]::WriteAllText($runner, $OldRunner)
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_NOTEBOOK_MIRROR=1')
        Install-KitNotebookSync -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $was = (Test-Path $hook) -and [bool](Get-ScheduledTask -TaskName $MirrorTask -ErrorAction SilentlyContinue)
        # Then the reader says no.
        Set-Content (Join-Path $h '.godspeed\device.env') @('GODSPEED_NOTEBOOK_MIRROR=0')
        $out = (Install-KitNotebookSync -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $gone = -not (Test-Path $hook) -and -not (Get-ScheduledTask -TaskName $MirrorTask -ErrorAction SilentlyContinue)
        # A computer nobody has asked yet is a no as well, and a hook the reader wrote stays.
        Remove-Item (Join-Path $h '.godspeed\device.env') -Force
        New-Item -ItemType Directory -Force (Split-Path $hook) | Out-Null
        Set-Content $hook "#!/bin/sh`n# mine"
        Install-KitNotebookSync -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $was -and $gone -and $out.Contains("always copies your mission control's files to Menerio, and you have not said yes to that") -and
            (Get-Content $hook -Raw).Contains('# mine') -and -not (Get-ScheduledTask -TaskName $MirrorTask -ErrorAction SilentlyContinue)
    }
}

Check "the passphrase is a question, Enter means no, and a no says the key is stored for this computer" {
    Invoke-MirrorCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'pass1'
        $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
        Set-Content $env:GODSPEED_AGE_KEY 'x'
        $script:asked = @(); $script:sealed = 0
        function Test-KitInteractive { $true }
        function Read-Host { param($Prompt) $script:asked += $Prompt; '' }
        function Protect-KitGodspeedKey { param($Godspeed) $script:sealed++; $true }
        $out = (Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $no = (($script:asked -join '|') -eq 'Set a passphrase for a second computer now? (y/N)') -and ($script:sealed -eq 0) -and
              $out.Contains('your key is stored for this computer. For a second computer later, run the Menerio step again')
        function Read-Host { param($Prompt) 'y' }
        Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $no -and ($script:sealed -eq 1)
    }
}
Check "nobody at the keyboard is a quiet no, and KB_NOTEBOOK_PASSPHRASE answers without asking, both ways" {
    Invoke-MirrorCase {
        param($h)
        $godspeed = New-NotebookGodspeed 'pass2'
        $env:GODSPEED_AGE_KEY = Join-Path $h '.godspeed\age-key.txt'
        Set-Content $env:GODSPEED_AGE_KEY 'x'
        $script:sealed = 0
        function Read-Host { throw 'must not ask' }
        function Protect-KitGodspeedKey { param($Godspeed) $script:sealed++; $true }
        function Test-KitInteractive { $false }
        $out = (Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String) -replace '\s+', ' '
        $quiet = ($script:sealed -eq 0) -and $out.Contains('stored for this computer') -and -not ($out -match 'WARNING')
        function Test-KitInteractive { $true }
        $env:KB_NOTEBOOK_PASSPHRASE = 'skip'
        Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $skip = ($script:sealed -eq 0)
        $env:KB_NOTEBOOK_PASSPHRASE = 'ask'
        Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $ask = ($script:sealed -eq 1)
        Set-Content (Join-Path $godspeed 'secrets\mc-key.age') 'x'
        $script:sealed = 0
        $done = (Request-KitPassphrase -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String).Trim() -eq ''
        $quiet -and $skip -and $ask -and $done -and ($script:sealed -eq 0)
    }
}
Check "a connected mission control with no passphrase is left in peace, and only the Menerio step offers one again" {
    Invoke-MirrorCase {
        param($h)
        $script:steps = @()
        function Get-KitNotebookState { 'connected' }
        function Request-KitPassphrase { param($Godspeed) $script:steps += 'PASSPHRASE' }
        function Write-KitExpiryRecord { param($Godspeed) }
        function Write-KitDueFolder { param($Godspeed) }
        function Set-KitNotebookEnv { param($Godspeed) }
        function Connect-KitAssistants { param($Godspeed) $script:steps += 'ASSISTANTS' }
        function Select-KitNotebookMirror { param($Godspeed) $script:steps += 'MIRROR' }
        function Install-KitNotebookSync { param($Godspeed) $script:steps += 'JOB' }
        function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) }
        function Copy-KitStarterGodspeed { }
        $godspeed = New-NotebookGodspeed 'pass3'
        Connect-KitNotebook -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        $full = ($script:steps -join '|')
        $script:steps = @()
        Connect-KitMenerioOnly -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-Null
        ($full -eq 'ASSISTANTS|MIRROR|JOB') -and (($script:steps -join '|') -eq 'PASSPHRASE|ASSISTANTS|MIRROR|JOB') -and
            (-not $env:KB_ONLY_MENERIO)
    }
}
Check "the first question no longer promises that the whole mission control becomes searchable" {
    $src = Get-Content (Join-Path $PSScriptRoot '..\join.ps1') -Raw
    -not $src.Contains('Your whole mission control also') -and $src.Contains('Copying them for search is a second question')
}

Write-Host ""
Write-Host "-- one skills room, and the installer proves it wired something"
#
# THE BUG THESE EXIST FOR. Until 2026-09-01 both installers junctioned .agents\skills to
# .claude\skills whenever .claude\skills existed. On a mission control whose recipes live in the
# visible skills\ room, which is the arrangement the book teaches, the starter top-up had
# just created .claude\skills EMPTY, so every non-Claude assistant was pointed at an empty
# folder while six recipes sat unreachable, under a green tick. Measured on a real
# reader-shaped mission control during Run 2, not imagined.
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

# A Windows path is the reason the JSON has to be escaped at all: C:\godspeed\skills goes out
# as C:\\godspeed\\skills or Hermes reads a path full of escape sequences.
Check "a Windows path goes into the JSON with its backslashes doubled" {
    (ConvertTo-KbJsonString 'C:\godspeed\skills') -eq '"C:\\godspeed\\skills"'
}

# Which room is the real one. Detected, never assumed.
Check "the visible room wins when it holds the recipes" {
    $d = New-TestDir 'sk-visible'
    Add-Recipes (Join-Path $d 'skills') @('a')
    New-Item -ItemType Directory -Force (Join-Path $d '.claude\skills') | Out-Null
    (Get-KitSkillsRoom -Godspeed $d) -eq (Join-Path $d 'skills')
}
Check "a Claude-era mission control keeps its recipes where they are" {
    $d = New-TestDir 'sk-claudeera'
    Add-Recipes (Join-Path $d '.claude\skills') @('a')
    (Get-KitSkillsRoom -Godspeed $d) -eq (Join-Path $d '.claude\skills')
}
Check "a brand new mission control is given the visible room" {
    $d = New-TestDir 'sk-new'
    (Get-KitSkillsRoom -Godspeed $d) -eq (Join-Path $d 'skills')
}

# The merge. `hermes config set` REPLACES a list, so this is how a reader loses a team
# folder they added themselves.
Check "an entry already in external_dirs survives, and the mission control's room is added after it" {
    Set-KbTextFile -Path $SkLog -Lines @()
    $script:SkMergeDir = New-TestDir 'sk-merge'
    Add-Recipes (Join-Path $script:SkMergeDir 'skills') @('a')
    Connect-KitSkills -Godspeed $script:SkMergeDir 3>&1 6>&1 | Out-Null
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
    Connect-KitSkills -Godspeed $script:SkMergeDir 3>&1 6>&1 | Out-Null
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
          $txt = (Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Out-String)
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
    Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Out-Null
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
    $r = Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Select-Object -Last 1
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
    Connect-KitSkills -Godspeed $script:SkD1 3>&1 6>&1 | Out-Null
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
Check "exactly one real skills folder exists in the mission control" {
    (@(Get-RealSkillsFolders -Root $script:SkD1)).Count -eq 1
}

# A mission control whose recipes really do live in .claude\skills must not be fed to itself. Getting
# this wrong copies a folder into itself and then moves it aside.
Check "a Claude-era mission control keeps its three recipes" {
    $script:SkD2 = New-TestDir 'sk-aj'
    Add-Recipes (Join-Path $script:SkD2 '.claude\skills') @('x', 'y', 'z')
    Connect-KitSkills -Godspeed $script:SkD2 3>&1 6>&1 | Out-Null
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
    Connect-KitSkills -Godspeed $script:SkD3 3>&1 6>&1 | Out-Null
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
    Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Out-Null
    ((Get-KitRecipeCount (Join-Path $d 'elsewhere')) -eq 2) -and
        ((Get-KitRecipeCount (Join-Path $d '.agents\skills')) -eq 3)
}

# Twice equals once, or re-running the installer is a thing people fear.
Check "a second run changes nothing on disk" {
    $d = New-TestDir 'sk-twice'
    Add-Recipes (Join-Path $d 'skills') @('a')
    Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Out-Null
    $before = (@(Get-ChildItem -LiteralPath $d -Recurse -Force -Name | Sort-Object) -join "`n")
    Connect-KitSkills -Godspeed $d 3>&1 6>&1 | Out-Null
    $after  = (@(Get-ChildItem -LiteralPath $d -Recurse -Force -Name | Sort-Object) -join "`n")
    $before -eq $after
}

# A real folder with real work standing where the link belongs is never deleted.
Check "a recipe found in the hidden folder is carried into the visible room" {
    $script:SkD5 = New-TestDir 'sk-carry'
    Add-Recipes (Join-Path $script:SkD5 'skills') @('mine')
    Add-Recipes (Join-Path $script:SkD5 '.claude\skills') @('theirs')
    Connect-KitSkills -Godspeed $script:SkD5 3>&1 6>&1 | Out-Null
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
# WHAT THESE GUARD. The kit shipped `hermes config set workspace "$GODSPEED"`, which is not a
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
    # PowerShell BY ABSOLUTE PATH, and it has to be. The Install-KitGodspeedTools cases
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

function Invoke-GodspeedCase {
    <#  Run Set-KitHermesGodspeed and hand back both halves: everything it said, and what it
        returned. The return value is last on the pipeline, after the prints. #>
    param([string]$Godspeed)
    $all = @(Set-KitHermesGodspeed -Godspeed $Godspeed 3>&1 6>&1)
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
                 'Invoke-KitHermesOneShot', 'Test-KitHermesReadsGodspeed', 'Set-KitHermesGodspeed') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}

$GodspeedOk = New-TestDir 'hermescwd-godspeed'
$HubRes = Invoke-GodspeedCase -Godspeed $GodspeedOk

Check "terminal.cwd is set to the mission control's absolute path" {
    (Get-Content -LiteralPath $env:STUB_CWDFILE -Raw).Trim() -eq (Get-KitRealPath $GodspeedOk)
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
        '*[[]Read the file .mc-reachable-check in your current folder and reply with its contents and nothing else.[]]*'
}
Check "the proof asks for the file by a RELATIVE name, or it proves nothing" {
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]Read the file ?:\*')
}
Check "the marker file is not left behind in the reader's mission control" {
    -not (Test-Path -LiteralPath (Join-Path $GodspeedOk '.mc-reachable-check'))
}
Check "a second run does not set terminal.cwd again" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    Invoke-GodspeedCase -Godspeed $GodspeedOk | Out-Null
    -not ((Get-Content -LiteralPath $env:STUB_LOG -Raw) -like '*[[]set[]] [[]terminal.cwd[]]*')
}

# THE CASE THAT MATTERS MOST. The setting reads back perfectly and the agent still
# cannot open the folder. Before this check that shipped as a green tick.
Check "an agent that ignores terminal.cwd is caught, not congratulated" {
    $env:STUB_MODE = 'ignore'
    $script:IgnoreRes = Invoke-GodspeedCase -Godspeed (New-TestDir 'hermescwd-ignored')
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
    $script:IgnoreRes.Text -like '*File not found: .mc-reachable-check*'
}

# A PROVIDER FAILURE IS NOT A FOLDER FAILURE, and telling a reader their mission control is half
# connected because their model is misconfigured is the workspace lie pointed the other
# way. Found by running the installer on hardware: the test server's account default was a
# model its own subscription cannot serve, so every one-shot came back HTTP 400 and the
# installer blamed terminal.cwd.
Check "a one-shot that reached no model is unreachable, not a failed read" {
    $env:STUB_MODE = 'http400'
    $script:UnreachRes = Invoke-GodspeedCase -Godspeed (New-TestDir 'hermescwd-nomodel')
    $r = Test-KitHermesReadsGodspeed -Godspeed (New-TestDir 'hermescwd-nomodel2')
    $env:STUB_MODE = ''
    $r -eq 'unreachable'
}
Check "and that is not reported as a broken mission control, but as a provider problem" {
    $script:UnreachRes.Ok -and
        ($script:UnreachRes.Text -like '*provider problem and not a folder problem*') -and
        ($script:UnreachRes.Text -like '*HTTP 400*') -and
        -not ($script:UnreachRes.Text -like '*could not read a file*')
}
Check "a missing inference provider is unreachable, not a broken folder" {
    # Hermes 0.20.0's wording for the same condition. A credential can be present
    # (a gh CLI token is auto-detected as one) while no model is configured, so
    # the credential gate passes and only this net catches it. Measured on the
    # book's own rehearsal server, where the miss called a wired mission control broken.
    $env:STUB_MODE = 'noprovider'
    $r = Test-KitHermesReadsGodspeed -Godspeed (New-TestDir 'hermescwd-noprov')
    $env:STUB_MODE = ''
    $r -eq 'unreachable'
}

# A parrot passes nothing. The token lives only in the file, never in the prompt, so an
# agent that echoes the prompt straight back cannot fake a read.
Check "an agent that only echoes the prompt back does not count as reading the file" {
    $env:STUB_MODE = 'parrot'
    $r = Test-KitHermesReadsGodspeed -Godspeed (New-TestDir 'hermescwd-parrot')
    $env:STUB_MODE = ''
    $r -eq 'no'
}

# A first install, before the reader has signed in anywhere. Crying wolf here is how an
# installer teaches people to ignore it.
Check "no provider yet is not a failure, and the setting still lands" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    [System.IO.File]::Delete($env:STUB_CWDFILE)
    $env:STUB_NO_CREDENTIAL = '1'
    $r = Invoke-GodspeedCase -Godspeed (New-TestDir 'hermescwd-nocred')
    $log = Get-Content -LiteralPath $env:STUB_LOG -Raw
    $env:STUB_NO_CREDENTIAL = ''
    $r.Ok -and ($log -like '*[[]set[]] [[]terminal.cwd[]]*') -and -not ($log -like '*[[]-z[]]*')
}
Check "a folder cannot be proved readable with no credential" {
    $env:STUB_NO_CREDENTIAL = '1'
    $r = Test-KitHermesReadsGodspeed -Godspeed (New-TestDir 'hermescwd-nocred2')
    $env:STUB_NO_CREDENTIAL = ''
    $r -eq 'unavailable'
}

# The escape hatch, for the test matrix and for a reader on a metered plan.
Check "KB_SKIP_GODSPEED_PROOF spends no request but still sets the folder" {
    Set-KbTextFile -Path $env:STUB_LOG -Lines @()
    [System.IO.File]::Delete($env:STUB_CWDFILE)
    $env:KB_SKIP_GODSPEED_PROOF = '1'
    $r = Invoke-GodspeedCase -Godspeed (New-TestDir 'hermescwd-skip')
    $log = Get-Content -LiteralPath $env:STUB_LOG -Raw
    $env:KB_SKIP_GODSPEED_PROOF = ''
    $r.Ok -and ($log -like '*[[]set[]] [[]terminal.cwd[]]*') -and -not ($log -like '*[[]-z[]]*')
}

Check "a folder that is not there is unavailable, not a failed read" {
    (Test-KitHermesReadsGodspeed -Godspeed (Join-Path $CwdRoot 'no-such-godspeed')) -eq 'unavailable'
}
Check "no Hermes on the PC is not a failure, and it says so plainly" {
    $keep = $env:KB_HERMES_BIN
    $env:KB_HERMES_BIN = Join-Path $CwdRoot 'bin\no-such-hermes.cmd'
    $r = Invoke-GodspeedCase -Godspeed $GodspeedOk
    $env:KB_HERMES_BIN = $keep
    $r.Ok -and ($r.Text -like '*Hermes is not on this PC yet*')
}

foreach ($v in 'KB_HERMES_BIN', 'STUB_LOG', 'STUB_CWDFILE', 'STUB_ELSEWHERE', 'STUB_MODE',
                'STUB_NO_CREDENTIAL', 'KB_SKIP_GODSPEED_PROOF') {
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

# Prove the run never left its own folder before putting the real home back, because an
# assertion after the restore would be checking the restore and not the run.
Check "THE SUITE NEVER TOUCHED THE REAL HOME: its home stayed inside its temp folder" {
    $HOME.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)
}
Check "and the real GODSPEED_DIR user variable is exactly what it was before the run" {
    [Environment]::GetEnvironmentVariable('GODSPEED_DIR', 'User') -eq $GodspeedDir0
}

# The real home back, and the GODSPEED_DIR variable with it. See $Home0 at the top.
try {
    Set-Variable -Name HOME -Value $Home0 -Scope Global -Force
    $env:HOME = $EnvHome0
    $env:KB_HOME = $KbHome0
    if ([Environment]::GetEnvironmentVariable('GODSPEED_DIR', 'User') -ne $GodspeedDir0) {
        [Environment]::SetEnvironmentVariable('GODSPEED_DIR', $GodspeedDir0, 'User')
    }
} catch { }

# --- WHERE A GODSPEED MAY GO (D-179, 2026-09-02) -------------------------------------------
# Twins of the cases in test.sh. The default is the top of the user folder; the folders
# OneDrive backs up are refused with a sentence; C:\godspeed stays allowed as the power option.
foreach ($fn in 'Get-KitDefaultGodspeedDir', 'Get-KitCloudSyncedParents', 'Get-KitGodspeedPathRefusal') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}
Check "the default is the top of the user folder" {
    (Get-KitDefaultGodspeedDir) -eq (Join-Path $HOME 'godspeed')
}
Check "the user folder itself is allowed" {
    $null -eq (Get-KitGodspeedPathRefusal -Path (Join-Path $HOME 'godspeed'))
}
Check "the drive root stays allowed, as the power option" {
    $null -eq (Get-KitGodspeedPathRefusal -Path 'C:\godspeed')
}
foreach ($k in 'MyDocuments', 'Desktop', 'MyPictures', 'MyMusic', 'MyVideos') {
    $base = [Environment]::GetFolderPath($k)
    if (-not $base) { continue }
    $p = Join-Path $base 'godspeed'
    Check "$k is refused ($p)" { [bool](Get-KitGodspeedPathRefusal -Path $p) }.GetNewClosure()
}
Check "deeper inside Documents is still refused" {
    [bool](Get-KitGodspeedPathRefusal -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'work\godspeed'))
}
Check "a folder merely named like one is allowed" {
    $null -eq (Get-KitGodspeedPathRefusal -Path (Join-Path $HOME 'Documents-old\godspeed'))
}
Check "the refusal says where to go instead" {
    (Get-KitGodspeedPathRefusal -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'godspeed')) -like "*$(Get-KitDefaultGodspeedDir)*"
}
$od0 = $env:OneDrive
try {
    $env:OneDrive = New-TestDir 'onedrive-root'
    Check "a path typed straight into the OneDrive root is refused" {
        [bool](Get-KitGodspeedPathRefusal -Path (Join-Path $env:OneDrive 'godspeed'))
    }
} finally { $env:OneDrive = $od0 }
Check "Find-KitGodspeed looks in the user folder before the drive root" {
    $src = (Get-Command Find-KitGodspeed).ScriptBlock.ToString()
    $src.IndexOf("(Join-Path `$HOME 'godspeed')") -lt $src.IndexOf("'C:\godspeed'")
}

# --- A SECOND GODSPEED BESIDE THE FIRST (2026-09-03) ---------------------------------------
# Twins of the cases in test.sh. Exactly five things on a Windows account answer "which
# mission control does this computer work from": the GODSPEED_DIR line in device.env, the GODSPEED_DIR user
# environment variable, the two scheduled jobs, and Hermes' terminal.cwd. A beside run
# takes none of them, and everything else it wires is either inside the mission control folder or
# keyed by the mission control's path. Before this existed, a second mission control took all five and the first
# mission control's daily jobs went quiet with nothing on screen to say so.
foreach ($fn in 'Test-KitBeside', 'Test-KitSamePath') {
    Check "$fn is defined" { [bool](Get-Command $fn -ErrorAction SilentlyContinue) }.GetNewClosure()
}
Check "beside is off unless it is asked for" {
    $b0 = $env:KB_BESIDE
    try { $env:KB_BESIDE = $null; -not (Test-KitBeside) } finally { $env:KB_BESIDE = $b0 }
}
Check "beside is on at exactly 1, and nothing else turns it on" {
    $b0 = $env:KB_BESIDE
    try {
        $env:KB_BESIDE = '1';    $on  = Test-KitBeside
        $env:KB_BESIDE = 'true'; $off = Test-KitBeside
        $on -and -not $off
    } finally { $env:KB_BESIDE = $b0 }
}
Check "the same folder spelled two ways is one folder" {
    $d = New-TestDir 'same-a'
    (Test-KitSamePath $d ($d + '\')) -and (Test-KitSamePath $d $d.ToUpper())
}
Check "two folders are two folders, and a missing side is never a match" {
    (-not (Test-KitSamePath (New-TestDir 'same-b') (New-TestDir 'same-c'))) -and
    (-not (Test-KitSamePath '' (New-TestDir 'same-d')))
}
Check "beside leaves the GODSPEED_DIR line in device.env exactly as it was" {
    $b0 = $env:KB_BESIDE
    try {
        $env:KB_HOME = New-TestDir 'beside-home'
        $env:KB_BESIDE = '1'
        New-Item -ItemType Directory -Force (Join-Path $env:KB_HOME '.godspeed') | Out-Null
        $f = Join-Path $env:KB_HOME '.godspeed\device.env'
        Set-Content $f "GODSPEED_DIR=C:\godspeed`nGODSPEED_PROMPT_SOURCES=claude"
        $before = Get-Content $f -Raw
        Set-KitGodspeedDirRecord -Godspeed (New-TestDir 'beside-godspeed') | Out-Null
        (Get-Content $f -Raw) -eq $before
    } finally { $env:KB_HOME = $null; $env:KB_BESIDE = $b0 }
}
Check "beside schedules no daily job, so the first mission control keeps the only one" {
    $b0 = $env:KB_BESIDE
    $task = 'Godspeed prompt archive BESIDE TEST'
    try {
        $env:KB_HOME = New-TestDir 'beside-harvest-home'
        $godspeed = New-TestDir 'beside-harvest-godspeed'
        New-Item -ItemType Directory -Force (Join-Path $godspeed 'bin') | Out-Null
        Set-Content (Join-Path $godspeed 'bin\prompt-harvest.js') 'console.log(1)'
        $env:KB_BESIDE = '1'
        Install-KitPromptHarvest -Godspeed $godspeed -TaskName $task | Out-Null
        -not (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
    } finally {
        $env:KB_HOME = $null; $env:KB_BESIDE = $b0
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "beside still gives THIS mission control its own save hook, because that lives inside it" {
    $b0 = $env:KB_BESIDE
    $task = 'Godspeed notebook sync BESIDE TEST'
    try {
        Invoke-NotebookCase {
            param($h)
            $godspeed = New-TestDir 'beside-nb-godspeed'
            git -C $godspeed init -q
            Set-Content (Join-Path $h '.local\bin\mc-notebook-sync') "#!/bin/sh`n# reads GODSPEED_NOTEBOOK_MIRROR`nexit 0"
            $env:KB_BESIDE = '1'
            Install-KitNotebookSync -Godspeed $godspeed -TaskName $task | Out-Null
            $hook = Join-Path $godspeed '.git\hooks\post-commit'
            (Test-Path $hook) -and
                ((Get-Content $hook -Raw).Contains('mc-notebook-sync')) -and
                -not (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
        }
    } finally {
        $env:KB_BESIDE = $b0
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "beside leaves Hermes pointing where it was, and says so" {
    $b0 = $env:KB_BESIDE
    try {
        $env:KB_BESIDE = '1'
        $godspeed = New-TestDir 'beside-hermes-godspeed'
        $out = Set-KitHermesGodspeed -Godspeed $godspeed 3>&1 4>&1 6>&1 | Out-String
        $out -like '*left Hermes pointing where it was*'
    } finally { $env:KB_BESIDE = $b0 }
}

# The installer's own half, read as text: these five lines are the whole contract, and a
# refactor that drops one of them puts the collision back without failing anything above.
$SetupSrc = Get-Content (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Raw
Check "the installer takes -Beside" { $SetupSrc -match '\[switch\]\$Beside' }
Check "the missing-code canary is the newest function, Show-KitGmailRetired" {
    $SetupSrc -match "Get-Command Show-KitGmailRetired -ErrorAction SilentlyContinue"
}
Check "the GODSPEED_DIR user variable is written only when this mission control is the one in charge" {
    $SetupSrc -match "if \(-not \(Test-KitBeside\)\) \{[^}]*SetEnvironmentVariable\('GODSPEED_DIR'"
}
Check "-Beside without -Godspeed stops rather than guessing a folder" {
    $SetupSrc -match '-Beside needs -Godspeed as well'
}
Check "-Beside with no mission control to sit beside stops and says to run it plain" {
    $SetupSrc -match 'nothing for a second one to sit beside'
}
Check "THE BUG: asking for one mission control while this PC works from another now stops" {
    # Until 2026-09-03 this silently brought the OTHER mission control up to date under a green
    # tick, and the folder actually asked for was never made. Find-KitGodspeed reads
    # $env:GODSPEED_DIR before it looks anywhere else, which is why -Godspeed alone could never
    # reach a folder that did not exist yet.
    ($SetupSrc -match 'already works from \$found') -and ($SetupSrc -match 'add -Beside')
}
Check "and Find-KitGodspeed really does read GODSPEED_DIR before the usual homes" {
    $src = (Get-Command Find-KitGodspeed).ScriptBlock.ToString()
    $src.IndexOf('$env:GODSPEED_DIR') -lt $src.IndexOf("(Join-Path `$HOME 'godspeed')")
}

# The clickable wizard's half, read as text. It cannot be driven from a test, so what is
# checked is the contract: the page exists, the box starts empty so the common path is
# still one click, the folder page opens when it is ticked, and the flag reaches the run.
$IssSrc = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
Check "the wizard asks before making a second mission control" { $IssSrc -match 'BesidePage := CreateInputOptionPage' }
Check "and the box starts unticked, so a returning reader still just clicks Next" {
    $IssSrc -match 'BesidePage\.Values\[0\] := False'
}
Check "the page is not shown on a PC with no mission control to sit beside" {
    $IssSrc -match "if PageID = BesidePage\.ID then\s+Result := \(FoundGodspeed = ''\)"
}
Check "the folder page opens when the box is ticked, and stays skipped when it is not" {
    $IssSrc -match "Result := \(FoundGodspeed <> ''\) and \(not Beside\)"
}
Check "a second mission control may not be the folder this PC already works from" {
    $IssSrc -match 'cannot sit beside itself'
}
Check "and the flag actually reaches setup-godspeed.ps1" {
    ($IssSrc -match 'function GetBesideFlag') -and ($IssSrc -match '\{code:GetBesideFlag\}')
}

# --- GIT CHATTER MUST NOT ABORT THE INSTALLER (2026-09-03) -----------------------------
# setup-godspeed.ps1 runs under $ErrorActionPreference = 'Stop', and PowerShell 7.3+ turns any
# line a native program writes to stderr into a terminating error. git writes ordinary
# progress there. "Applied autostash." stopped a real run dead, halfway through the wiring,
# on a mission control whose only sin was an edited file nobody had committed yet. That is every reader
# who has written something in their mission control.
Check "Invoke-KitGit is defined" { [bool](Get-Command Invoke-KitGit -ErrorAction SilentlyContinue) }
Check "THE REGRESSION: a mission control with uncommitted work still finishes its update" {
    $bare = New-TestDir 'dirty-remote'
    $work = New-TestDir 'dirty-godspeed'
    git init --bare -q $bare
    git init -q $work
    Set-Content (Join-Path $work 'README.md') 'one'
    git -C $work add -A 2>&1 | Out-Null
    git -C $work -c user.email='t@t' -c user.name='t' commit -q -m first 2>&1 | Out-Null
    git -C $work remote add origin $bare 2>&1 | Out-Null
    git -C $work push -q origin HEAD 2>&1 | Out-Null
    # The edited file that used to be fatal: --autostash then says "Applied autostash." on
    # stderr, and the run died there rather than reaching a single wiring step.
    Set-Content (Join-Path $work 'README.md') 'one, edited and not committed'
    $threw = $false
    try {
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        Update-KitGodspeed -Godspeed $work | Out-Null
    } catch { $threw = $true } finally { $ErrorActionPreference = $eap }
    # And the reader's uncommitted edit is still there, which is the whole reason for
    # --autostash in the first place.
    (-not $threw) -and ((Get-Content (Join-Path $work 'README.md') -Raw).Contains('edited and not committed'))
}

# --- -Godspeed HAS TO SURVIVE THE LIBRARY LOAD (2026-09-03) ---------------------------------
# join.ps1 is a script in its own right as well as setup-godspeed.ps1's library, so it has its
# own param block, and that block declares [string]$Godspeed. Dot-sourcing runs a param block in
# the CALLER'S scope, so `. $Join -AsLibrary` set $Godspeed back to $null and threw away whatever
# -Godspeed the installer was given. -Godspeed therefore never worked on Windows, on any run, and
# nothing said so: with $Godspeed empty, Find-KitGodspeed detected the machine's existing mission control and the
# common case looked perfect. It surfaced as "-Beside needs -Godspeed as well" on a command line
# that plainly had one. The bash twin loads a library with no param block and never had it.
Check "THE MECHANISM: dot-sourcing the library really does wipe a caller's Godspeed" {
    $lib = Join-Path $PSScriptRoot '..\join.ps1'
    $after = & {
        $Godspeed = 'C:\typed-by-the-user'
        . $lib -AsLibrary
        $Godspeed
    }
    # If this ever comes back as the typed path, the library stopped declaring -Godspeed and the
    # guard in setup-godspeed.ps1 can go. Until then the guard is load-bearing.
    [string]::IsNullOrEmpty($after)
}
Check "so the installer saves -Godspeed before the load and puts it back after" {
    ($SetupSrc -match '\$WantGodspeed = \$Godspeed') -and ($SetupSrc -match '\$Godspeed = \$WantGodspeed')
}
Check "and it puts it back AFTER both dot-sources, not between them" {
    $save    = $SetupSrc.IndexOf('$WantGodspeed = $Godspeed')
    $restore = $SetupSrc.IndexOf('$Godspeed = $WantGodspeed')
    $lastDot = $SetupSrc.LastIndexOf('-AsLibrary')
    ($save -lt $lastDot) -and ($lastDot -lt $restore)
}

# --- A SHIM RUNS THE PROGRAM'S OWN INTERPRETER (2026-09-03) -----------------------------
# Every .cmd this writes said `bash "<file>" %*` until today, and 18 of the mission control's own
# commands are Python or Node. bash handed a file as an argument does not honour its
# shebang, it reads it as bash, so `hub-check-voice` answered "import: command not found"
# and all 18 were broken when typed by name. Unnoticed because the `hub` dispatcher runs its
# siblings through its own interpreter, never through these shims. No bash twin:
# kb_install_godspeed_cli makes symlinks and chmods them, and a kernel reads a shebang.
Check "Get-KitPython is defined" { [bool](Get-Command Get-KitPython -ErrorAction SilentlyContinue) }
Check "and the python it names actually runs, not a Store stub that opens a shop" {
    $p = Get-KitPython
    if (-not $p) { return $true }   # a PC with no Python is a real answer, and it says so
    $eap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $v = (& $p --version 2>&1 | Out-String)
        ($LASTEXITCODE -eq 0) -and ($v -match 'Python')
    } finally { $ErrorActionPreference = $eap }
}
Check "a bash command still gets bash, a python one python, a node one node" {
    $godspeed = New-TestDir 'shim-godspeed'
    $cli = Join-Path $godspeed 'agents\hub-cli'
    New-Item -ItemType Directory -Force $cli | Out-Null
    Set-Content (Join-Path $cli 'hub')          "#!/usr/bin/env bash`necho hi"
    Set-Content (Join-Path $cli 'hub-pytool')  "#!/usr/bin/env python3`nprint(1)"
    Set-Content (Join-Path $cli 'hub-nodetool') "#!/usr/bin/env node`nconsole.log(1)"
    $home0 = $HOME
    try {
        $h = New-TestDir 'shim-home'
        $env:HOME = $h
        Set-Variable -Name HOME -Value $h -Scope Global -Force
        Install-KitGodspeedCli -Godspeed $godspeed | Out-Null
        $bin = Join-Path $h '.local\bin'
        $b = (Get-Content (Join-Path $bin 'hub.cmd') -Raw)
        $p = (Get-Content (Join-Path $bin 'hub-pytool.cmd') -Raw)
        $nd = (Get-Content (Join-Path $bin 'hub-nodetool.cmd') -Raw)
        ($b -match 'bash') -and
        ($p -notmatch 'bash') -and ($p -match 'py') -and
        ($nd -notmatch 'bash') -and ($nd -match 'node')
    } finally {
        Set-Variable -Name HOME -Value $home0 -Scope Global -Force
        $env:HOME = $home0
    }
}

# --- WINDOWS PINS A TAG NOW, LIKE ITS TWIN (2026-09-04) --------------------------------
# install-godspeed.sh has always pinned an immutable tag and says why: this book's readers get
# exactly the code that passed its end-to-end runs. setup-godspeed.ps1 defaulted to the moving v2
# branch, so the two platforms made different promises and only one was written down. On
# 2026-09-03 six pushes to v2 reached every Windows reader who ran the installer, hours
# before the release describing them existed, while macOS and Linux stayed on the old tag.
$IssSrc2   = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
$BuildSrc  = Get-Content (Join-Path $PSScriptRoot 'build-installer.ps1') -Raw
Check "the wizard carries a pin, and it is a tag rather than the moving branch" {
    ($IssSrc2 -match '#define\s+KbPin\s+"(v[0-9]+\.[0-9]+(\.[0-9]+)?)"')
}
Check "the wizard also carries its own version" { $IssSrc2 -match '#define\s+AppVersion\s+"[0-9]' }
Check "the install run is given the pin" {
    ($IssSrc2 -split "`n" | Where-Object { $_ -match 'setup-godspeed\.ps1.*-NoPause' } |
        Where-Object { $_ -match '-KbBranch' }).Count -eq 1
}
Check "and so is the Start Menu updater, or a reader who clicks it floats after all" {
    ($IssSrc2 -split "`n" | Where-Object { $_ -match 'setup-godspeed\.ps1' -and $_ -notmatch '-NoPause' -and $_ -match 'Parameters:' } |
        Where-Object { $_ -match '-KbBranch' }).Count -ge 1
}
Check "setup-godspeed.ps1 takes -KbBranch, and an explicit one beats the environment" {
    ($SetupSrc -match '\[string\]\$KbBranch') -and
    ($SetupSrc -match 'if \(-not \$KbBranch\) \{ \$KbBranch = if \(\$env:KB_BRANCH\)')
}
Check "a developer with no pin still gets the moving branch, which is what they want" {
    $SetupSrc -match "else \{ 'v2' \}"
}
Check "THE GATE: the build refuses a pin that is not a tag naming the commit being built" {
    ($BuildSrc -match 'no such tag exists here') -and
    ($BuildSrc -match '\$pinnedAt -ne \$head') -and
    ($BuildSrc -match 'uncommitted changes')
}
Check "and the build reads git without git being able to kill it" {
    # build-installer.ps1 also runs under 'Stop', and `git rev-parse` on a tag that does not
    # exist yet writes to stderr. It killed the build instead of reporting the missing pin.
    ($BuildSrc -match 'function git0') -and ($BuildSrc -notmatch '\(git rev-parse HEAD')
}

# THE MAIL TOOL (2026-09-21, email plan). Every install and re-run tells each assistant about
# mc-mail and connects no mailbox. Uses the REAL kit files from a teach-it-once-kit checkout
# beside this one, because the promise is about the real program: one ordinary PC, nothing
# asked, nothing connected, "not connected" is not an error, and a second run changes nothing.
$MailSrc = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'teach-it-once-kit\tools'
if ((Test-KitCommand 'node') -and (Test-Path (Join-Path $MailSrc 'mc-mail.js'))) {
    Write-Host "-- the mail tool"
    $mailGodspeed = New-TestDir 'mail-godspeed'
    $mailBin = Join-Path $SuiteHome '.local\bin'
    foreach ($f in 'mc-mail.js', 'mc-mail-gmail.js', 'mc-mail-wire.js', 'mc-mail-imap.js', 'mc-mail-pair.js', 'mc-mail-himalaya.json') { Copy-Item (Join-Path $MailSrc $f) $mailBin -Force }
    Set-Content -Path (Join-Path $mailGodspeed 'AGENTS.md') -Value '# mission control' -Encoding ascii
    Set-Content -Path (Join-Path $mailGodspeed '.mcp.json') -Value '{"mcpServers":{"notebook":{"type":"http","url":"https://mcp.menerio.com"}}}' -Encoding ascii
    # Earlier cases put KB_HOME back to the real one; this case needs the suite's own home.
    $kbhome0 = $env:KB_HOME; $env:KB_HOME = $SuiteHome
    $codex0 = $env:CODEX_HOME; $hermes0 = $env:HERMES_HOME; $up0 = $env:USERPROFILE
    $env:CODEX_HOME = New-TestDir 'mail-codex'; $env:HERMES_HOME = New-TestDir 'mail-hermes'; $env:USERPROFILE = $SuiteHome
    Set-Content -Path (Join-Path $env:HERMES_HOME 'config.yaml') -Value "model: x`nmcp_servers:`n  notebook:`n    url: https://mcp.menerio.com" -Encoding ascii
    try {
        $out1 = Connect-KitMail -Godspeed $mailGodspeed 6>&1 | Out-String
        $out2 = Connect-KitMail -Godspeed $mailGodspeed 6>&1 | Out-String
        $mcp = Get-Content (Join-Path $mailGodspeed '.mcp.json') -Raw
        Check "the mail tool is added to Claude Code, Codex and Hermes, keeping what was there" {
            $mcp.Contains('mc-mail') -and $mcp.Contains('notebook') -and
                (Get-Content (Join-Path $env:CODEX_HOME 'config.toml') -Raw).Contains('mc-mail') -and
                (Get-Content (Join-Path $env:HERMES_HOME 'config.yaml') -Raw).Contains('mc-mail:')
        }.GetNewClosure()
        Check "a second run changes nothing" { ([regex]::Matches($out2, 'already has the mail tool')).Count -eq 3 }.GetNewClosure()
        Check "installing it asked nothing and connected nothing" { -not ($out1 -match 'Client ID|password|Connected:') }.GetNewClosure()
        $launch = (ConvertFrom-Json $mcp).mcpServers.'mc-mail'.args[1]
        $godspeedDir0 = $env:GODSPEED_DIR; $env:GODSPEED_DIR = $mailGodspeed; $env:GODSPEED_MAIL_HOME = $SuiteHome
        $st = & node -e $launch status 2>&1 | Out-String; $rc = $LASTEXITCODE
        $env:GODSPEED_DIR = $godspeedDir0; Remove-Item Env:GODSPEED_MAIL_HOME -ErrorAction SilentlyContinue
        Check "the entry every assistant is given starts the tool on Windows, and 'not connected' is not an error" {
            ([regex]::Matches($st, 'not connected')).Count -eq 2 -and $rc -eq 0
        }.GetNewClosure()
    } finally {
        $env:CODEX_HOME = $codex0; $env:HERMES_HOME = $hermes0; $env:USERPROFILE = $up0; $env:KB_HOME = $kbhome0
        foreach ($f in 'mc-mail.js', 'mc-mail-gmail.js', 'mc-mail-wire.js', 'mc-mail-imap.js', 'mc-mail-pair.js', 'mc-mail-himalaya.json') { Remove-Item (Join-Path $mailBin $f) -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "  skip  the mail tool case (needs node and a teach-it-once-kit checkout beside this one)"
}

# =============================================================================
# THE GMAIL STEP, RETIRED (2026-09-22). Email is connected by asking an assistant, so an
# install and "Update my mission control" ask nothing about it, and -Only gmail refreshes the mail tool
# and the recipes and then SAYS the old step is retired. test.sh compares the words with
# the bash twin.
# =============================================================================
Write-Host ""
Write-Host "-- the Gmail step, retired"
Check "-Only gmail refreshes the programs and the recipes, tells the assistants, says it is retired, and runs nothing else" {
    $script:steps = @()
    function Install-KitGodspeedTools { param($Godspeed, $ToolsRepo) $script:steps += "tools:$ToolsRepo" }
    function Copy-KitStarterGodspeed { param($Path, $StarterRepo, $StarterPath) $script:steps += "recipes:$StarterRepo" }
    function Connect-KitMail { param($Godspeed) $script:steps += 'wire' }
    function Update-KitGodspeed { $script:steps += 'UPDATE' }
    function Install-KitPrereqs { $script:steps += 'PREREQS' }
    function Connect-KitNotebook { $script:steps += 'MENERIO' }
    function Read-Host { throw 'must not ask' }
    $out = Connect-KitGmailOnly -Godspeed (New-TestDir 'gmail-only') -ToolsRepo 'kit-url' 3>&1 4>&1 6>&1 | Out-String
    (($script:steps -join '|') -eq 'tools:kit-url|recipes:kit-url|wire') -and
        $out.Contains('is retired, and nothing was changed') -and $out.Contains('Connect Gmail for me')
}
$SetupSrcG = Get-Content (Join-Path $PSScriptRoot 'setup-godspeed.ps1') -Raw
Check "setup-godspeed.ps1 runs -Only gmail before it checks a single prerequisite" {
    $a = $SetupSrcG.IndexOf('Connect-KitGmailOnly -Godspeed $found')
    $b = $SetupSrcG.IndexOf('$missing = @(Install-KitPrereqs)')
    ($a -gt 0) -and ($b -gt 0) -and ($a -lt $b)
}
Check "an install and 'Update my mission control' never ask about Gmail" {
    -not $SetupSrcG.Contains('Request-KitGmail -Godspeed')
}
Check "the Start menu entry a reader clicks is still there, and still runs the whole installer" {
    $iss = Get-Content (Join-Path $PSScriptRoot 'godspeed-setup.iss') -Raw
    $iss.Contains('Name: "{group}\Update my mission control"') -and -not ($iss -match 'Update my mission control[^\n]*\n[^\n]*-Only')
}
Check "the old offer is silent even with a person at the keyboard" {
    function Test-KitInteractive { $true }
    function Read-Host { throw 'must not ask' }
    $out = Request-KitGmail -Godspeed (New-TestDir 'gmail-offer') 3>&1 4>&1 6>&1 | Out-String
    -not $out.Trim()
}
Check "this file carries none of the Google console sentences, and tells no reader to type mc-mail connect gmail" {
    $code = ($JoinSrc -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    -not ($JoinSrc -match 'Client ID|Client secret|Is this the one|Connect Gmail now') -and -not $code.Contains('mc-mail connect gmail')
}

# THE REAL PATH, PUT BACK ONCE MORE, AND THIS TIME LAST. The restore further up was written
# when it was the end of the file. Cases were added below it afterwards, and one of them
# (the shim case, with its own shim-home) installs the mission control commands, which prepends its bin
# folder to the persisted user PATH. So every run since left exactly one dead
# ...\kb-test-xxxxxxxx\shim-home\.local\bin behind for good: 16 of them were found on the
# author's PC on 2026-09-20, which is the same slow road to "Environment variable name or
# value is too long" that the note at the top of this file describes.
try { [Environment]::SetEnvironmentVariable('Path', $UserPath0, 'User') } catch { }
Check "THE SUITE LEFT THE REAL PATH AS IT FOUND IT: no temporary folder of this run is in it" {
    -not ([Environment]::GetEnvironmentVariable('Path', 'User') -like "*$Root*")
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
