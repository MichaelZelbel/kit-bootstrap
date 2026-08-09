# =============================================================================
# kit-bootstrap / join.ps1   -   "I already have a hub. This Windows PC is another machine."
#
# The Windows half of join.sh. It exists because the CREATE installer in the
# book's kit only runs on a rented Linux server, which left every reader working
# on a Windows laptop with no way to join their own hub. Michael hit the same gap
# on 2026-08-09, one day before a business trip.
#
# Self-contained on purpose: a Windows reader downloads one file and runs it. It
# does not need lib.sh, which is bash.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File join.ps1 [C:\path\to\your\hub]
#
# Or dot-source it to reuse the one function (this is how the hub's own device
# bootstrap calls it, so the wiring lives in ONE place per D-092):
#   . .\join.ps1 -AsLibrary ; Join-KitMemory -Hub 'C:\hub'
#
# Safe to run as many times as you like. It never deletes a memory.
# Junctions, not symlinks: a junction needs no administrator rights on Windows.
# =============================================================================
param(
    [string]$Hub,
    [switch]$AsLibrary
)

function Write-KbOk   { param($m) Write-Host "   ok: $m" }
function Write-KbWarn { param($m) Write-Warning $m }
function Write-KbSay  { param($m) Write-Host "`n== $m" -ForegroundColor Cyan }

function Set-KbTextFile {
    <#  Write a text file as UTF-8 with no byte-order mark.

        Not `Set-Content -Encoding utf8NoBOM`, which only exists in PowerShell 7.
        Windows ships 5.1 and that is what a double-clicked installer runs under,
        so anything here that 7 alone understands fails on the machine of every
        person who has not gone looking for a newer PowerShell.

        AllowEmptyString is not decoration. A mandatory [string[]] refuses an array
        holding a blank line, and every one of these files is prose with blank
        lines in it, so without it this function rejects its only real input. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines = @()
    )
    [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UTF8Encoding($false)))
    if (-not (Test-Path $Path)) { throw "could not write $Path" }
}

# raw.githubusercontent.com refuses anything below TLS 1.2, and Windows PowerShell
# 5.1 still defaults to older ones. Without this line every download here fails
# with a connection error that names nothing useful.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Get-KitMemoryLinkPath {
    <#  Where Claude Code keeps the memory for this hub folder. Derived from the
        path, never typed in, so it still works when the hub sits somewhere else
        on the next machine. #>
    param([Parameter(Mandatory)][string]$Hub)
    $mangled = ($Hub -replace '[^a-zA-Z0-9]', '-').ToLower()
    Join-Path $HOME ".claude\projects\$mangled\memory"
}

function Initialize-KitMemoryIndex {
    param([Parameter(Mandatory)][string]$Hub)
    $mem = Join-Path $Hub 'memory'
    New-Item -ItemType Directory -Force $mem | Out-Null
    $idx = Join-Path $mem 'MEMORY.md'
    if (Test-Path $idx) { return }
    $lines = @(
        '# Memory index'
        ''
        'This is what your assistants have learned about you and your work, one file per'
        'fact, and this page is the list of them. Your assistant reads this list at the'
        'start of a session and opens only the files it needs, so the list stays small'
        'and the facts stay out of the way until they matter.'
        ''
        'It lives in your hub folder rather than inside one AI tool, so every assistant'
        'on every one of your machines reads the same memory.'
        ''
        'One line per memory, like this:'
        ''
        '- [What it is](some-fact.md) - the short version, so a session can tell whether to open it'
    )
    Set-KbTextFile -Path $idx -Lines $lines
    Write-KbOk "memory: created the index at $idx"
}

