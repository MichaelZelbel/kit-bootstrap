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
    # Which AI tools may be synced from this PC, as a comma list (e.g. claude,codex).
    # '-' means none. The default '(auto)' means "no choice made this run": keep what
    # this device already has recorded, or every syncable tool found here.
    [string]$Sources = '(auto)',
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

function Update-KitFolderNames {
    <#  Rename an older hub's folders to the names that say WHEN each one is read.

        The first shape of this system had context/ for what you write and memory/ for what
        your assistant writes. That describes who typed it, which nobody asks while working.
        The names now answer the question that decides everything: profile/ and rules/ every
        session, observations/ when the subject comes up, prompts/ only when you ask by name.

        Safe to run again, and safe on a hub that never had the old names. It renames ONLY
        when the new name is absent, so a reader who already has both keeps both and is told,
        rather than having two folders silently merged. Nothing is ever deleted. #>
    param([Parameter(Mandatory)][string]$Hub)
    foreach ($pair in @(@('context','profile'), @('memory','observations'))) {
        $old = Join-Path $Hub $pair[0]
        $new = Join-Path $Hub $pair[1]
        if (-not (Test-Path $old)) { continue }
        if (Test-Path $new) {
            Write-KbWarn "folders: you have both $($pair[0])\ and $($pair[1])\. Leaving both alone; move what you want by hand, then delete the empty one."
            continue
        }
        $moved = $false
        if (Test-Path (Join-Path $Hub '.git')) {
            git -C $Hub ls-files --error-unmatch $pair[0] 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                git -C $Hub mv $pair[0] $pair[1] 2>&1 | Out-Null
                $moved = ($LASTEXITCODE -eq 0)
            }
        }
        if (-not $moved) { Move-Item $old $new }
        Write-KbOk "folders: $($pair[0])\ is now $($pair[1])\, which says when your assistant reads it"
    }
    foreach ($d in @('profile','rules','observations')) {
        New-Item -ItemType Directory -Force (Join-Path $Hub $d) | Out-Null
    }
}

function Initialize-KitMemoryIndex {
    param([Parameter(Mandatory)][string]$Hub)
    Update-KitFolderNames -Hub $Hub
    $mem = Join-Path $Hub 'observations'
    New-Item -ItemType Directory -Force $mem | Out-Null
    $idx = Join-Path $mem 'MEMORY.md'
    if (Test-Path $idx) { return }
    $lines = @(
        '# What I remember, and where it goes'
        ''
        'Your assistant loads this page every session, so it is short on purpose.'
        ''
        '**The rules are not here.** They live in `rules/`, one file per rule with the'
        'whole story, and the short version of every one of them is compiled into'
        '`AGENTS.md`, which your assistant reads before anything else.'
        ''
        '**What it works out about you goes here**, one file per fact, and it opens one'
        'only when the subject comes up. That is why this page stays small while the'
        'folder behind it can grow as large as it likes.'
        ''
        '**The four folders, and the only thing that separates them is WHEN they are read:**'
        ''
        '    profile/       what it knows because you told it ...... every session'
        '    rules/         how it should behave .................... compiled into AGENTS.md'
        '    observations/  what it worked out on its own ........... when the subject comes up'
        '    prompts/       what you typed to an AI ................. never, unless you ask'
        ''
        'All of it lives in your hub folder rather than inside one AI tool, so every'
        'assistant on every one of your machines reads the same thing.'
        ''
        'Write a new one here as `some-fact.md`, with a `name` and a one-line'
        '`description` at the top so a session can tell whether to open it.'
    )
    Set-KbTextFile -Path $idx -Lines $lines
    Write-KbOk "memory: created the page at $idx"
}

