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
    New-Item -ItemType Directory -Force (Join-Path $Path 'memory') | Out-Null
    Set-Content (Join-Path $Path 'memory\MEMORY.md') '# Memory index'
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
                 'Install-KitPromptHarvest', 'Install-KitHubTools') {
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
    (Test-KitHub $d) -and (Test-Path (Join-Path $d 'AGENTS.md')) -and (Test-Path (Join-Path $d 'memory\MEMORY.md'))
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
    (Test-Path (Join-Path $d 'context\about-me.md')) -and (Test-Path (Join-Path $d 'skills\plan-my-day.md'))
}
Check "the starter's own AGENTS.md wins, no invented one overwrites it" {
    (Get-Content (Join-Path $Root 'fromstarter\AGENTS.md') -Raw).Contains('the real one')
}
Check "the starter's own memory index is kept, not replaced by a blank one" {
    $sr = Join-Path $Root 'starter-src'
    New-Item -ItemType Directory -Force (Join-Path $sr 'starter-hub\memory') | Out-Null
    Set-Content (Join-Path $sr 'starter-hub\memory\MEMORY.md') '# Memory index -- the product wrote this'
    git -C $sr add -A 2>&1 | Out-Null
    git -C $sr -c user.email='t@t' -c user.name='t' commit -q -m 'memory' 2>&1 | Out-Null
    $d = Join-Path $Root 'keepindex'
    New-KitHub -Path $d -StarterRepo $sr | Out-Null
    (Get-Content (Join-Path $d 'memory\MEMORY.md') -Raw).Contains('the product wrote this')
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
    foreach ($f in 'AGENTS.md', 'context\about-me.md', 'context\people.md', 'context\voice.md',
                    'procedures.md', 'decisions.md', 'memory\MEMORY.md', 'skills\plan-my-day.md') {
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
Write-Host "-- the memory link, which is the point of the whole thing"
Check "the memory path is derived from the hub folder" {
    (Get-KitMemoryLinkPath -Hub 'C:\hub') -eq (Join-Path $HOME '.claude\projects\c--hub\memory')
}
Check "linking a hub makes a junction that points back at it" {
    $d = Join-Path $Root 'linkme'
    New-KitHub -Path $d | Out-Null
    Join-KitMemory -Hub $d | Out-Null
    $link = Get-KitMemoryLinkPath -Hub $d
    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    $ok = $item -and $item.LinkType -and ((Resolve-Path (@($item.Target)[0])).Path -eq (Resolve-Path (Join-Path $d 'memory')).Path)
    if ($item) { (Get-Item $link -Force).Delete() }
    Remove-Item (Split-Path $link -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    $ok
}
Check "a memory already in the old place is carried over, never lost" {
    $d = Join-Path $Root 'carry'
    New-KitHub -Path $d | Out-Null
    $link = Get-KitMemoryLinkPath -Hub $d
    New-Item -ItemType Directory -Force $link | Out-Null
    Set-Content (Join-Path $link 'precious.md') 'do not lose me'
    Join-KitMemory -Hub $d 3>$null | Out-Null
    $carried = Test-Path (Join-Path $d 'memory\precious.md')
    $kept    = @(Get-ChildItem (Split-Path $link -Parent) -Directory | Where-Object { $_.Name -like 'memory.replaced-*' }).Count -gt 0
    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) { (Get-Item $link -Force).Delete() }
    Remove-Item (Split-Path $link -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    $carried -and $kept
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

Write-Host ""
Write-Host "-- the daily job that files what you type to an AI"
# Added 2026-08-10. The hub keeps a drawer of everything its owner has typed to an
# assistant, and filling it needs a job on each machine. Nothing installed that job:
# one computer had one because somebody typed it into that computer's schedule by
# hand, and every other computer quietly kept nothing. These are the Windows twins of
# the cases in test.sh. When you change one side, change both.
$TaskForTests = 'Hub prompt archive TEST'
Check "a hub with no harvester stays quiet" {
    $bare = New-TestDir 'noharvest'
    $out = Install-KitPromptHarvest -Hub $bare -TaskName $TaskForTests 3>&1 4>&1 | Out-String
    ($out.Trim() -eq '') -and -not (Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue)
}
Check "a hub with a harvester gets a job that runs it, and only once a day" {
    $hub = New-TestDir 'harvest'
    New-Item -ItemType Directory -Force (Join-Path $hub 'bin') | Out-Null
    Set-Content (Join-Path $hub 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        $task = Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue
        $args = if ($task) { ($task.Actions | ForEach-Object { $_.Arguments }) -join ' ' } else { '' }
        [bool]$task -and ($args -match 'prompt-harvest\.js') -and ($args -match '--once-a-day')
    } finally {
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Check "running the installer twice does not stack up two jobs" {
    $hub = New-TestDir 'harvest2'
    New-Item -ItemType Directory -Force (Join-Path $hub 'bin') | Out-Null
    Set-Content (Join-Path $hub 'bin\prompt-harvest.js') 'console.log(1)'
    try {
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        Install-KitPromptHarvest -Hub $hub -TaskName $TaskForTests | Out-Null
        @(Get-ScheduledTask -TaskName $TaskForTests -ErrorAction SilentlyContinue).Count -eq 1
    } finally {
        Unregister-ScheduledTask -TaskName $TaskForTests -Confirm:$false -ErrorAction SilentlyContinue
    }
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