function Join-KitMemory {
    <#  Point the assistant's private memory folder at the hub's memory/ folder,
        so one memory is shared by every machine and every assistant. #>
    param([Parameter(Mandatory)][string]$Hub)

    $mem  = Join-Path $Hub 'memory'
    $link = Get-KitMemoryLinkPath -Hub $Hub
    Initialize-KitMemoryIndex -Hub $Hub

    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        # A link pointing at the WRONG hub is the failure that looks like success:
        # the assistant keeps writing memories into a folder nobody syncs any more.
        $target = @($item.Target)[0]
        if ($target -and ((Resolve-Path $target -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $mem).Path)) {
            Write-KbOk "memory: already shared with $mem"
            return
        }
        Write-KbWarn "memory: the link pointed at $target, not at this hub. Repointing it."
        (Get-Item $link -Force).Delete()
    }
    elseif ($item) {
        # Real memories from before this ran. Carry them in, then move the folder
        # aside with a timestamp. Never delete: a memory nobody can get back is the
        # one thing this whole design exists to prevent.
        Get-ChildItem $link -File | Where-Object { -not (Test-Path (Join-Path $mem $_.Name)) } |
            ForEach-Object { Copy-Item $_.FullName $mem; Write-KbOk "memory: carried over $($_.Name)" }
        $stash = "$link.replaced-$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item $link $stash
        Write-KbOk "memory: your old folder is kept at $stash (delete it once you are happy)"
    }

    New-Item -ItemType Directory -Force (Split-Path $link -Parent) | Out-Null
    New-Item -ItemType Junction -Path $link -Target $mem | Out-Null
    Write-KbOk "memory: $link now points at $mem, so every machine shares it"
}

# =============================================================================
# FINDING A HUB THAT IS ALREADY HERE, AND PUTTING ITS COMMANDS WITHIN REACH
#
# Added 2026-08-09. `hub map` on the Windows work PC answered with a file path
# from the rented server, and fixing the tool itself only got halfway: there was
# no `hub` command on that machine at all. The server has one because its deploy
# script copies the tools into /usr/local/bin. Nothing did the same for a laptop.
# =============================================================================

function Test-KitHub {
    <#  Is this a hub, or just a folder called hub? Checked before every answer so
        discovery cannot hand back an empty directory that matched on its name. #>
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path (Join-Path $Dir '.git'))) { return $false }
    return ((Test-Path (Join-Path $Dir 'memory')) -or (Test-Path (Join-Path $Dir 'AGENTS.md')) -or
            (Test-Path (Join-Path $Dir 'CLAUDE.md')))
}