function Join-KitMemory {
    <#  Point the assistant's private memory folder at the hub's observations/ folder,
        which is where what an assistant works out on its own belongs, so one memory is
        shared by every machine and every assistant. #>
    param([Parameter(Mandatory)][string]$Hub)

    # The index belongs to the hub, not to any one tool, so it is seeded even
    # when the link below is skipped.
    Initialize-KitMemoryIndex -Hub $Hub

    # Only for a PC that actually has Claude Code, and whose owner has not
    # switched it off. Before this guard, a PC that had never seen Claude Code
    # got a fabricated ~\.claude profile folder out of nowhere. The functions it
    # leans on live a little further down this file.
    if (-not (Test-KitAiTool 'claude')) {
        Write-KbOk "memory: Claude Code is not on this PC, so there is no memory folder to share yet. Run this again once it is installed."
        return
    }
    if (@((Get-KitEnabledSources) -split ',' | ForEach-Object { $_.Trim() }) -notcontains 'claude') {
        Write-KbOk "memory: you chose not to sync Claude Code on this PC, so its memory folder was left alone."
        return
    }

    $mem  = Join-Path $Hub 'observations'
    $link = Get-KitMemoryLinkPath -Hub $Hub

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
# WHICH AI TOOLS LIVE ON THIS PC, AND WHICH OF THEM MAY BE SYNCED
#
# The Windows twin of the same section in lib.sh: same ids, same order, same
# words, so a person moving between machines is told the same story. Added
# 2026-08-11, because before this the installer wired sync with no detection,
# no disclosure and no choice: it created a Claude Code memory link on PCs that
# had never seen Claude Code, and the harvest read Codex's conversation logs
# and pushed them to the hub's repository without one sentence saying so.
#
#   DETECTED  the tool leaves files on this PC, so we can see it is here.
#   SYNCABLE  this kit can read what the person typed to it: Claude Code
#             (memory + prompts), Codex (prompts), Hermes chat bots (prompts).
#             Everything else is shown with the reason it is not.
#   ENABLED   the person said yes. Recorded per device in ~\.hub\device.env as
#             HUB_PROMPT_SOURCES. The value "-" means NONE: a Windows
#             environment variable cannot hold an empty string, so none needs a
#             spelling that survives one.
# =============================================================================

$script:KitSupportedSources = @('claude', 'codex', 'hermes')

function Get-KitHome {
    <#  KB_HOME wins so the test suite can hand these functions a pretend home
        folder instead of reading (or writing into) the real one. #>
    if ($env:KB_HOME) { return $env:KB_HOME }
    return $HOME
}

function Test-KitAiTool {
    <#  Does this AI tool leave files on this PC? Fingerprints verified on real
        installs (2026-08-11). A wrong path here can only fail to see a tool,
        never invent one, because everything is a plain "does this folder exist".
        KB_ASSUME_TOOLS is the test override: a comma list of ids to report as
        present, or "-" for a PC with nothing. #>
    param([Parameter(Mandatory)][string]$Id)
    if ($env:KB_ASSUME_TOOLS) {
        return ((($env:KB_ASSUME_TOOLS -split ',') | ForEach-Object { $_.Trim() }) -contains $Id)
    }
    $h = Get-KitHome
    switch ($Id) {
        'claude'         { return ((Test-Path (Join-Path $h '.claude')) -or
                                   [bool](Get-Command claude -ErrorAction SilentlyContinue)) }
        'codex'          { return [bool](Test-Path (Join-Path $h '.codex')) }
        'hermes'         { return [bool](Test-Path (Join-Path $h '.hermes\profiles')) }
        'claude-desktop' { return (($null -ne $env:APPDATA -and (Test-Path (Join-Path $env:APPDATA 'Claude'))) -or
                                   ($null -ne $env:LOCALAPPDATA -and (Test-Path (Join-Path $env:LOCALAPPDATA 'AnthropicClaude')))) }
        'muse'           { return ((Test-Path (Join-Path $h '.config\muse')) -or
                                   (Test-Path (Join-Path $h '.local\share\muse')) -or
                                   [bool](Get-Command muse -ErrorAction SilentlyContinue)) }
        'opencode'       { return ((Test-Path (Join-Path $h '.config\opencode')) -or
                                   [bool](Get-Command opencode -ErrorAction SilentlyContinue)) }
        'openclaw'       { return [bool](Test-Path (Join-Path $h '.openclaw')) }
        'comet'          { return ($null -ne $env:LOCALAPPDATA -and (Test-Path (Join-Path $env:LOCALAPPDATA 'Perplexity\Comet'))) }
        'copilot'        { return [bool](Test-Path (Join-Path $h '.copilot')) }
        'cursor'         { return ((Test-Path (Join-Path $h '.cursor')) -or
                                   ($null -ne $env:APPDATA -and (Test-Path (Join-Path $env:APPDATA 'Cursor')))) }
        'gemini'         { return [bool](Test-Path (Join-Path $h '.gemini')) }
    }
    return $false
}

function Get-KitAiToolInfo {
    <#  sync|Human name|why not, when sync is none. "sync" is what this kit can
        read TODAY, not what the tool could offer. #>
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'claude'         { return 'memory+prompts|Claude Code|' }
        'codex'          { return 'prompts|Codex|' }
        'hermes'         { return 'prompts|Hermes chat bots|' }
        'claude-desktop' { return 'none|Claude Desktop|keeps your conversations on its own servers, not in files here' }
        'comet'          { return 'none|Perplexity Comet|keeps your conversations on its own servers, not in files here' }
        'muse'           { return 'none|Muse Code|keeps files here, but this kit cannot read its format yet' }
        'opencode'       { return 'none|OpenCode|keeps files here, but this kit cannot read its format yet' }
        'openclaw'       { return 'none|OpenClaw|keeps files here, but this kit cannot read its format yet' }
        'copilot'        { return 'none|GitHub Copilot|keeps files here, but this kit cannot read its format yet' }
        'cursor'         { return 'none|Cursor|keeps files here, but this kit cannot read its format yet' }
        'gemini'         { return 'none|Gemini CLI|keeps files here, but this kit cannot read its format yet' }
    }
    return $null
}

function Find-KitAiTools {
    <#  One line per AI tool found on this PC:  id|sync|Human name|note
        Fixed order, syncable-first, so every caller (the report below, the
        wizard's checklist) shows the same list in the same order. #>
    foreach ($id in @('claude', 'codex', 'hermes', 'claude-desktop', 'muse', 'opencode',
                      'openclaw', 'comet', 'copilot', 'cursor', 'gemini')) {
        if (Test-KitAiTool $id) { "$id|$(Get-KitAiToolInfo $id)" }
    }
}

function Get-KitDeviceEnvValue {
    param([Parameter(Mandatory)][string]$Name)
    $p = Join-Path (Get-KitHome) '.hub\device.env'
    if (-not (Test-Path $p)) { return $null }
    $val = $null
    foreach ($line in @(Get-Content $p -ErrorAction SilentlyContinue)) {
        $l = $line -replace '^\s*export\s+', ''
        if ($l -match '^\s*#') { continue }
        $m = [regex]::Match($l, '^\s*' + [regex]::Escape($Name) + '\s*=(.*)$')
        if ($m.Success) { $val = $m.Groups[1].Value.Trim().Trim('"').Trim("'") }
    }
    return $val
}

function Get-KitEnabledSources {
    <#  Which syncable tools the person said yes to, as a comma list ('' = none).
        Who decides, in order: KB_SYNC_SOURCES this run, the choice recorded on
        this device, and only then "every syncable tool found here", which is
        what every machine did before there was a choice. #>
    $v = $env:KB_SYNC_SOURCES
    if ($null -eq $v) { $v = Get-KitDeviceEnvValue 'HUB_PROMPT_SOURCES' }
    if ($null -eq $v) {
        $found = @()
        foreach ($id in $script:KitSupportedSources) { if (Test-KitAiTool $id) { $found += $id } }
        return ($found -join ',')
    }
    if ($v.Trim() -eq '-') { return '' }
    return $v
}

function Set-KitPromptSources {
    <#  Record the choice on this device, in ~\.hub\device.env rather than in the
        hub, because the hub travels to every machine and this is a fact about
        one of them. #>
    param([AllowEmptyString()][string]$Value = '')
    if ($Value.Trim() -eq '-') { $Value = '' }
    $dir = Join-Path (Get-KitHome) '.hub'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $f = Join-Path $dir 'device.env'
    $lines = @()
    if (Test-Path $f) { $lines = @(Get-Content $f) }
    $found = $false
    $lines = @($lines | ForEach-Object {
        if ($_ -match '^\s*HUB_PROMPT_SOURCES=') { $found = $true; "HUB_PROMPT_SOURCES=$Value" } else { $_ }
    })
    if (-not $found) { $lines += "HUB_PROMPT_SOURCES=$Value" }
    Set-Content -Path $f -Value $lines -Encoding ascii
    Write-KbOk "recorded your choice on this device: HUB_PROMPT_SOURCES=$Value (in $f)"
}

function Write-KitSyncReport {
    <#  The truth about this PC, built from what was detected and chosen, never
        from the promise. This is what the completion screen prints. #>
    $on = @((Get-KitEnabledSources) -split ',' | Where-Object { $_ })
    $synced = @(); $off = @(); $unsync = @()
    foreach ($line in @(Find-KitAiTools)) {
        $p = $line -split '\|', 4
        if ($p.Count -lt 4) { continue }
        $id = $p[0]; $sync = $p[1]; $name = $p[2]; $note = $p[3]
        if ($sync -eq 'none') {
            $unsync += "  - ${name}: $note"
        } elseif ($on -contains $id) {
            if ($sync -eq 'memory+prompts') { $synced += "  - ${name}: its memory folder, plus what you type to it and its answers" }
            else { $synced += "  - ${name}: what you type to it, and its answers" }
        } else {
            $off += "  - $name (switched off by your choice; edit HUB_PROMPT_SOURCES in ~\.hub\device.env to change it)"
        }
    }
    if ($synced.Count -gt 0) {
        Write-Host "What is synced from this PC into your hub, and pushed to its repository:"
        $synced | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "Nothing is synced from this PC: no AI tool here is both readable by this kit and switched on."
    }
    if ($off.Count -gt 0)    { Write-Host "Found here but left alone:";   $off    | ForEach-Object { Write-Host $_ } }
    if ($unsync.Count -gt 0) { Write-Host "Found here but not syncable:"; $unsync | ForEach-Object { Write-Host $_ } }
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
    # A hub made on this machine five minutes ago has no remote yet, and telling
    # its owner it "could not pull" and "may be out of date" is alarming and
    # untrue: there is nowhere to be out of date FROM. Say the useful thing
    # instead, which is the step that would make their folder reach their other
    # machines.
    git -C $Hub remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-KbOk "this hub lives only on this computer for now. Give it a home on GitHub when you are ready, and it will travel to your other machines."
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

function Install-KitHubTools {
    <#  Put the kit's own small programs on this PC. The Windows twin of
        kb_install_hub_tools in lib.sh.

        WHY THESE ARE NOT IN THE HUB FOLDER. The hub is a folder of text files
        and the book says so in its folder tour: "Nothing here needs a terminal." A
        Node program and a Python program sitting in it would be the first two
        things in there that are not text a person can read. So they are
        installed the way an assistant is installed, on the machine, and they
        write into the folder from outside.

        WHY THEY ARE NOT COPIED INTO A PRIVATE FOLDER EITHER. Before 2026-08-10
        the only copy of the prompt collector lived in one person's own hub, so
        the program the book promises its readers existed nowhere they could get
        it. One copy, in the kit, installed identically on every machine.

        Quiet on a kit that ships no tools folder, which is every other product. #>
    param(
        [Parameter(Mandatory)][string]$Hub,
        [string]$ToolsRepo,
        [string]$ToolsPath = 'tools'
    )

    # A join does not retype the product. The kit the tools came from is written
    # down in ~\.hub\device.env the first time it is known (below, beside HUB_DIR),
    # so a later run that names no kit refreshes them instead of skipping.
    if (-not $ToolsRepo) {
        $devEnv = Join-Path $HOME '.hub\device.env'
        if (Test-Path $devEnv) {
            $line = @(Get-Content $devEnv | Where-Object { $_ -match '^\s*HUB_TOOLS_REPO=' })[0]
            if ($line) { $ToolsRepo = ($line -replace '^\s*HUB_TOOLS_REPO=', '').Trim() }
        }
    }
    if (-not $ToolsRepo) { return }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-tools-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        git clone --depth 1 --quiet $ToolsRepo $tmp 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-KbWarn "prompt archive: I could not fetch the kit's programs from $ToolsRepo, so the daily job has nothing to run yet. Check this PC can reach the internet and run this again."
            return
        }
        $src = Join-Path $tmp $ToolsPath
        if (-not (Test-Path $src)) { return }

        $bin = Join-Path $HOME '.local\bin'
        New-Item -ItemType Directory -Force $bin | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $HOME '.hub') | Out-Null
        $n = 0
        Get-ChildItem $src -File | Where-Object { $_.Extension -ne '.md' } | ForEach-Object {
            # REMOVE FIRST, ALWAYS. Install-KitHubCli puts links in this same folder that
            # point back into the hub, and copying over a link writes THROUGH it, into the
            # hub. That happened on the first live run and the only sign was a changed file
            # nobody asked to change. Deleting the name first means we always write a file.
            $dest = Join-Path $bin $_.Name
            Remove-Item $dest -Force -ErrorAction SilentlyContinue
            Copy-Item $_.FullName $dest -Force
            $n++
        }
        if ($n -eq 0) { return }

        # The launcher. A .cmd rather than a shortcut, because a scheduled task and a
        # terminal both understand one, and %~dp0 is how it finds its other half: the
        # collector sits in the same folder and is never looked for anywhere else.
        $js = Join-Path $bin 'prompt-harvest.js'
        if (Test-Path $js) {
            @('@echo off', "node `"%~dp0prompt-harvest.js`" %*") |
                Set-Content -Path (Join-Path $bin 'hub-prompt-harvest.cmd') -Encoding ascii
        }

        # The rules compiler, which a reader types by hand rather than the schedule
        # running it. It was a Python program until 2026-08-21 and the book printed it as
        # a path inside the hub, which is a folder this installer deliberately keeps free
        # of programs. Nobody had that path, and nothing here installs Python either, so
        # the one command Chapter 17 asks a reader to type worked for nobody. Node is
        # already a prerequisite, so it is a Node program with a .cmd, exactly like the
        # collector above. Without the .cmd a bare compile-rules.js silently does nothing
        # in PowerShell, which is worse than an error.
        $rulesJs = Join-Path $bin 'compile-rules.js'
        if (Test-Path $rulesJs) {
            @('@echo off', "node `"%~dp0compile-rules.js`" %*") |
                Set-Content -Path (Join-Path $bin 'hub-compile-rules.cmd') -Encoding ascii
        }

        # Where the hub is, recorded once, so a job started by the schedule with almost
        # no environment never has to guess. The programs read this file already.
        $devEnv = Join-Path $HOME '.hub\device.env'
        $has = (Test-Path $devEnv) -and ((Get-Content $devEnv) -match '^\s*HUB_DIR=')
        if (-not $has) { Add-Content -Path $devEnv -Value "HUB_DIR=$Hub" -Encoding ascii }
        # And where the tools came from, so the next run can refresh them unprompted.
        $hasRepo = (Test-Path $devEnv) -and ((Get-Content $devEnv) -match '^\s*HUB_TOOLS_REPO=')
        if (-not $hasRepo) { Add-Content -Path $devEnv -Value "HUB_TOOLS_REPO=$ToolsRepo" -Encoding ascii }

        Update-KitPath
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';') -notcontains $bin) {
            $joined = if ($userPath) { "$bin;$userPath" } else { $bin }
            [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
        }
        $env:Path = "$bin;$env:Path"
        Write-KbOk "prompt archive: installed the program that files what you type to an AI, and its answers ($bin)"
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-KitHiddenLauncher {
    <#  Write the tiny .vbs that runs a console program with no visible window, and
        return its path.

        WHY EVERY SCHEDULED JOB MUST GO THROUGH THIS. A Windows scheduled task whose
        program is a console program (bash.exe, node.exe, python.exe) opens a terminal
        window in the owner's face every single time it fires. On a reader's PC that is
        an unexplained window flashing once an hour, forever, with nothing to click.
        The task's own "Hidden" setting does NOT prevent it: that hides the task in the
        Task Scheduler list, not the window the program opens.

        WHY IT IS A FUNCTION AND NOT A COPIED BLOCK. It was a copied block, in the
        prompt archive step only, and the notebook step written eight days later missed
        it: readers on Windows would have got exactly the window this file already knew
        how to avoid, and Michael found it flashing on his own PC on 2026-08-21. One
        copy, used by both. #>
    param([Parameter(Mandatory)][string]$Dir)
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $vbs = Join-Path $Dir 'run-hidden.vbs'
    @(
        "' Run any console command with no visible window (written by the kit installer).",
        "' Usage: wscript run-hidden.vbs <workdir> <exe> [args...]",
        'Option Explicit',
        'Dim sh, i, cmd, a',
        'If WScript.Arguments.Count < 2 Then WScript.Quit 2',
        'Set sh = CreateObject("WScript.Shell")',
        'sh.CurrentDirectory = WScript.Arguments(0)',
        'cmd = ""',
        'For i = 1 To WScript.Arguments.Count - 1',
        '  a = WScript.Arguments(i)',
        '  If InStr(a, " ") > 0 Then a = """" & a & """"',
        '  cmd = cmd & a & " "',
        'Next',
        'sh.Run Trim(cmd), 0, False'
    ) | Set-Content -Path $vbs -Encoding ascii
    return $vbs
}

function Install-KitPromptHarvest {
    <#  Make this PC file what its owner types to an AI, by itself, every day.
        The Windows twin of kb_install_prompt_harvest in lib.sh: same promise,
        native mechanism. Linux and Mac get a line in cron; Windows gets a
        scheduled task, because that is what Windows has.

        WHY THIS BELONGS IN THE INSTALLER. The hub keeps a drawer of everything
        he has typed to any assistant, so months later he can ask "how did I get
        that result in June" and be answered with the words he actually used.
        Filling it needs something on each machine to run once a day, and until
        2026-08-10 nothing installed it: one computer had a job because somebody
        typed one there by hand, and the rest had nothing. A wiring step you
        perform by hand only ever covers the machine you were sitting at.

        Quiet on a hub that ships no harvester, which is every reader's hub for
        now: nothing to schedule, so nothing to say.

        TaskName is a parameter so the test suite can register and remove its own
        task instead of touching the real one. #>
    param(
        [Parameter(Mandatory)][string]$Hub,
        [string]$TaskName = 'Hub prompt archive'
    )

    # The installed program first, the hub's own copy second. The second is only for a
    # hub set up before the programs were installed on the machine, so nothing breaks
    # between the two.
    #
    # HISTORY, because this path was broken in the least visible way possible: the
    # string used to contain a literal BACKSPACE byte (".local<0x08>in"), the corpse of
    # a "\b" interpreted somewhere on its way into the file. It rendered as ".localin",
    # the installed program was never found, the function returned two lines down, and
    # NO Windows machine ever got the scheduled task. The tests missed it because they
    # only ever exercised the hub-copy fallback; they now cover this branch too.
    $installed = Join-Path (Get-KitHome) '.local\bin\prompt-harvest.js'
    $js = if (Test-Path $installed) { $installed } else { Join-Path $Hub 'bin\prompt-harvest.js' }
    if (-not (Test-Path $js)) { return }

    $node = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $node) {
        Write-KbWarn "prompt archive: Node.js is not on this computer, so what you type to an AI here (and its answers) cannot be filed. Install Node.js and run this again."
        return
    }
    if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
        Write-KbWarn "prompt archive: this Windows has no Task Scheduler commands, so nothing can run the daily job. Run it yourself when you want it: node `"$js`""
        return
    }

    # NEVER make node.exe the task's own executable: the task then flashes a terminal
    # window at the owner every hour it fires (reported 2026-08-18, on two of Michael's
    # machines). The job goes through wscript + a tiny .vbs launcher instead, which runs
    # the same command with its window hidden. The launcher is written here, next to the
    # collector, because a reader's hub ships no such file. A task found running node
    # directly is from before this fix and gets replaced.
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing -and $existing.Actions[0].Execute -match 'wscript') {
        Write-KbOk "prompt archive: already scheduled on this computer"
        return
    }
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-KbOk "prompt archive: replacing the old job, which opened a visible window every hour"
    }

    $vbs = Write-KitHiddenLauncher -Dir (Split-Path $js)

    try {
        # Hourly, not nightly, and the job does nothing if it already ran today. A fixed
        # time in the small hours is right for a server and wrong for a laptop that is shut.
        $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
            -Argument "`"$vbs`" `"$Hub`" `"$node`" `"$js`" --once-a-day" -WorkingDirectory $Hub
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
            -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description 'Files what you type to an AI on this computer, and its answers, into your hub.' -Force | Out-Null
        Write-KbOk "prompt archive: this computer now files what you type to an AI, and its answers, once a day"
    } catch {
        Write-KbWarn "prompt archive: I could not add the daily job to this computer's schedule ($($_.Exception.Message)). Run it by hand when you want it: node `"$js`""
    }
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
        #
        # One exception: .gitignore GROWS. Every hub already has one from day one,
        # so skip-if-present means a rule the starter learns later (the dev/ fence,
        # 2026-08-19) never reaches an existing hub - and the miss is not stale
        # text but a whole nested repository committed into the hub's history. For
        # that one file, append the starter's pattern lines the hub does not
        # already have (comments and blanks skipped, so a re-run adds nothing twice).
        Get-ChildItem $src -Force | ForEach-Object {
            $dest = Join-Path $Path $_.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $_.FullName $dest -Recurse -Force
            } elseif ($_.Name -eq '.gitignore' -and -not $_.PSIsContainer) {
                $have = @(Get-Content $dest -ErrorAction SilentlyContinue)
                $add = @(Get-Content $_.FullName | Where-Object { $_ -and $_ -notmatch '^\s*#' -and ($have -notcontains $_) })
                if ($add.Count) { Add-Content -Path $dest -Value $add }
            }
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

# =============================================================================
# YOUR NOTEBOOK: CONNECT IT ONCE, AND THE CONNECTION TRAVELS WITH THE FOLDER
#
# The Windows twins of the kb_*notebook* functions in lib.sh. When you change one
# side, change the other, and add the case to BOTH test.sh and test-windows.ps1.
#
# Added 2026-08-16. Before this, the installer had no credential step of any kind
# on either front door. The book promised that every computer you own
# reads the same hub, and said nothing about the one thing that did NOT travel: the
# key to your notebook. A reader joining a second machine got their files and a
# notebook that was simply absent, with nothing anywhere saying so.
#
#   secrets\hub-secrets.env.age   your credentials, locked, INSIDE the hub folder
#   secrets\hub-key.age           the key to that, locked with ONE passphrase
#   ~\.hub\age-key.txt            the unlocked key, on this PC only
#
# THE TRADE, said plainly: anyone with BOTH your hub folder and your passphrase has
# your credentials. Same bargain as a password manager. Keep the folder private and
# put the passphrase in your password manager.
#
# KB_AGE / KB_AGE_KEYGEN are the test overrides, the same as KB_HOME further up.
# =============================================================================

function Get-KitAge       { if ($env:KB_AGE) { return $env:KB_AGE } return 'age' }
function Get-KitAgeKeygen { if ($env:KB_AGE_KEYGEN) { return $env:KB_AGE_KEYGEN } return 'age-keygen' }
function Test-KitAge {
    [bool](Get-Command (Get-KitAge) -ErrorAction SilentlyContinue) -and
    [bool](Get-Command (Get-KitAgeKeygen) -ErrorAction SilentlyContinue)
}
function Get-KitHubKeyPath {
    if ($env:HUB_AGE_KEY) { return $env:HUB_AGE_KEY }
    return (Join-Path (Get-KitHome) '.hub\age-key.txt')
}

function Test-KitInteractive {
    <#  Is there a person at a keyboard right now?

        age asks for a passphrase at the terminal ON PURPOSE and will not take one
        from a pipe or a variable. With no terminal it does not fail, it WAITS - so an
        install running unattended stops dead, with no message and no end, which is
        the worst of the three possible outcomes. Found by this kit's own test suite
        on 2026-08-16, where it hung for seven minutes on a case that was meant to
        return in a millisecond. The bash side has always had this guard (have_tty);
        this side did not. #>
    try { return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) }
    catch { return $false }
}

function Get-KitNotebookState {
    <#  connected  = this PC can already open the credentials in that folder
        sealed     = the folder carries them and the key, waiting for a passphrase
        locked-out = the folder carries credentials, this PC cannot open them, and there
                     is no sealed key to ask a passphrase for. Nothing may be written.
        none       = no notebook here yet, which is a complete way to own a hub

        LOCKED-OUT IS THE ONE THAT MATTERS, and it was missing on the day this was
        written. Without it, a run on a machine that already had somebody's hub read
        "I cannot open this" as "there is nothing here", took a new token and re-locked
        the whole store to THIS computer's key - shutting every other computer sharing
        that folder out of every credential in it at once, silently. It happened during
        testing and was survivable only because the file was committed. #>
    param([Parameter(Mandatory)][string]$Hub)
    $key   = Get-KitHubKeyPath
    $store = Join-Path $Hub 'secrets\hub-secrets.env.age'
    if ((Test-Path $store) -and (Test-Path $key) -and (Test-KitAge)) {
        & (Get-KitAge) -d -i $key $store > $null 2>&1
        if ($LASTEXITCODE -eq 0) { return 'connected' }
    }
    if (Test-Path (Join-Path $Hub 'secrets\hub-key.age')) { return 'sealed' }
    if (Test-Path $store) { return 'locked-out' }
    return 'none'
}

function Unlock-KitHubKey {
    <#  The SECOND computer, and every one after it. One passphrase, and every
        credential the folder carries is live here. #>
    param([Parameter(Mandatory)][string]$Hub)
    $key    = Get-KitHubKeyPath
    $sealed = Join-Path $Hub 'secrets\hub-key.age'
    if (-not (Test-Path $sealed)) { return $false }
    if (Test-Path $key) { return $true }
    if (-not (Test-KitAge)) {
        Write-KbWarn "notebook: this PC needs the 'age' program to unlock your credentials. Install it (winget install --id FiloSottile.age) and run this again."
        return $false
    }
    if (-not (Test-KitInteractive)) {
        Write-KbWarn "notebook: this folder carries your connection, but I cannot ask for your passphrase here. Run the installer again from a terminal window."
        return $false
    }
    Write-Host ""
    Write-Host "This computer has no key yet, but your hub folder carries one."
    Write-Host "Type your hub passphrase to unlock every credential at once:"
    New-Item -ItemType Directory -Force (Split-Path $key -Parent) | Out-Null
    & (Get-KitAge) -d -o $key $sealed
    if ($LASTEXITCODE -eq 0 -and (Test-Path $key)) {
        Write-KbOk "notebook: unlocked. Nothing had to be carried to this computer."
        return $true
    }
    # A half-written key is worse than none: it looks like a connection and opens nothing.
    Remove-Item $key -ErrorAction SilentlyContinue
    Write-KbWarn "notebook: that passphrase did not open it, so nothing was changed. Your passphrase is in your password manager; run this again to try once more."
    return $false
}

function Protect-KitHubKey {
    <#  The FIRST computer. Put the key INTO the folder, locked with one passphrase,
        so the next computer needs nothing carried to it. Refuses to seal a key that
        opens nothing, and proves the round trip before keeping the result: an
        unverified backup is not a backup, and the machine that would discover that
        is the new one, at the moment it has no other way in. #>
    param([Parameter(Mandatory)][string]$Hub)
    $key    = Get-KitHubKeyPath
    $sealed = Join-Path $Hub 'secrets\hub-key.age'
    $store  = Join-Path $Hub 'secrets\hub-secrets.env.age'
    if (-not (Test-Path $key))  { return $false }
    if (Test-Path $sealed)      { return $true }
    if (-not (Test-KitAge))     { return $false }
    if (Test-Path $store) {
        & (Get-KitAge) -d -i $key $store > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-KbWarn "notebook: the key on this PC does not open the credentials in that folder, so sealing it would produce a passphrase that unlocks nothing. Nothing changed."
            return $false
        }
    }
    if (-not (Test-KitInteractive)) {
        Write-KbWarn "notebook: I could not ask for a passphrase here, so your key was NOT put into the folder. Until it is, a second computer cannot pick up the connection. Run the installer again from a terminal window."
        return $false
    }
    Write-Host ""
    Write-Host "Choose a passphrase. This is the ONE thing you will type on your next computer,"
    Write-Host "and the one thing to put in your password manager. You will be asked twice."
    New-Item -ItemType Directory -Force (Join-Path $Hub 'secrets') | Out-Null
    & (Get-KitAge) -p -o $sealed $key
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $sealed -ErrorAction SilentlyContinue
        Write-KbWarn "notebook: your key was NOT put into the folder, so a second computer cannot pick up the connection yet. Run this again to try once more."
        return $false
    }
    $check = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-seal-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    Write-Host ""
    Write-Host "Type the same passphrase once more, so I can prove it really opens:"
    & (Get-KitAge) -d -o $check $sealed
    $same = $false
    if ($LASTEXITCODE -eq 0 -and (Test-Path $check)) {
        $same = (Get-FileHash $check).Hash -eq (Get-FileHash $key).Hash
    }
    Remove-Item $check -ErrorAction SilentlyContinue
    if ($same) {
        Write-KbOk "notebook: your connection now travels with the folder. On your next computer, that passphrase is all you type."
        return $true
    }
    Remove-Item $sealed -ErrorAction SilentlyContinue
    Write-KbWarn "notebook: the two passphrases did not match, so nothing was kept. Run this again."
    return $false
}

function Save-KitNotebookToken {
    <#  Put one credential into the folder's locked store, making a key for this PC
        first if there is none. Merges: a store holding other credentials keeps them. #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][string]$Token)
    if (-not (Test-KitAge)) {
        Write-KbWarn "notebook: this PC needs the 'age' program to keep a credential safely. Install it (winget install --id FiloSottile.age) and run this again."
        return $false
    }
    $key   = Get-KitHubKeyPath
    $store = Join-Path $Hub 'secrets\hub-secrets.env.age'
    # NEVER re-lock a store this PC cannot already open. Writing it would encrypt the whole
    # thing to this machine's key and shut out every other computer sharing the folder -
    # all of them, from every credential, in one step and without a word.
    if (Test-Path $store) {
        $canOpen = $false
        if (Test-Path $key) { & (Get-KitAge) -d -i $key $store > $null 2>&1; $canOpen = ($LASTEXITCODE -eq 0) }
        if (-not $canOpen) {
            Write-KbWarn "notebook: that folder already carries credentials this PC cannot open, so I am not touching them. Unlock it first with the hub passphrase, or point me at a different folder."
            return $false
        }
    }
    New-Item -ItemType Directory -Force (Split-Path $key -Parent) | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $Hub 'secrets') | Out-Null
    if (-not (Test-Path $key)) {
        & (Get-KitAgeKeygen) -o $key > $null 2>&1
        if (-not (Test-Path $key)) { Write-KbWarn "notebook: I could not make a key on this PC."; return $false }
    }
    $recipient = (& (Get-KitAgeKeygen) -y $key 2>$null | Select-Object -First 1)
    if (-not $recipient) { Write-KbWarn "notebook: the key on this PC is not readable."; return $false }

    $lines = @()
    if (Test-Path $store) {
        $lines = @(& (Get-KitAge) -d -i $key $store 2>$null | Where-Object { $_ -notmatch '^MENERIO_' })
    }
    # One credential, one name. Menerio used to hand out a separate connector token
    # and API key, and this wrote the same value under both names so a reader still
    # pasted one thing. Since 2026-08-16 an API key with "Hub access" opens both
    # doors, so there is one name and nothing to reconcile.
    $lines += "MENERIO_API_KEY=$Token"
    $plain = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-store-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    Set-KbTextFile -Path $plain -Lines $lines
    & (Get-KitAge) -r $recipient -o $store $plain 2>$null
    $rc = $LASTEXITCODE
    Remove-Item $plain -ErrorAction SilentlyContinue
    if ($rc -eq 0) { Write-KbOk "notebook: your credential is kept inside your hub folder, locked."; return $true }
    Write-KbWarn "notebook: I could not write the credential into your hub folder."
    return $false
}

function Write-KitMcpConfig {
    <#  The file that tells your assistant where your notebook is. It NAMES the
        credential rather than carrying it, so the file holds no secret and is safe
        to keep in the folder. Never overwrites one you already have. #>
    param([Parameter(Mandatory)][string]$Hub)
    $f = Join-Path $Hub '.mcp.json'
    if (Test-Path $f) { Write-KbOk "notebook: .mcp.json is already there, left as you have it"; return }
    $lines = @(
        '{',
        '  "_comment": [',
        '    "This tells your assistant where your notebook is.",',
        '    "It NAMES the credential rather than carrying it: ${MENERIO_API_KEY} is read from",',
        '    "this computer''s environment when the assistant starts, so this file holds no secret",',
        '    "and is safe to keep in the folder. The value itself lives locked in secrets/, and",',
        '    "travels with the folder to every computer you own.",',
        '    "Delete this file if you do not use a notebook. Nothing else in the book needs it."',
        '  ],',
        '  "mcpServers": {',
        '    "menerio": {',
        '      "url": "https://mcp.menerio.com",',
        '      "headers": {',
        '        "Authorization": "Bearer ${MENERIO_API_KEY}",',
        '        "Accept": "application/json, text/event-stream",',
        '        "Content-Type": "application/json"',
        '      }',
        '    }',
        '  }',
        '}'
    )
    Set-KbTextFile -Path $f -Lines $lines
    Write-KbOk "notebook: wrote $f, which names your credential instead of carrying it"
}

function Install-KitNotebookSync {
    <#  On save, plus an hourly catch-up. Both are quiet and cost nothing when no
        notebook is connected, which is why they are installed for every reader.

        WHY A SCHEDULED TASK AND NOT cron: Windows has no cron. The book never
        mentioned Windows scheduling at all before 2026-08-16, which is how the
        prompt-archive job could be missing on every reader's PC and be noticed by
        nobody: there was no sentence anywhere saying a job should be there. #>
    param(
        [Parameter(Mandatory)][string]$Hub,
        [string]$TaskName = 'Hub notebook sync'
    )
    $bash = Get-KitGitBash
    $runner = Join-Path (Get-KitHome) '.local\bin\hub-notebook-sync'
    if (-not (Test-Path $runner)) { return }

    # 1. On save. Git for Windows runs hooks through its own sh, so the same tiny
    #    hook works on both sides. It never blocks and never fails the save.
    $hookDir = Join-Path $Hub '.git\hooks'
    $hook = Join-Path $hookDir 'post-commit'
    if (Test-Path (Join-Path $Hub '.git')) {
        if (Test-Path $hook) {
            if (-not (Select-String -Path $hook -Pattern 'hub-notebook-sync' -Quiet -ErrorAction SilentlyContinue)) {
                Write-KbOk "notebook: you already have a post-commit hook, so I left it alone."
            }
        } else {
            New-Item -ItemType Directory -Force $hookDir | Out-Null
            $posix = $runner -replace '\\', '/'
            Set-KbTextFile -Path $hook -Lines @(
                '#!/bin/sh',
                '# Keep your notebook current the moment you save (Teach It Once).',
                '# Never blocks, never fails the save, and does nothing if you have no notebook.',
                ('"' + $posix + '" >/dev/null 2>&1 &'),
                'exit 0'
            )
            Write-KbOk "notebook: your hub now updates the notebook the moment you save a change"
        }
    }

    # 2. The hourly catch-up, for whatever happened while the PC was asleep.
    if (-not $bash) {
        Write-KbWarn "notebook: I could not find Git Bash, so the hourly catch-up was not scheduled. Your notebook still updates when you save."
        return
    }
    # NEVER make bash.exe the task's own executable: the task then flashes a terminal
    # window at the reader every hour it fires. It goes through wscript and the shared
    # launcher instead (see Write-KitHiddenLauncher). A task found starting bash
    # directly was registered before this fix and is replaced here, so a reader who
    # already installed gets the window taken away by re-running the installer.
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing -and $existing.Actions[0].Execute -match 'wscript') {
        Write-KbOk "notebook: the hourly catch-up is already on this PC"
        return
    }
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-KbOk "notebook: replacing the old hourly job, which opened a visible window every hour"
    }
    try {
        $posix = $runner -replace '\\', '/'
        $vbs   = Write-KitHiddenLauncher -Dir (Split-Path $runner)
        $action  = New-ScheduledTaskAction -Execute 'wscript.exe' `
                       -Argument ("`"$vbs`" `"$Hub`" `"$bash`" -lc `"$posix`"") -WorkingDirectory $Hub
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(37) `
                       -RepetitionInterval (New-TimeSpan -Hours 1)
        $set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                       -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $set `
            -Description 'Keeps your notebook current with what changed in your hub (Teach It Once).' -Force | Out-Null
        Write-KbOk "notebook: this PC will also catch up once an hour"
    } catch {
        Write-KbWarn "notebook: I could not add the hourly job to this PC's schedule ($($_.Exception.Message)). Your notebook still updates when you save."
    }
}

function Set-KitNotebookEnv {
    <#  Put the notebook credential into this PC's environment, so .mcp.json can NAME
        it instead of carrying it.

        WHY A USER ENVIRONMENT VARIABLE IS NOT A DOWNGRADE HERE. It is stored for this
        Windows account only, and the unlocked key in ~\.hub is readable by that same
        account already, so it exposes nothing the PC did not already expose. The
        passphrase protects the FOLDER as it travels, which is a different job. #>
    param([Parameter(Mandatory)][string]$Hub)
    $key   = Get-KitHubKeyPath
    $store = Join-Path $Hub 'secrets\hub-secrets.env.age'
    if (-not ((Test-Path $key) -and (Test-Path $store) -and (Test-KitAge))) { return }
    $lines = @(& (Get-KitAge) -d -i $key $store 2>$null)
    if ($LASTEXITCODE -ne 0) { return }
    $n = 0
    foreach ($line in $lines) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'User')
            Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2] -ErrorAction SilentlyContinue
            $n++
        }
    }
    if ($n -gt 0) { Write-KbOk "notebook: $n credential(s) are now on this PC for your assistant to use (open a new terminal for it to take)" }
}

function Connect-KitNotebook {
    <#  The whole credential step, as one moment in the install rather than a checklist.
        -Token answers the question without asking. KB_NOTEBOOK=skip says no. #>
    param([Parameter(Mandatory)][string]$Hub, [string]$Token)
    if ($env:KB_NOTEBOOK -eq 'skip') { return }
    $state = Get-KitNotebookState -Hub $Hub
    switch ($state) {
        'connected' { Write-KbOk "notebook: already connected on this computer" }
        'sealed'    { [void](Unlock-KitHubKey -Hub $Hub) }
        'locked-out' {
            Write-KbWarn "notebook: that folder already carries credentials, and this PC cannot open them. Nothing was changed. Copy .hub\age-key.txt from the computer that can open it, or seal it there so a passphrase is enough here."
            return
        }
        default {
            if (-not $Token) { $Token = $env:KB_NOTEBOOK_TOKEN }
            if (-not $Token) {
                if (-not (Test-KitInteractive)) { return }   # a one-line install stays a one-line install
                Write-Host ""
                Write-Host "A notebook is optional. Everything in this book works on plain files without one."
                Write-Host "It adds one thing: searching your hub by MEANING instead of by exact word."
                Write-Host "It needs a free account at menerio.com, and the book has a whole chapter on it later."
                $yn = Read-Host "Connect a notebook now? (y/N)"
                if ($yn -notmatch '^[Yy]') {
                    Write-KbOk "notebook: not connected, which is a complete way to own a hub. Run this again whenever you change your mind."
                    return
                }
                Write-Host "In Menerio: Settings, then API Keys, then Generate new API key. Leave every box ticked (that is the default)."
                $Token = Read-Host "Paste that key here"
            }
            if (-not $Token) { Write-KbOk "notebook: nothing pasted, so nothing was connected."; return }
            if (-not (Save-KitNotebookToken -Hub $Hub -Token $Token)) { return }
            [void](Protect-KitHubKey -Hub $Hub)
        }
    }
    Write-KitMcpConfig -Hub $Hub
    Install-KitNotebookSync -Hub $Hub
    Set-KitNotebookEnv -Hub $Hub
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

# Which AI tools live here, and which may be synced. The choice is recorded on
# this device before any wiring runs, so everything below obeys it, and the
# person is told what will be read BEFORE it is read, not after.
if ($Sources -ne '(auto)') {
    Set-KitPromptSources -Value $Sources
    if ($Sources.Trim() -eq '' -or $Sources.Trim() -eq '-') { $env:KB_SYNC_SOURCES = '-' }
    else { $env:KB_SYNC_SOURCES = $Sources }
}
Write-KitSyncReport

# Get the latest of everything, because a join that leaves you on last month's memory
# looks exactly like a join that worked. This is also what brings an older
# installation on a machine you have not touched in a while up to date.
Update-KitHub -Hub $Hub

Join-KitMemory -Hub $Hub

# The hub's own commands, so `hub map ...` works from any folder on this machine
# instead of only on the server where the deploy script installs them.
Install-KitHubCli -Hub $Hub

# The daily job that files what you type to an AI on this machine into the hub.
Install-KitHubTools -Hub $Hub -ToolsRepo $env:KB_TOOLS_REPO
Install-KitPromptHarvest -Hub $Hub

# The notebook. A joined machine is exactly the machine this step was made for: the
# credentials travel inside the folder, so if the hub carries them this unseals and
# wires the sync here too. Sits after the tools step on purpose, because it schedules
# the runner that step just installed. Quiet for the reader who never connects one.
Connect-KitNotebook -Hub $Hub

$skills = Join-Path $Hub '.claude\skills'
$agents = Join-Path $Hub '.agents\skills'
if ((Test-Path $skills) -and -not (Test-Path $agents)) {
    New-Item -ItemType Directory -Force (Join-Path $Hub '.agents') | Out-Null
    New-Item -ItemType Junction -Path $agents -Target $skills | Out-Null
    Write-KbOk "skills: assistants other than Claude Code can now read them too"
}

# The completion text is built from what actually happened on THIS PC, never
# from the promise. The old text here claimed "nothing is stored inside one AI
# tool any more" on every machine, including ones where only Claude Code (or
# nothing at all) had been wired. A person told the truth can fix a gap; a
# person told the promise cannot even see one.
Write-KbSay "Done"
Write-Host "Your hub on this PC is $Hub"
Write-Host ""
Write-KitSyncReport
Write-Host @"

Anything synced travels between your machines with the hub's git push and pull,
so keep doing what you already do with the folder. To change which AI tools are
read on this PC later: run this again with -Sources, or edit
HUB_PROMPT_SOURCES in $HOME\.hub\device.env
"@