function Find-KitHub {
    <#  The hub already installed on this machine, or $null. A machine that has one
        knows where it is in more than one way, so look before asking the reader.
        Plain foreach loops on purpose: `return` inside a ForEach-Object only ends
        that one item, so a pipeline here would keep searching after it had won. #>
    param([string]$Hint)

    foreach ($c in @($Hint, $env:HUB_DIR, $env:HUB)) {
        if (Test-KitHub $c) { return (Resolve-Path $c).Path }
    }
    # A machine joined once before already told us: the assistant's memory folder is
    # a junction straight into the hub. Read where it points. The folder's own name is
    # no help - every one of : \ . and a space became the same dash on the way in.
    $projects = @(Get-ChildItem (Join-Path $HOME '.claude\projects') -Directory -ErrorAction SilentlyContinue)
    foreach ($p in $projects) {
        $item = Get-Item (Join-Path $p.FullName 'memory') -Force -ErrorAction SilentlyContinue
        if (-not $item -or -not $item.LinkType) { continue }
        $t = @($item.Target)[0]
        if (-not $t) { continue }
        $d = Split-Path $t -Parent
        if (Test-KitHub $d) { return (Resolve-Path $d).Path }
    }

    foreach ($c in @('C:\hub', (Join-Path $HOME 'hub'), (Join-Path $HOME 'Documents\hub'),
                     (Join-Path $HOME 'dev\hub'))) {
        if (Test-KitHub $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Update-KitHub {
    <#  Bring an existing installation up to date. Never fatal: a machine with no
        network should still finish wiring itself and just say it is behind. #>
    param([Parameter(Mandatory)][string]$Hub)
    if (-not (Test-Path (Join-Path $Hub '.git'))) {
        Write-KbWarn "$Hub is not a git folder, so there is nothing to pull. Continuing."
        return
    }
    $branch = (git -C $Hub rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $branch -or $branch -eq 'HEAD') { $branch = 'main' }
    git -C $Hub pull --rebase --autostash -q origin $branch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-KbOk "updated your hub to $(git -C $Hub log -1 --format='%h %s' 2>$null)"
    } else {
        Write-KbWarn "could not pull (no network, or a conflict to sort out by hand). Continuing with the copy already on this machine, which may be out of date."
    }
}

function Get-KitGitBash {
    <#  `bash` on the Windows PATH is normally the WSL launcher, and WSL cannot open
        C:\hub\... the way these tools expect - it sees /mnt/c. Git Bash is the one
        that can. git is already a prerequisite, so derive it from where git is
        rather than trusting whatever PATH resolves. #>
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $root = Split-Path (Split-Path $git -Parent) -Parent
        foreach ($rel in 'bin\bash.exe', 'usr\bin\bash.exe') {
            $c = Join-Path $root $rel
            if (Test-Path $c) { return $c }
        }
    }
    foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe")) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Install-KitHubCli {
    <#  Put the hub's own commands on this machine's PATH.

        ALL of them, not just `hub`. `hub memory search` is a wrapper that runs
        `hub-memory-lookup` by bare name, so a PATH holding only `hub` gives you a
        command that exists and then fails, which is the worst of the three states.
        Quiet on a hub that ships no tools, which is every reader's hub. #>
    param([Parameter(Mandatory)][string]$Hub)

    $src = Join-Path $Hub 'agents\hub-cli'
    if (-not (Test-Path (Join-Path $src 'hub'))) { return }

    $bash = Get-KitGitBash
    if (-not $bash) {
        Write-KbWarn "could not find Git Bash, so the hub commands were NOT installed. Install Git for Windows (winget install --id Git.Git) and run this again."
        return
    }

    $bin = Join-Path $HOME '.local\bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $n = 0
    Get-ChildItem $src -File |
        Where-Object { ($_.Name -eq 'hub' -or $_.Name -like 'hub-*') -and $_.Extension -notin '.env', '.md' } |
        ForEach-Object {
            $target = $_.FullName -replace '\\', '/'
            @('@echo off', "`"$bash`" `"$target`" %*") |
                Set-Content -Path (Join-Path $bin "$($_.Name).cmd") -Encoding ascii
            $n++
        }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $bin) {
        $joined = if ($userPath) { "$bin;$userPath" } else { $bin }
        [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
        Write-KbOk "added $bin to your PATH (open a new terminal for it to take)"
    }
    $env:Path = "$bin;$env:Path"
    Write-KbOk "commands: $n hub tools now run from anywhere, e.g. hub map lovable"
}

# =============================================================================
# THE THINGS A WINDOWS PC NEEDS BEFORE ANY OF THE ABOVE CAN WORK
#
# Added 2026-08-09. Everything above assumes git is already on the machine and an
# assistant is already installed. On a rented Linux server that is true, because
# the CREATE installer put them there. On somebody's own Windows laptop it is
# usually false, and until now the answer was "go install three things by hand
# first", which is not an installer, it is homework.
# =============================================================================

function Test-KitCommand { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Update-KitPath {
    <#  Re-read PATH from the registry into this process.

        A program installed one line ago is invisible to the next line without
        this: Windows hands every process its PATH at birth and never updates it.
        That is the difference between an installer that works and one that tells
        you to close the window and start again. #>
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user, $env:Path) | Where-Object { $_ }) -join ';'
}

function Install-KitWingetPackage {
    <#  Install one package with Windows' own package manager, quietly.
        Returns $true only when the command it provides is reachable afterwards,
        because "winget exited 0" and "the tool is usable" are not the same claim. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Human
    )
    if (Test-KitCommand $Command) { Write-KbOk "$Human is already here"; return $true }

    if (-not (Test-KitCommand 'winget')) {
        Write-KbWarn "$Human is missing and this PC has no App Installer, so I cannot fetch it. Install $Human by hand, then run this again."
        return $false
    }

    Write-Host "   installing $Human (this can take a few minutes)..."
    # --silent keeps the vendor's own wizard from popping up behind ours. The two
    # agreement flags stop winget stopping to ask a question nobody is there to answer.
    winget install --id $Id --exact --silent --disable-interactivity `
        --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    Update-KitPath

    if (Test-KitCommand $Command) { Write-KbOk "$Human installed"; return $true }
    Write-KbWarn "$Human did not become usable after installing it. Sign out and in again, or install it by hand."
    return $false
}

function Install-KitClaudeCode {
    <#  The assistant itself. Anthropic ships a Windows installer of their own, so
        use that rather than inventing a second way to install their product. #>
    if (Test-KitCommand 'claude') { Write-KbOk "Claude Code is already here"; return $true }

    Write-Host "   installing Claude Code..."
    $script = Join-Path $env:TEMP 'claude-install.ps1'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://claude.ai/install.ps1' -OutFile $script -ErrorAction Stop
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script 2>&1 | Out-Null
    } catch {
        Write-KbWarn "could not fetch the Claude Code installer: $($_.Exception.Message)"
        return $false
    }
    # Its own install folder, in case PATH has not caught up inside this process.
    $env:Path = "$(Join-Path $HOME '.local\bin');$env:Path"
    Update-KitPath

    if (Test-KitCommand 'claude') { Write-KbOk "Claude Code installed"; return $true }
    Write-KbWarn "Claude Code did not become usable. Open a new terminal and run: claude --version"
    return $false
}

function Install-KitPrereqs {
    <#  Everything the hub needs on a Windows PC. Reports what is still missing
        instead of stopping, because a half-wired machine that says which half is
        far more useful than one that quit on the first problem. #>
    Write-KbSay "Checking what this PC needs"
    $missing = @()

    # git: the hub IS a git folder, and Git for Windows also brings Git Bash,
    # which is what the hub's own commands run under.
    if (-not (Install-KitWingetPackage -Id 'Git.Git' -Command 'git' -Human 'Git')) { $missing += 'Git' }
    # node: several hub tools are node programs (calling another machine's AI, for one).
    if (-not (Install-KitWingetPackage -Id 'OpenJS.NodeJS.LTS' -Command 'node' -Human 'Node.js')) { $missing += 'Node.js' }
    if (-not (Install-KitClaudeCode)) { $missing += 'Claude Code' }

    return $missing
}

function Copy-KitStarterHub {
    <#  Lay down a product's real starter folder, fetched from its own public
        repository.

        This function exists because of a bug worth remembering. The first version
        of New-KitHub INVENTED a hub: a short AGENTS.md written from scratch and an
        empty memory index. Meanwhile the book's kit already ships `starter-hub/`,
        a proper one with context/, skills/, procedures.md, decisions.md, inbox/
        and prompts/, which the chapters then walk the reader through filling in.
        So a reader who installed on a fresh PC would have got a folder that did
        not match the book they were holding, and every instruction like "open
        context/about-me.md" would have failed on a file that was not there.

        Nothing here may invent content that a product already ships. Generic on
        purpose: the caller says which repository and which folder, so this stays
        the shared floor rather than one book's private helper. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StarterRepo,
        [string]$StarterPath = 'starter-hub'
    )

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("kit-starter-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        git clone --depth 1 --quiet $StarterRepo $tmp 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }

        $src = Join-Path $tmp $StarterPath
        if (-not (Test-Path $src)) { return $false }

        New-Item -ItemType Directory -Force $Path | Out-Null
        # -Force so hidden files come too, and never overwriting: a second run must
        # not tread on a sentence the person has already written about themselves.
        Get-ChildItem $src -Force | ForEach-Object {
            $dest = Join-Path $Path $_.Name
            if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest -Recurse -Force }
        }
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-KitHub {
    <#  There is no hub on this PC. Make one.

        Two shapes, because people arrive in two states: they already keep a hub
        in a git repository somewhere and this is simply another machine, or they
        have nothing at all and today is day one.

        On day one the folder is copied from the product's own starter, never
        written from imagination. See Copy-KitStarterHub for what that cost us. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$RepoUrl,
        [string]$StarterRepo,
        [string]$StarterPath = 'starter-hub'
    )

    if (Test-Path $Path) {
        $hasFiles = @(Get-ChildItem $Path -Force -ErrorAction SilentlyContinue).Count -gt 0
        if ($hasFiles -and -not (Test-KitHub $Path)) {
            throw "$Path already exists and has things in it, but it is not a hub. Pick an empty folder, or one that does not exist yet."
        }
    }

    if ($RepoUrl) {
        Write-KbSay "Getting your hub from $RepoUrl"
        New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
        git clone $RepoUrl $Path
        if ($LASTEXITCODE -ne 0) {
            throw "Could not copy that repository. If it is a private one, sign in first (run: gh auth login) and try again. The address I tried was $RepoUrl"
        }
        Write-KbOk "your hub is now at $Path"
        return
    }

    Write-KbSay "Starting a new hub at $Path"
    New-Item -ItemType Directory -Force $Path | Out-Null

    $gotStarter = $false
    if ($StarterRepo) {
        Write-Host "   fetching the starter folder..."
        $gotStarter = Copy-KitStarterHub -Path $Path -StarterRepo $StarterRepo -StarterPath $StarterPath
        if ($gotStarter) {
            Write-KbOk "your hub starts with the real starter folder, the one the book fills in chapter by chapter"
        } else {
            # Loud, and with the way out in the same breath. A hub of the wrong
            # shape sends somebody looking for files the book names and they do
            # not have, which is a worse hour than being told plainly here.
            Write-KbWarn @"
I could not fetch the starter folder from $StarterRepo
so I am making a bare hub instead. It works, but it does NOT have the files the
book walks you through (context/, skills/, procedures.md and the rest).
To put that right: open $StarterRepo in a browser, use the green Code button ->
Download ZIP, and copy the starter-hub folder from inside it into $Path
"@
        }
    }

    if (-not (Test-Path (Join-Path $Path '.git'))) {
        git -C $Path init -q
        if ($LASTEXITCODE -ne 0) { throw "Could not start a git folder at $Path." }
    }
    Initialize-KitMemoryIndex -Hub $Path
    if ($gotStarter) { Write-KbOk "your hub is now at $Path"; return }

    $agents = Join-Path $Path 'AGENTS.md'
    if (-not (Test-Path $agents)) {
        $starter = @(
            '# My hub'
            ''
            'This folder is the brain my AI assistants share. Every assistant on every one'
            'of my machines reads this file first, so what I write here is what all of them'
            'know about how I want to work.'
            ''
            '## What is in here'
            ''
            '- `memory/` - what the assistants have learned about me, one file per fact.'
            '  `memory/MEMORY.md` is the list of them.'
            '- Anything else I want them to have: notes about me, about my work, about the'
            '  things I am building.'
            ''
            '## Keeping it on my other machines'
            ''
            'This folder is a git folder, so it travels the ordinary way: commit, push, and'
            'run the same installer on the next machine.'
        )
        Set-KbTextFile -Path $agents -Lines $starter
        Write-KbOk "wrote a starter $agents for you to make your own"
    }
    Write-KbOk "your hub is now at $Path"
}

if ($AsLibrary) { return }

# ---------------------------------------------------------------- run standalone
# Which hub? A machine that has one already knows where it is, so look before asking.
$Hub = Find-KitHub -Hint $Hub
if (-not $Hub) {
    Write-Error "I could not find a hub on this machine. I looked where you pointed me, at the folder your assistant's memory is linked to, and in the usual places (C:\hub, $HOME\hub). If yours is somewhere else, pass the path: join.ps1 C:\path\to\your\hub . If you have not got one yet, clone it first, then run this again."
    exit 1
}

Write-KbSay "Joining this machine to the hub at $Hub"

# Get the latest of everything, because a join that leaves you on last month's memory
# looks exactly like a join that worked. This is also what brings an older
# installation on a machine you have not touched in a while up to date.
Update-KitHub -Hub $Hub

Join-KitMemory -Hub $Hub

# The hub's own commands, so `hub map ...` works from any folder on this machine
# instead of only on the server where the deploy script installs them.
Install-KitHubCli -Hub $Hub

$skills = Join-Path $Hub '.claude\skills'
$agents = Join-Path $Hub '.agents\skills'
if ((Test-Path $skills) -and -not (Test-Path $agents)) {
    New-Item -ItemType Directory -Force (Join-Path $Hub '.agents') | Out-Null
    New-Item -ItemType Junction -Path $agents -Target $skills | Out-Null
    Write-KbOk "skills: assistants other than Claude Code can now read them too"
}

Write-KbSay "Done"
Write-Host @"
This machine now shares one memory with the rest of them, at:

  $(Join-Path $Hub 'memory')

What that means in practice: anything your assistant learns here is written into
your hub folder and travels with the next push, and anything it learned on
another machine is already here. Nothing is stored inside one AI tool any more.

There is one thing this cannot do for you: a memory only reaches the other
machines once it is pushed, so keep doing what you already do with the folder.
"@
