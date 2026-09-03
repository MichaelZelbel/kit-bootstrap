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
            # COUNT, do not guess. The old wording said "delete the empty one" and was
            # printed at a reader whose folders both held four files.
            $nOld = @(Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue).Count
            $nNew = @(Get-ChildItem -LiteralPath $new -Force -ErrorAction SilentlyContinue).Count
            Write-KbWarn "folders: you have both $($pair[0])\ ($nOld inside) and $($pair[1])\ ($nNew inside).
     They are one room under two names, and your assistant reads $($pair[1])\. Nothing was
     moved and nothing was lost. Move what you want to keep into $($pair[1])\, then delete
     $($pair[0])\."
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
    # rules\ has never had another name, so it is always safe to make. The other two are
    # made ONLY when this hub is not already keeping them under their old name. Creating
    # them regardless is precisely how the duplicate room got built.
    New-Item -ItemType Directory -Force (Join-Path $Hub 'rules') | Out-Null
    foreach ($pair in @(@('context','profile'), @('memory','observations'))) {
        if (-not (Test-Path (Join-Path $Hub $pair[0]))) {
            New-Item -ItemType Directory -Force (Join-Path $Hub $pair[1]) | Out-Null
        }
    }
}

function Get-KitRoomTwin {
    <#  If this hub already keeps that room under its OTHER name, return that other name.

        context\ and profile\ are the same room, and so are memory\ and observations\.
        Measured on a real existing hub during Run 2: the top-up found no profile\, so it
        copied the starter's in beside a context\ that already held the same four
        filenames, and the next run then complained about a duplicate it had made itself.
        Answers in both directions, so it is safe to ask about either spelling. #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][string]$Name)
    foreach ($pair in @(@('context','profile'), @('memory','observations'))) {
        if ($Name -eq $pair[1] -and (Test-Path (Join-Path $Hub $pair[0]))) { return $pair[0] }
        if ($Name -eq $pair[0] -and (Test-Path (Join-Path $Hub $pair[1]))) { return $pair[1] }
    }
    return ''
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
#             (memory + prompts), Codex (prompts), Hermes (prompts).
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
        # config.yaml is the marker every install has. The old marker, a
        # profiles\ subfolder, missed any install still on its default profile,
        # and the old location, ~\.hermes, is not where Windows keeps it - which
        # between them made Hermes invisible on the machine of the person
        # writing the book about it. HERMES_HOME wins because that is where a
        # relocated install actually lives.
        'hermes'         { foreach ($d in @($env:HERMES_HOME,
                               $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'hermes' }),
                               (Join-Path $h '.hermes'))) {
                               if ($d -and (Test-Path (Join-Path $d 'config.yaml'))) { return $true }
                           }
                           return $false }
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
        'hermes'         { return 'prompts|Hermes|' }
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

function Get-KitDefaultHubDir {
    <#  Where a new hub goes when nobody said: the top of the user folder, the same
        sentence on every OS (D-179, 2026-09-01). C:\hub stays a power option a person
        types in, never the suggestion. #>
    return (Join-Path $HOME 'hub')
}

function Get-KitCloudSyncedParents {
    <#  The folders a cloud drive syncs by default. OneDrive's folder backup takes
        Desktop, Documents and Pictures, and on newer Windows Music and Videos too.
        GetFolderPath follows the redirection when backup is already on, so this finds
        the folder wherever OneDrive moved it. The OneDrive roots come last, for a path
        typed straight into them. #>
    $out = @()
    foreach ($k in 'Desktop', 'MyDocuments', 'MyPictures', 'MyMusic', 'MyVideos') {
        $p = $null
        try { $p = [Environment]::GetFolderPath($k) } catch { $p = $null }
        if ($p) { $out += $p }
    }
    foreach ($v in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($v) { $out += $v }
    }
    return $out
}

function Get-KitHubPathRefusal {
    <#  One plain sentence when the path is a place a hub must not go, else $null.
        The rule is D-179's: never under a folder a cloud drive syncs, because a synced
        git folder gets its history corrupted (lock files copied mid-write, duplicate
        conflict copies). The drive root, C:\hub, is allowed on purpose. #>
    param([string]$Path)
    if (-not $Path -or -not $Path.Trim()) {
        return "a hub needs a folder path, for example $(Get-KitDefaultHubDir)"
    }
    $want = (Get-KitRealPath $Path).TrimEnd('\')
    foreach ($parent in Get-KitCloudSyncedParents) {
        $p = (Get-KitRealPath $parent).TrimEnd('\')
        if (-not $p) { continue }
        if ($want.Equals($p, [System.StringComparison]::OrdinalIgnoreCase) -or
            $want.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return "$p is backed up by a cloud drive, and a synced hub gets its history corrupted. Put it at $(Get-KitDefaultHubDir) instead, or at C:\hub if you want the shortest path."
        }
    }
    return $null
}

function Test-KitSamePath {
    <#  Do these two paths name the same folder? Windows case, trailing slashes and
        junctions all have to be settled before two hub paths can be compared, and the
        comparison was inlined in three places before this function existed. #>
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    return (Get-KitRealPath $A).TrimEnd('\').Equals(
            (Get-KitRealPath $B).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-KitBeside {
    <#  Is this run putting a hub BESIDE the one this computer already works from,
        instead of making it the one this computer works from?

        WHY THIS EXISTS. Exactly five things on a Windows account answer the question
        "which hub does this computer work from": the HUB_DIR line in ~\.hub\device.env,
        the HUB_DIR user environment variable, the two scheduled jobs, and Hermes'
        terminal.cwd. Every other wiring step is either inside the hub folder or keyed
        by the hub's own path (the assistant memory link mangles the path into its
        folder name, and Install-KitHubCli writes nothing at all for a hub that ships
        no commands), so it cannot collide. Before this switch existed, a second hub on
        one machine took all five, and the first hub's daily jobs went quiet with
        nothing on screen to say so: the same failure as a renamed folder
        (observations/a-renamed-folder-silences-every-tool-that-hardcoded-it).

        Who wants it: anyone keeping a work hub beside a personal one, a reader trying
        the book's hub before moving into it, and a screen recording that has to show a
        clean hub on a machine that already carries a full one.

        An environment variable rather than a parameter threaded through five
        functions, matching KB_SYNC_SOURCES and KB_HERMES_BIN: the installer makes the
        choice once, every wiring step reads it wherever it lands, and a test sets it
        in one place. #>
    return ($env:KB_BESIDE -eq '1')
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

    foreach ($c in @((Join-Path $HOME 'hub'), 'C:\hub', (Join-Path $HOME 'Documents\hub'),
                     (Join-Path $HOME 'dev\hub'))) {
        if (Test-KitHub $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Invoke-KitGit {
    <#  git, with its chatter silenced and with no power to abort the run.

        WHY THIS EXISTS. setup-hub.ps1 sets $ErrorActionPreference = 'Stop', and PowerShell
        7.3 and newer turn ANY line a native program writes to stderr into a terminating
        error ($PSNativeCommandUseErrorActionPreference, on by default). git writes plenty
        of ordinary progress there. On 2026-09-03 the line "Applied autostash." stopped the
        installer dead, halfway through, on a hub whose only sin was an edited file that had
        not been committed yet. A reader who has written something in their hub, which is
        the entire point of owning one, would have hit exactly that. Redirecting with 2>$null
        does not help: the error is raised before the redirection is considered.

        $LASTEXITCODE is what decides whether git actually failed, and it survives this. #>
    param([Parameter(Mandatory, ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @GitArgs 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    } finally {
        $ErrorActionPreference = $eap
    }
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
    Invoke-KitGit -C $Hub remote get-url origin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-KbOk "this hub lives only on this computer for now. Give it a home on GitHub when you are ready, and it will travel to your other machines."
        return
    }
    $branch = @(Invoke-KitGit -C $Hub rev-parse --abbrev-ref HEAD)[0]
    if (-not $branch -or $branch -eq 'HEAD') { $branch = 'main' }
    Invoke-KitGit -C $Hub pull --rebase --autostash -q origin $branch | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-KbOk "updated your hub to $(@(Invoke-KitGit -C $Hub log -1 --format='%h %s')[0])"
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

function Get-KitPython {
    <#  A python this PC will actually run, probed the way the hub's own CLI probes it.
        Windows rarely has `python3`; it has `python`, or the `py` launcher, or neither. #>
    foreach ($c in 'python3', 'python', 'py') {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        # PROVE IT RUNS. Windows ships stubs at %LOCALAPPDATA%\Microsoft\WindowsApps named
        # python.exe and python3.exe that are not Python at all: they open the Microsoft Store
        # page. Get-Command finds them, they are first on PATH, and baking one into a command
        # gives somebody a shop instead of an answer, with nothing on screen explaining it.
        # Asking for a version separates the real one from the shop in about 200 milliseconds.
        $ok = $false
        try {
            $eap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $cmd.Source --version 2>&1 | Out-Null
            $ok = ($LASTEXITCODE -eq 0)
        } catch { $ok = $false } finally { $ErrorActionPreference = $eap }
        if ($ok) { return $cmd.Source }
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
    $node = (Get-Command node -ErrorAction SilentlyContinue).Source
    $py   = Get-KitPython
    $n = 0
    Get-ChildItem $src -File |
        Where-Object { ($_.Name -eq 'hub' -or $_.Name -like 'hub-*') -and $_.Extension -notin '.env', '.md' } |
        ForEach-Object {
            $target = $_.FullName -replace '\\', '/'
            # WHICH RUNNER, read from the file's own first line.
            #
            # Every one of these got `bash "<file>" %*` until 2026-09-03, and 18 of the hub's
            # own commands are Python or Node. bash does not honour a shebang in a file it is
            # handed as an argument, it just reads it as bash, so `hub-check-voice` answered
            # "import: command not found" and every one of those 18 was broken when typed by
            # name. It went unnoticed because the `hub` dispatcher runs its siblings through
            # its own interpreter and never through these shims.
            #
            # No bash twin: kb_install_hub_cli makes symlinks and chmods them, and a kernel
            # reads the shebang. Windows has no shebang, which is the whole reason a .cmd
            # wrapper exists here at all.
            $shebang = ''
            try { $shebang = [string](Get-Content -LiteralPath $_.FullName -TotalCount 1 -ErrorAction Stop) } catch { }
            $runner = "`"$bash`" `"$target`""
            if ($shebang -match '^#!.*\bnode\b') {
                if ($node) { $runner = "`"$node`" `"$target`"" }
                else { Write-KbWarn "commands: $($_.Name) needs Node.js and this PC has none, so it was left pointing at bash and will not run."; }
            } elseif ($shebang -match '^#!.*\bpy(thon3?)?\b') {
                if ($py) { $runner = "`"$py`" `"$target`"" }
                else { Write-KbWarn "commands: $($_.Name) needs Python and this PC has none, so it was left pointing at bash and will not run."; }
            }
            @('@echo off', "$runner %*") |
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

function Set-KitHubDirRecord {
    <#  Where the hub is, in ~\.hub\device.env. Recorded the first time, and RE-RECORDED
        when the line names another folder: the daily jobs read this line to find the
        hub, so a stale one after a move is a hub that quietly files nothing
        (observations/a-renamed-folder-silences-every-tool-that-hardcoded-it). #>
    param([Parameter(Mandatory)][string]$Hub)
    if (Test-KitBeside) {
        $keep = Get-KitDeviceEnvValue 'HUB_DIR'
        if ($keep) { Write-KbOk "device.env: HUB_DIR still points at $keep. This hub sits beside it." }
        return
    }
    $dir = Join-Path (Get-KitHome) '.hub'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $f = Join-Path $dir 'device.env'
    $recorded = Get-KitDeviceEnvValue 'HUB_DIR'
    if (-not $recorded) {
        Add-Content -Path $f -Value "HUB_DIR=$Hub" -Encoding ascii
        return
    }
    $same = (Get-KitRealPath $recorded).TrimEnd('\').Equals((Get-KitRealPath $Hub).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
    if ($same) { return }
    $lines = @(Get-Content $f | ForEach-Object { if ($_ -match '^\s*HUB_DIR=') { "HUB_DIR=$Hub" } else { $_ } })
    Set-Content -Path $f -Value $lines -Encoding ascii
    Write-KbOk "device.env: HUB_DIR pointed at $recorded, not at this hub. Re-pointed it."
}

function Test-KitTaskPointsAt {
    <#  Does every action of this scheduled task run in this hub? A task registered for
        a hub that has since moved reads back perfectly and fires hourly against a folder
        that is gone, and until 2026-09-02 the installer looked at its name, saw it, and
        said "already scheduled". The folder is what decides, so the folder is compared. #>
    param([Parameter(Mandatory)]$Task, [Parameter(Mandatory)][string]$Hub)
    $want = (Get-KitRealPath $Hub).TrimEnd('\')
    foreach ($a in $Task.Actions) {
        if (-not $a.WorkingDirectory) { return $false }
        $wd = (Get-KitRealPath $a.WorkingDirectory).TrimEnd('\')
        if (-not $wd.Equals($want, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
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
        # A KIT SHIPS PRODUCTS, NOT ITS OWN TEST SUITE. Measured on a real install:
        # test-notebook-sync.sh and test-prompt-archive.sh were copied onto the reader's
        # PATH beside hub-due and hub-check-keys, so a reader could type a command that
        # runs the kit's tests against their own hub without ever being told what it was.
        Get-ChildItem $src -File |
            Where-Object { $_.Extension -ne '.md' } |
            Where-Object { $_.Name -notlike 'test-*' -and $_.Name -notlike '*-test*' -and $_.Name -notlike '*_test*' } |
            ForEach-Object {
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

        # The launchers. A .cmd rather than a shortcut, because a scheduled task and a terminal
        # both understand one, and %~dp0 is how it finds its other half: the program sits in the
        # same folder and is never looked for anywhere else.
        #
        # ONE TABLE, BOTH PLATFORMS, and the bash twin in lib.sh carries the same list. Before
        # 2026-08-29 only the prompt collector got a launcher here, so on Windows hub-check-keys
        # and hub-compile-rules were extension-less shell scripts nothing could run, while the
        # book printed both as commands a reader types.
        foreach ($pair in @(
            @{ src = 'prompt-harvest.js'; cmd = 'hub-prompt-harvest' },
            @{ src = 'compile-rules.js';  cmd = 'hub-compile-rules'  },
            @{ src = 'check-keys.js';     cmd = 'hub-check-keys'     },
            @{ src = 'due.js';            cmd = 'hub-due'            }
        )) {
            if (-not (Test-Path (Join-Path $bin $pair.src))) { continue }
            @('@echo off', "node `"%~dp0$($pair.src)`" %*") |
                Set-Content -Path (Join-Path $bin ($pair.cmd + '.cmd')) -Encoding ascii
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
        $devEnv = Join-Path (Get-KitHome) '.hub\device.env'
        Set-KitHubDirRecord -Hub $Hub
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
    if (Test-KitBeside) {
        Write-KbOk "prompt archive: left the daily job where it is. This hub sits beside the one this computer works from."
        return
    }

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
        if (Test-KitTaskPointsAt -Task $existing -Hub $Hub) {
            Write-KbOk "prompt archive: already scheduled on this computer"
            return
        }
        Write-KbOk "prompt archive: the daily job ran in $($existing.Actions[0].WorkingDirectory), not in this hub. Re-pointing it."
    } elseif ($existing) {
        Write-KbOk "prompt archive: replacing the old job, which opened a visible window every hour"
    }
    if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }

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

function Confirm-KitHermes {
    <#  The assistant itself, since Batch AK (2026-09-01): Hermes is the taught
        path from Chapter 3, and Claude Code is Chapter 5's optional developer
        door. This installer has never installed anything with a window - the
        Claude desktop app was always the reader's own download - and Hermes
        Desktop ships its own hermes-setup.exe, so the job here is to CONFIRM
        Hermes is present and say where to get it when it is not, never to
        fetch an app behind the wizard's back. #>
    if ((Test-KitAiTool 'hermes') -or (Test-KitHermesHere)) {
        Write-KbOk "Hermes is here"
        return $true
    }
    Write-KbWarn "Hermes is not on this PC yet. Download it from https://hermes-agent.nousresearch.com , run its installer, then run this installer again so it can finish the wiring."
    return $false
}

function Install-KitClaudeCode {
    <#  Claude Code, kept for Chapter 5's developer path. Install-KitPrereqs
        stopped calling this in Batch AK - the reader-facing installer confirms
        Hermes instead - but the function stays for the products and the
        developer chapter that still want it. Anthropic ships a Windows
        installer of their own, so use that rather than inventing a second way
        to install their product. #>
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
    # Hermes, not Claude Code, since Batch AK: the book teaches Hermes from
    # Chapter 3, and a developer who wants Claude Code gets it in Chapter 5.
    if (-not (Confirm-KitHermes)) { $missing += 'Hermes' }

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
            # Never add a room this hub already keeps under its other name, or the top-up
            # drops profile\ next to a perfectly good context\. See Get-KitRoomTwin.
            if (-not (Test-Path $dest) -and (Get-KitRoomTwin -Hub $Path -Name $_.Name)) {
                # nothing to do: the room is already here under its older name
            } elseif (-not (Test-Path $dest)) {
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
    Write-KitExpiryRecord -Hub $Path
    Write-KitDueFolder -Hub $Path
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

function Write-KitExpiryRecord {
    <#  The file that remembers WHEN each of your keys dies. The Windows twin of
        kb_seed_expiry_record in lib.sh.

        WHY IT EXISTS. A key is not just a thing you own, it is a thing with a lifespan,
        and the day it dies nothing announces it. The service simply starts saying no,
        and the message it gives back blames whatever asked rather than the date. Most
        keys never expire; the ones that do usually last a year, which is exactly long
        enough to have forgotten.

        WHY A FILE AND NOT A CALENDAR ENTRY. A calendar entry belongs to one account on
        one service. This travels in the folder with the key it is about, every computer
        reads it, the morning brief can read it, and hub-check-keys can read it. It also
        survives changing calendars, which people do.

        Never overwrites one that is already there, and holds no key: names, dates and
        links only. #>
    param([Parameter(Mandatory)][string]$Hub)
    $f = Join-Path $Hub 'secrets\expires.txt'
    if (Test-Path $f) { return }
    New-Item -ItemType Directory -Force (Join-Path $Hub 'secrets') | Out-Null
    # THE TEXT BELOW IS THE READER KIT'S COPY, BYTE FOR BYTE, and a test compares them.
    # There were THREE copies of this file and two of them had drifted: the bash twin and
    # this one both predated the @ convention that hub-check-keys implements, so a reader
    # with an established hub was handed a page that did not document the thing their own
    # tool was doing. Only the new-hub path, which copies from the kit, was current. If
    # you change one, change all three, and the tests will say so.
    $lines = @(
        '# When your keys run out.',
        '#',
        '# Some keys last forever. Some die after a year, and on that morning nothing tells you:',
        '# whatever used the key simply stops working, and the error blames the wrong thing. This',
        '# file is how your hub knows the date before you do.',
        '#',
        '# One key per line. Three things, separated by spaces:',
        '#',
        '#     NAME_OF_THE_KEY     the date it dies     the page you get a new one from',
        '#',
        '# Like this:',
        '#',
        '#     SOME_SERVICE_TOKEN  2027-03-14  https://example.com/account/tokens  # what it opens',
        '#',
        '# The date is written year first: 2027-03-14 is the 14th of March, 2027. Write `never`',
        '# instead of a date for a key you have checked and that does not expire. Write `-` instead',
        '# of a page when there is nowhere to go and get one, and put the steps in the words after',
        '# the # so the reminder still tells you what to do.',
        '#',
        '# The words after the # are for you. Say what the key opens, in your own words, because in',
        '# a year you will not remember what its name meant.',
        '#',
        '# A KEY THAT LIVES ON ONE COMPUTER. Nearly every key belongs in the locked store next door,',
        '# because putting it there once puts it on every computer you own. A few must not: a login',
        '# that belongs to one machine stops being that machine''s login the moment two machines share',
        '# it. Those keys are not in the store, so write down where they DO live, with an @, and read',
        '# it as the word "at":',
        '#',
        '#     SOME_LOGIN@/the/file/it/lives/in  2027-03-14  -  # what it opens, and how you renew it',
        '#',
        '# It is counted down exactly like every other line. The only difference is that `hub-check-keys`',
        '# knows not to go looking for it in your store, and so does not tell you it is missing.',
        '#',
        '# NEVER PUT A KEY ITSELF IN HERE. This file is plain text and travels with your folder.',
        '# Names, dates, file paths and links only. The keys themselves are locked, next door, or in',
        '# the one file the @ names.',
        '#',
        '# WHAT READS IT: your morning brief, which starts mentioning a key two months before it',
        '# dies (once a week), then every morning for the last fortnight, and every morning after',
        '# it has died. Changing the date here is the off switch. And `hub-check-keys`, any time',
        '# you want to ask.'
    )
    Set-KbTextFile -Path $f -Lines $lines
    Write-KbOk "keys: made secrets\expires.txt, where you write down when a key runs out"
}

function Write-KitDueFolder {
    <#  The room that holds everything in this person's life with a last day. The Windows twin of
        kb_seed_due_folder in lib.sh.

        WHY IT EXISTS. A calendar reminder fires on a date and knows nothing else, so it goes off
        about something already done, and once that has happened a few times a person stops
        reading reminders. The one that mattered then goes past too. This room is the other shape:
        two dates per thing, and how loud the hub gets follows how much of the window between
        them is left.

        WHY IT IS SEEDED HERE AS WELL AS SHIPPED IN starter-hub/. Copy-KitStarterHub tops up a hub
        that already exists, which covers almost everybody, but it needs the network and the
        starter repository. This costs nothing and covers the reader whose top-up could not run.
        Same reason Write-KitExpiryRecord exists.

        THE TEXT BELOW IS A COPY OF teach-it-once-kit/starter-hub/due/README.md, byte for byte,
        and test.sh compares them. Two copies of one file is two places to fix a typo, and the one
        nobody edits is the one every reader ends up with. Change the kit's copy, then copy it here
        and into the kb_seed_due_folder twin in lib.sh.

        Never overwrites a README that is already there, and never touches an obligation file. #>
    param([Parameter(Mandatory)][string]$Hub)
    $f = Join-Path $Hub 'due\README.md'
    if (Test-Path $f) { return }
    New-Item -ItemType Directory -Force (Join-Path $Hub 'due') | Out-Null
    $lines = @(
        '# due - the things with a last day'
        ''
        '**This room starts empty, and an empty one costs you nothing.** It fills the first time you tell'
        'your hub about something with a deadline (Chapter 33). If you never do, you have an empty folder'
        'and you have lost nothing.'
        ''
        '## Why this is not a reminder'
        ''
        'A calendar reminder fires on a date and knows nothing else. It cannot tell whether you already did'
        'the thing, so it goes off afterwards, and after that happens a few times you stop reading'
        'reminders. Then one of them stops on its last occurrence whether or not the job got done, and that'
        'is the one that mattered.'
        ''
        'Everything in here is built to fix both halves of that.'
        ''
        '## The window'
        ''
        'Every file in here holds **the first day you can do the thing, and the last day you still can.**'
        'Not a due date. A window.'
        ''
        'How loud your hub gets follows how much of the window is left, as a fraction:'
        ''
        '| Left of the window | Your hub |'
        '|---|---|'
        '| more than half | says it once when the window opens, then at most monthly |'
        '| half to a quarter | a line in your brief about every fortnight |'
        '| a quarter to a tenth | its own line, near the top, about weekly |'
        '| under a tenth, and always the last day | every morning |'
        ''
        '**One rule, whether the window is a week or a year.** That is the whole reason you can have a'
        'hundred of these. There is nothing to tune per item, and if a thing feels like it needs its own'
        'setting, the window is wrong rather than the rule.'
        ''
        '## What a file looks like'
        ''
        'One file per thing, named however you like:'
        ''
        '```'
        'due/car-service.md'
        ''
        'TITLE:          Car service before the warranty runs out'
        'DONE-WHEN:      The car has been serviced at a garage the warranty accepts.'
        'COST-IF-MISSED: The warranty ends. A gearbox after that is mine to pay for.'
        'SELF-CHECK:     none'
        'SELF-CHECK-ARG:'
        'REPEATS:        yearly'
        'LINK:           https://example.com/book-a-service'
        'SOURCE:         me, 2026-08-29'
        ''
        '## Windows'
        'STRIP: 2026-09-01 2027-02-28 open'
        ''
        '## Log'
        '- 2026-08-29 created, window 2026-09-01 to 2027-02-28'
        '```'
        ''
        'Plain text. Read it, edit it, delete it. The program writes the same shape you would.'
        ''
        '**A repeating thing is ONE file that grows a new window each time**, never one file per occurrence.'
        'That is what keeps a hundred of these at a hundred files instead of thousands.'
        ''
        '## The four questions, asked once'
        ''
        'When you add one, answer four things and never be asked again:'
        ''
        '1. What is true when this is finished?'
        '2. From when to when can you do it?'
        '3. What does it cost you if it slips?'
        '4. **How could your hub tell you did it, without asking you?**'
        ''
        'The fourth is the one that matters and the one everybody skips. Some things can answer it. A key is'
        'replaced when the date in `secrets/expires.txt` moves. A backup happened if the file is newer than'
        'the window. Those close themselves and never nag you again after you act, which is exactly the'
        'failure that kills every reminder app.'
        ''
        'Most things cannot answer it, and **that is a fine answer**. Nobody can tell your hub that you'
        'submitted a timesheet into somebody else''s website. Those say so and wait for you to say the word.'
        'Ask the question anyway, every time, because knowing which kind a thing is changes what you build'
        'around it.'
        ''
        '## No date, not eligible'
        ''
        '`hub-due add` refuses anything without both dates, in those words. That refusal is the only thing'
        'standing between this folder and a to-do app you stop maintaining.'
        ''
        '## Three states, and only three'
        ''
        '**open, done, dropped.** Done can happen by itself when there is a self check. **Dropped only ever'
        'comes from you**, and it deletes the file and everything it remembers, which is why the command'
        'makes you type `--yes`.'
        ''
        'Something whose window closed without being done **stays open**. Nothing tidies it away, because'
        'for a deadline "nobody got to it" is the failure, not a quiet success.'
        ''
        '## Your keys are already in here'
        ''
        'If you have `secrets/expires.txt` from Chapter 27, `hub-due` reads it and treats each key as one of'
        'these. You never write a date in two places, and there is one thing nagging you rather than two'
        'that disagree. Moving the date in that file is still the off switch, and it is now also the proof:'
        'moving it forward is what replacing a key looks like from outside, so the reminder closes itself.'
        ''
        '## You do not need a calendar'
        ''
        'Not for any of this. If you do have one, your assistant can add **one entry per thing**, and one is'
        'the whole rule. It goes on the day your hub starts being loud, not on the day the thing dies, and'
        'the death date goes in the title so the single entry says both. Never two entries about one date:'
        'the day they disagree with each other you stop believing either.'
        ''
        'It comes out again when you finish, as long as the day has not passed yet. That is the part that'
        'makes one entry safe, because otherwise an entry you already acted on sits there being wrong. A day'
        'that has already gone by is left alone: it is a record of what happened.'
        ''
        'You can also go the other way and add one from your phone, by writing an event that says'
        '`hub: from 1 Feb`. **The calendar never decides when you get nagged and never knows whether you'
        'acted.**'
        ''
        '## The commands'
        ''
        '```'
        'hub-due                     everything, loudest first'
        'hub-due today               at most three, which is what your morning brief reads'
        'hub-due add <name> ...      make one'
        'hub-due done <name>         you did it'
        'hub-due drop <name> --yes   delete it'
        'hub-due check               run the self checks, close what is provably done'
        '```'
        ''
        'The card is `procedures/what-runs-out-and-when.md` in the kit. Chapter 33.'
    )
    Set-KbTextFile -Path $f -Lines $lines
    Write-KbOk "deadlines: made due\README.md, the room for everything with a last day"
}

function Write-KitMcpConfig {
    <#  The file that tells CLAUDE CODE where your notebook is, and nothing else.

        It used to say "your assistant", which was an over-claim the moment the book
        stopped being a Claude Code book. Hermes never reads a folder .mcp.json:
        checked in the Hermes source, there is not one reference to it. So a hub does
        NOT carry its own MCP configuration and this installer must not imply that it
        does. Hermes keeps its own, and the commands are `hermes mcp add`,
        `hermes mcp catalog` and `hermes mcp install <name>`, all three confirmed
        against the binary before being printed.

        The file stays, because Chapter 5 keeps Claude Code in VS Code as the
        developer path and this is how that path finds the notebook. It NAMES the
        credential rather than carrying it, so it holds no secret and is safe to keep
        in the folder. Never overwrites one you already have. #>
    param([Parameter(Mandatory)][string]$Hub)
    $f = Join-Path $Hub '.mcp.json'
    if (Test-Path $f) { Write-KbOk "notebook: .mcp.json is already there, left as you have it"; return }
    $lines = @(
        '{',
        '  "_comment": [',
        '    "THIS FILE IS READ BY CLAUDE CODE, AND BY NOTHING ELSE IN THIS BOOK.",',
        '    "Hermes does not read it. Checked in the Hermes source: there is not one reference",',
        '    "to a folder .mcp.json anywhere in it. Hermes keeps its own connections, and you",',
        '    "add one with `hermes mcp add`, or pick from `hermes mcp catalog` and install it",',
        '    "with `hermes mcp install <name>`.",',
        '    "What it does do, for Claude Code: it says where your notebook is, and it NAMES the",',
        '    "credential rather than carrying it. ${MENERIO_API_KEY} is read from this computer''s",',
        '    "environment when Claude Code starts, so this file holds no secret and is safe to",',
        '    "keep in the folder. The value itself lives locked in secrets/, and travels with the",',
        '    "folder to every computer you own.",',
        '    "Delete this file if you do not use Claude Code. Nothing else in the book needs it."',
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
    Write-KbOk "notebook: wrote $f for Claude Code, and it names your credential instead of carrying it."
    Write-Host "   notebook: Hermes does not read that file. To give Hermes the same notebook:"
    Write-Host "     hermes mcp add    (or: hermes mcp catalog, then hermes mcp install <name>)"
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

    # 2. The hourly catch-up, for whatever happened while the PC was asleep. A hub
    #    sitting beside another one stops here: the hook above is inside this folder and
    #    is its own, but the hourly job is one name for the whole account.
    if (Test-KitBeside) {
        Write-KbOk "notebook: left the hourly catch-up where it is. This hub sits beside the one this computer works from."
        return
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
        if (Test-KitTaskPointsAt -Task $existing -Hub $Hub) {
            Write-KbOk "notebook: the hourly catch-up is already on this PC"
            return
        }
        Write-KbOk "notebook: the hourly catch-up ran in $($existing.Actions[0].WorkingDirectory), not in this hub. Re-pointing it."
    } elseif ($existing) {
        Write-KbOk "notebook: replacing the old hourly job, which opened a visible window every hour"
    }
    if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
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
    Write-KitExpiryRecord -Hub $Hub
    Write-KitDueFolder -Hub $Hub
    Install-KitNotebookSync -Hub $Hub
    Set-KitNotebookEnv -Hub $Hub
}

# =============================================================================
# THE SKILLS ROOM, AND THE ONE RULE THAT KEEPS IT A SINGLE ROOM
#
# The Windows twin of kb_wire_skills in lib.sh, and it exists for the same defect.
# Until 2026-09-01 both installers ran three lines that looked harmless: if the hub
# had a .claude\skills folder, junction .agents\skills to it and say "assistants
# other than Claude Code can now read them too". On a hub whose recipes live in the
# VISIBLE skills\ room, which is the arrangement the book teaches, that sentence was
# false. The starter top-up had just created an EMPTY .claude\skills, so the junction
# pointed every non-Claude assistant at an empty folder while the reader's recipes sat
# in skills\ untouched and unreachable. Measured on a real reader-shaped hub: 0 recipes
# reachable, 6 present, and a green tick printed over it.
#
# So the rule is one real folder and links to it, never two real folders, and the
# installer must COUNT what it wired rather than trust that it wired anything.
#
# This is a PORT and not shared code, for the reason at the top of this file: lib.sh
# is bash, a Windows reader downloads one file, and the link here has to be a JUNCTION
# because a junction needs no administrator rights. Same names in the same order as the
# bash, so a change to one is easy to carry to the other.
# =============================================================================

function ConvertTo-KbJsonString {
    <#  One string, quoted for JSON.

        Windows is why this cannot be skipped. Every path here carries backslashes,
        and "C:\hub\skills" is not valid JSON - it has to go out as
        "C:\\hub\\skills" or Hermes reads a path with escape sequences in it. .NET's
        Replace and not PowerShell's -replace, because -replace is a regular
        expression on both sides and backslashes in a regex replacement are their own
        small trap. #>
    param([string]$Text)
    return '"' + ([string]$Text).Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-KitRealPath {
    <#  Where a path really lands, following a junction to whatever it points at.

        PowerShell 5.1 has no ResolveLinkTarget, and Resolve-Path on a junction hands
        back the junction rather than its target, so this walks .Target itself - the
        same property Join-KitMemory above already reads. A path that does not exist
        still gets a normalised answer, because two spellings of the same absent
        folder have to compare equal. The loop has a ceiling so a junction pointing
        at itself cannot hang an installer. #>
    param([string]$Path)
    if (-not $Path) { return '' }
    $p = $Path
    for ($i = 0; $i -lt 16; $i++) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $item -or -not $item.LinkType) { break }
        $t = @($item.Target)[0]
        if (-not $t) { break }
        $p = $t
    }
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\', '/')
}

function Get-KitRecipeCount {
    <#  How many recipes a folder holds, counting both shapes the book has ever used:
        a flat <name>.md, and a <name>\SKILL.md folder. Always returns a number and
        never throws, so it is safe inside an assertion.

        The two levels are spelled out rather than done with -Recurse, and that is
        deliberate: -Recurse would count a recipe's own notes as further recipes and
        report a number nobody can reconcile with what they see in the folder.

        Windows needs no equivalent of the bash `find -L`, because a junction is
        resolved by the filesystem itself and Get-ChildItem walks straight through
        one. The bash twin learned that the hard way. #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return 0 }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -File -Filter '*.md' -Force -ErrorAction SilentlyContinue)) {
        [void]$seen.Add($f.FullName)
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue)) {
        $s = Join-Path $d.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $s -PathType Leaf) { [void]$seen.Add($s) }
    }
    return $seen.Count
}

function Get-KitSkillsRoom {
    <#  The folder this reader's recipes ACTUALLY live in. Detected, never assumed: a
        hub built under the Claude-only batch keeps them in .claude\skills, and a hub
        built by the book keeps them in the visible skills\. The visible room wins
        when both hold something, because it is the one the reader can see and the one
        the book walks them through. #>
    param([Parameter(Mandatory)][string]$Hub)
    $visible = Join-Path $Hub 'skills'
    if ((Get-KitRecipeCount $visible) -gt 0) { return $visible }
    $hidden = Join-Path $Hub '.claude\skills'
    if ((Get-KitRecipeCount $hidden) -gt 0) { return $hidden }
    # An empty or brand new hub: the visible room is the right answer, not a hidden
    # folder we would then have to teach as a room.
    return $visible
}

function Set-KitSkillsGitIgnore {
    <#  Keep git honest about the hidden doors. Git on Windows sees a junction as an
        ordinary folder, so `git add -A` would commit the recipes a second time under
        .claude\skills and a Linux clone would then hold two real rooms that drift, the
        one thing the single room exists to prevent. Every door that is a LINK is listed
        in .gitignore and untracked; the real room is never touched, whatever its name
        (a Claude-era hub keeps .claude\skills tracked). #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][string]$Real)
    if (-not (Test-Path -LiteralPath (Join-Path $Hub '.git'))) { return }
    $gi = Join-Path $Hub '.gitignore'
    $realPath = Get-KitRealPath $Real
    foreach ($rel in @('.claude/skills', '.agents/skills')) {
        $door = Join-Path $Hub ($rel -replace '/', '')
        if (-not (Test-Path -LiteralPath $door)) { continue }
        $item = Get-Item -LiteralPath $door -Force -ErrorAction SilentlyContinue
        if ($item -and -not $item.LinkType -and ((Get-KitRealPath $door) -eq $realPath)) { continue }
        $lines = @(); if (Test-Path -LiteralPath $gi) { $lines = @(Get-Content -LiteralPath $gi) }
        if (-not ($lines -contains $rel) -and -not ($lines -contains "$rel/")) { Add-Content -LiteralPath $gi -Value $rel }
        $tracked = (& git -C $Hub ls-files $rel 2>$null)
        if ($tracked) {
            & git -C $Hub rm -r -q --cached $rel 2>$null | Out-Null
            Write-KbOk "skills: $rel is a door, not a room, so git stops tracking it (the recipes stay tracked in the real room)"
        }
    }
}

function Set-KitRoomLink {
    <#  Make $Link resolve to $Room, whatever it is today. Repairs a junction pointing
        somewhere else, and refuses to destroy a real folder that holds work: that
        folder is carried in and moved aside with a timestamp, never deleted. Returns
        $true when the link ends up pointing at the room. #>
    param([Parameter(Mandatory)][string]$Link, [Parameter(Mandatory)][string]$Room)

    # Already resolving to the room, and that covers two cases at once: a link written
    # earlier with a different spelling of the same path, AND the hub whose real room
    # IS this very folder. Without the second, a Claude-era hub whose recipes live in
    # .claude\skills would have this function copy that folder into itself and then
    # move it aside, which is the worst outcome in this file.
    if ((Test-Path -LiteralPath $Link) -and ((Get-KitRealPath $Link) -eq (Get-KitRealPath $Room))) {
        return $true
    }

    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        # .Delete() on the junction removes the reparse point and leaves whatever it
        # pointed at alone. A recursive delete would walk through it and take the
        # reader's recipes with it, which is the one mistake this whole file exists to
        # avoid, so this line is not a style choice.
        try { $item.Delete() } catch { return $false }
    }
    elseif ($item) {
        if ((Get-KitRecipeCount $Link) -gt 0) {
            foreach ($f in @(Get-ChildItem -LiteralPath $Link -Force -ErrorAction SilentlyContinue)) {
                $dest = Join-Path $Room $f.Name
                if (-not (Test-Path -LiteralPath $dest)) {
                    Copy-Item -LiteralPath $f.FullName -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $stash = "$Link.replaced-$(Get-Date -Format yyyyMMddHHmmss)"
            try { Move-Item -LiteralPath $Link -Destination $stash -ErrorAction Stop } catch { return $false }
            Write-KbOk "skills: recipes found in $Link were carried into $Room, and the old folder is kept at $stash"
        }
        else {
            # The empty placeholder the old installer made. Nothing to lose. .NET's
            # recursive delete stops at a reparse point rather than following it, and
            # the junction case above has already been taken, so this only ever
            # removes a real and recipe-free folder.
            try { [System.IO.Directory]::Delete($Link, $true) } catch { return $false }
        }
    }

    New-Item -ItemType Directory -Force (Split-Path $Link -Parent) | Out-Null
    try { New-Item -ItemType Junction -Path $Link -Target $Room -ErrorAction Stop | Out-Null }
    catch { return $false }
    return $true
}

function Set-KitHermesSkillsDir {
    <#  Tell Hermes to read the reader's room, WITHOUT throwing away anything already
        configured there. `hermes config set` REPLACES a list, so a blind set is how a
        reader loses the team folder they added last month. Read, merge, write.

        WHICH hermes is settled by KB_HERMES_BIN, defaulting to whatever is on PATH.
        That is not decoration: on 2026-09-01 an early run of the bash twin, exercised
        from a scratch folder, wrote a temp path into the author's own live config,
        because the function found the real hermes on PATH. A test that can reach the
        real thing eventually will. The same hook covers the PC where Hermes is
        installed but not on PATH. #>
    param([Parameter(Mandatory)][string]$Room)

    $bin = if ($env:KB_HERMES_BIN) { $env:KB_HERMES_BIN } else { 'hermes' }
    if (-not (Get-Command $bin -ErrorAction SilentlyContinue)) {
        Write-KbOk "skills: Hermes is not on this PC yet, so there is nothing to tell it. Run this again once it is."
        return
    }

    # `hermes config get` prints one path per line, each prefixed "- ". Verified
    # against a real Hermes 0.21.0 before any of this was written.
    $cur = @(Get-KitHermesList -Key 'skills.external_dirs')

    if ($cur -contains $Room) {
        Write-KbOk "skills: Hermes already reads $Room"
        return
    }

    $json = '[' + ((@($cur) + @($Room) | ForEach-Object { ConvertTo-KbJsonString $_ }) -join ',') + ']'
    # Through Invoke-KitHermesConfigSet, never &: PowerShell 5.1 eats the JSON's
    # quotes on the way to a native argv, and Hermes then stores a string it ignores.
    if (Invoke-KitHermesConfigSet -Key 'skills.external_dirs' -Value $json) {
        # READ IT BACK. Hermes 0.20.0 stores a JSON list as a plain string, which its
        # own readers then ignore, so the setting lands and does nothing. A success
        # line over an inert setting is the workspace lie again, so the truth is said
        # out loud instead. Not fatal: the links keep every recipe reachable.
        if (@(Get-KitHermesList -Key 'skills.external_dirs') -contains $Room) {
            Write-KbOk "skills: Hermes now reads $Room"
        } else {
            Write-KbWarn "skills: this Hermes stored the room as text it does not read, so Hermes
     itself will not see $Room until Hermes is updated. Your recipes stay
     reachable through the links either way."
        }
    } else {
        Write-KbWarn "skills: could not tell Hermes to read $Room.
     Run this by hand: hermes config set skills.external_dirs '$json'"
    }
}

function Connect-KitSkills {
    <#  The whole job: find the real room, point every other name at it, tell Hermes
        where it is, then PROVE it by counting what is reachable through the door the
        old code got backwards. #>
    param([Parameter(Mandatory)][string]$Hub)

    $room = Get-KitSkillsRoom -Hub $Hub
    New-Item -ItemType Directory -Force $room | Out-Null
    $real = Get-KitRealPath $room
    $have = Get-KitRecipeCount $real

    # Claude Code only ever looks in .claude\skills, and the book keeps that door open
    # for the developer's chapter, so it becomes a JUNCTION to the visible room. This
    # is the direction the old code had backwards.
    $claude = Join-Path $Hub '.claude\skills'
    $agents = Join-Path $Hub '.agents\skills'
    if (-not (Set-KitRoomLink -Link $claude -Room $real)) {
        Write-KbWarn "skills: could not point $claude at $real"
    }
    # .agents\skills is the same story for everything that is not Claude Code.
    if (-not (Set-KitRoomLink -Link $agents -Room $real)) {
        Write-KbWarn "skills: could not point $agents at $real"
    }

    Set-KitHermesSkillsDir -Room $real
    Set-KitSkillsGitIgnore -Hub $Hub -Real $real

    # THE ASSERTION THAT WOULD HAVE CAUGHT THE OLD BUG ON THE DAY IT SHIPPED. A green
    # tick over an empty room is worse than a red one, because the reader stops
    # looking.
    $reach = Get-KitRecipeCount $claude
    if ($have -gt 0 -and $reach -eq 0) {
        Write-KbWarn "skills: $have recipe(s) live in $real but nothing can reach them through $claude.
     Nothing was moved and nothing was lost. Do not trust a recipe to fire until this is sorted."
        return $false
    }
    if ($have -gt 0) {
        Write-KbOk "skills: $have recipe(s) in $real, and every assistant reads that one folder"
    } else {
        Write-KbOk "skills: your room is ready at $real, and every assistant already knows to read it"
    }
    return $true
}

# =============================================================================
# TELLING HERMES WHERE THE HUB IS, AND PROVING IT
#
# The Windows twin of kb_point_hermes_at_hub in lib.sh, and the long note above that
# function is the one to read. The short version: six ways of pointing Hermes at a
# folder are known, measured on hardware, and only two of them work. Four are silent
# no-ops and the kit shipped one of them, `hermes config set workspace <hub>`, which
# is not a recognised key at all.
#
#   hermes config set workspace <hub>   not a key. SHIPPED, with the warning sent to
#                                       /dev/null and a green tick printed over it
#   --in <dir> on the -z one-shot       read only in cmd_chat, which -z never reaches
#   cd before launching                 ignored; the agent lands in the home folder
#   WorkingDirectory= in the unit       pinned to HERMES_HOME upstream on purpose
#   terminal.cwd                        WORKS
#   --workdir on a cron job             WORKS, per job, and beats terminal.cwd
#
# AND IT IS VERIFIED BY A FILE READ, NEVER BY READING THE SETTING BACK. Three
# mechanisms in this family already read back perfectly and did nothing. The failure
# this guards against is the worst shape there is: AGENTS.md is found from the launch
# directory, so the assistant knows the house rules and still cannot open the folder
# those rules describe. From the outside that looks like it is working.
# =============================================================================

function Get-KitHermesBin {
    <#  Which hermes to talk to. See Set-KitHermesSkillsDir for why this hook exists
        rather than a bare 'hermes'. #>
    if ($env:KB_HERMES_BIN) { return $env:KB_HERMES_BIN }
    return 'hermes'
}

function Test-KitHermesHere {
    [bool](Get-Command (Get-KitHermesBin) -ErrorAction SilentlyContinue)
}

function ConvertFrom-KbYamlScalar {
    <#  Strip the single quotes a YAML writer puts around a value that would otherwise be
        ambiguous, and unescape the doubled quotes inside.

        WHY THIS IS NOT OPTIONAL. Every deny rule the kit ships starts with `*`, and a `*`
        at the start of a YAML scalar means an ALIAS, so `hermes config get` hands all
        eighteen of them back QUOTED. Reading them back without this is how a second
        install run added the same eighteen rules again AND wrote the quote characters
        into them: the list grew to thirty-six entries, half of which matched no command
        at all. Found by running the installer twice on real hardware. A stub that echoes
        back whatever it was given can never show this, and ours did not.

        The loop exists because a config already corrupted that way carries several
        layers. #>
    param([string]$Text)
    $v = [string]$Text
    while ($v.Length -gt 1 -and $v.StartsWith("'") -and $v.EndsWith("'")) {
        $v = $v.Substring(1, $v.Length - 2).Replace("''", "'")
    }
    return $v
}

function Get-KitHermesList {
    <#  A list-valued Hermes setting, one clean value per line. `config get` prints
        "- value" per entry, an unset key prints "Config key not set" and exits 1, and an
        empty list prints []. All three mean "nothing" to a caller merging into it.

        ONLY "- " LINES ARE ENTRIES. Hermes 0.20.0 stores a JSON list as one plain
        string and `config get` echoes that string back RAW, and a read that treated
        the echo as an entry fed it into the next merge, which nested the whole list
        one level deeper on every single run. Measured on the book's own rehearsal
        server. A string is not a list, so it is not returned as one. #>
    param([Parameter(Mandatory)][string]$Key)
    if (-not (Test-KitHermesHere)) { return @() }
    $out = @()
    try { $out = @(& (Get-KitHermesBin) config get $Key 2>$null) } catch { return @() }
    return @($out |
        Where-Object { [string]$_ -match '^\s*-\s' } |
        ForEach-Object { ConvertFrom-KbYamlScalar (([string]$_ -replace '^\s*-\s*', '').Trim()) } |
        Where-Object { $_ -and $_ -ne '[]' -and $_ -notlike 'Config key not set*' })
}

function Test-KitHermesCredential {
    <#  Is there a provider Hermes can actually call? Without one the file-read proof
        cannot run, and reporting that as a failed setting would be a lie: on a first
        install the reader has not signed in yet, and an installer that cries wolf on
        every fresh PC teaches people to ignore it. #>
    if (-not (Test-KitHermesHere)) { return $false }
    $out = & (Get-KitHermesBin) auth list 2>$null
    return [bool](@($out) -match '\(\d+ credential')
}

function ConvertTo-KbNativeArg {
    <#  One argument, quoted for a native process's command line by the rules
        CommandLineToArgvW parses it back with. PowerShell 5.1's own binder does NOT
        do this for an embedded quote: measured against a real Hermes 0.20.6, a JSON
        array passed with & arrived in argv with every quote eaten, Hermes called it
        invalid YAML/JSON, stored a STRING that "isinstance-gated readers will
        ignore", and all eighteen deny rules shipped as decoration. Escaped by hand
        and carried on a hand-built line, the same value arrives byte for byte. #>
    param([Parameter(Mandatory)][string]$Value)
    # Backslashes directly before a quote double, the quote itself is escaped, and
    # trailing backslashes double so the closing quote survives them.
    $s = $Value -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

function Invoke-KitHermesConfigSet {
    <#  hermes config set <key> <value>, carried on a hand-built argument line
        through Start-Process, exactly as Invoke-KitHermesOneShot carries the -z
        prompt and for the same reason: & mangles an embedded quote under 5.1.
        Returns $true only when hermes exited 0. #>
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    $argLine = 'config set ' + $Key + ' ' + (ConvertTo-KbNativeArg $Value)
    $o = [System.IO.Path]::GetTempFileName()
    $e = [System.IO.Path]::GetTempFileName()
    $code = 1
    try {
        $p = Start-Process -FilePath (Get-KitHermesBin) -ArgumentList $argLine `
                -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
        # Touch the handle BEFORE the process can exit, or ExitCode reads back
        # $null and a successful set is reported as a failure.
        $null = $p.Handle
        if ($p.WaitForExit(60 * 1000)) { $code = $p.ExitCode } else { try { $p.Kill() } catch { } }
    } catch { }
    foreach ($f in @($o, $e)) { try { [System.IO.File]::Delete($f) } catch { } }
    return ($code -eq 0)
}

function Invoke-KitHermesOneShot {
    <#  One -z prompt, with a ceiling on how long it may take. Windows has no
        timeout(1), and an installer that never returns is worse than one that says it
        could not check, so the process is started, waited on, and killed if it
        outstays. Returns everything it printed, out and err together. #>
    param([Parameter(Mandatory)][string]$Prompt, [int]$Seconds = 180)
    # THE PROMPT IS QUOTED BY HAND, AND IT HAS TO BE. Start-Process -ArgumentList takes
    # an array and then joins it with spaces WITHOUT quoting anything, so a sentence
    # arrives at hermes.exe as sixteen separate arguments and -z gets the word "Read".
    # Caught by running it rather than by reading it, which is the only way this kind
    # of thing ever turns up.
    $argLine = '-z "' + ($Prompt -replace '"', '\"') + '"'
    $o = [System.IO.Path]::GetTempFileName()
    $e = [System.IO.Path]::GetTempFileName()
    $text = ''
    try {
        $p = Start-Process -FilePath (Get-KitHermesBin) -ArgumentList $argLine `
                -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
        if (-not $p.WaitForExit($Seconds * 1000)) {
            try { $p.Kill() } catch { }
        }
    } catch { }
    foreach ($f in @($o, $e)) {
        try { $text += (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue) } catch { }
        try { [System.IO.File]::Delete($f) } catch { }
    }
    return [string]$text
}

function Test-KitHermesReadsHub {
    <#  THE PROOF. Returns 'yes', 'no' or 'unavailable', so a caller branches on the
        word rather than on an exit status.

        Three details, and every one of them is load-bearing.

        The token is never in the prompt. If it were, a model that could not open the
        file could parrot it back and the check would pass on nothing.

        The file is named RELATIVELY. An absolute path is read correctly from any
        working directory at all, which is the exact thing under test.

        The OUTPUT decides, never the exit code. A one-shot that reached no model
        still exits 0, measured: "API call failed after 3 retries: HTTP 429" on
        stdout, exit status 0. #>
    param([Parameter(Mandatory)][string]$Hub)
    if (-not (Test-Path -LiteralPath $Hub -PathType Container)) { return 'unavailable' }
    if (-not (Test-KitHermesHere)) { return 'unavailable' }
    if (-not (Test-KitHermesCredential)) { return 'unavailable' }

    $marker = '.hub-reachable-check'
    $token  = 'HUBREACH' + (Get-Date -Format yyyyMMddHHmmss) + $PID
    $file   = Join-Path $Hub $marker
    try { Set-KbTextFile -Path $file -Lines @($token) } catch { return 'unavailable' }
    try {
        $out = Invoke-KitHermesOneShot -Prompt "Read the file $marker in your current folder and reply with its contents and nothing else."
    } finally {
        try { [System.IO.File]::Delete($file) } catch { }
    }
    $script:KitHubProofSaid = ([string]$out).Trim()
    if ($out -and $out.Contains($token)) { return 'yes' }

    # NOT AN ANSWER ABOUT THE FOLDER AT ALL. If no model ran, the one-shot says nothing
    # about terminal.cwd, and blaming the wiring for a provider error is the same lie as
    # the workspace line, just pointed the other way. Measured: on the test server the
    # account default was a model its own subscription cannot serve, so every one-shot
    # came back "HTTP 400 ... not supported when using Codex with a ChatGPT account" and
    # the installer told the reader their hub was half connected. It was not.
    foreach ($sign in 'HTTP 4', 'HTTP 5', 'API call failed', 'not supported', 'ate limit',
                       'no authentication', 'not configured', 'credit', 'quota',
                       'nauthorized', 'Connection', 'timed out', 'o provider',
                       'nference provider') {
        if ([string]$out -like "*$sign*") { return 'unreachable' }
    }
    return 'no'
}

function Set-KitHermesHub {
    <#  Set terminal.cwd to the hub's absolute path, then prove the hub is reachable.
        Never sets `workspace`, which is the line this replaces.

        KB_SKIP_HUB_PROOF=1 skips the model call, for the test matrix and for a reader
        on a metered plan who would rather not spend a request on a check. #>
    param([Parameter(Mandatory)][string]$Hub)

    if (-not (Test-Path -LiteralPath $Hub -PathType Container)) {
        Write-KbWarn "hub: no folder at $Hub"
        return $false
    }
    $abs = Get-KitRealPath $Hub

    if (Test-KitBeside) {
        Write-KbOk "hub: left Hermes pointing where it was. This hub sits beside the one this computer works from."
        return $true
    }

    if (-not (Test-KitHermesHere)) {
        Write-KbOk "hub: Hermes is not on this PC yet, so there is nothing to point at $abs. Run this again once it is."
        return $true
    }
    $bin = Get-KitHermesBin

    $cur = ''
    try { $cur = ([string](@(& $bin config get terminal.cwd 2>$null) | Select-Object -First 1)).Trim() } catch { }
    if ($cur -eq $abs) {
        Write-KbOk "hub: Hermes already works in $abs"
    } else {
        & $bin config set terminal.cwd $abs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-KbWarn "hub: could not tell Hermes to work in $abs.
     Run this by hand: hermes config set terminal.cwd $abs"
            return $false
        }
        Write-KbOk "hub: Hermes now works in $abs"
    }

    if ($env:KB_SKIP_HUB_PROOF -eq '1') { return $true }

    switch (Test-KitHermesReadsHub -Hub $abs) {
        'yes' {
            Write-KbOk "hub: and it can read a file in there, checked just now rather than assumed"
            return $true
        }
        'unavailable' {
            Write-KbOk "hub: no provider is connected yet, so I could not prove the folder is readable.
       Sign in, run this again, and it will check."
            return $true
        }
        'unreachable' {
            # Say what actually happened, and do not report a wiring failure that is not one.
            $said = ''
            if ($script:KitHubProofSaid) {
                $said = (($script:KitHubProofSaid -split "`n")[0])
                if ($said.Length -gt 160) { $said = $said.Substring(0, 160) }
            }
            Write-KbWarn "hub: I set the folder, but could not check it: Hermes could not reach a model
     just now. That is a provider problem and not a folder problem, so nothing here is
     broken. It said: $said
     Sort the model or provider out, run this again, and it will check."
            return $true
        }
        default {
            # The answer is quoted because "half connected" and "the model ignored
            # the ask" look identical from the outside, and only the reply tells
            # them apart. A real Windows e2e burned a round trip on exactly this.
            $said = ''
            if ($script:KitHubProofSaid) {
                $said = (($script:KitHubProofSaid -split "`n")[0])
                if ($said.Length -gt 160) { $said = $said.Substring(0, 160) }
            }
            Write-KbWarn "hub: Hermes says it works in $abs but could not read a file that is sitting there.
     That is the half-connected shape: it knows the rules in AGENTS.md and cannot open
     the folder those rules describe. It answered: $said
     Do not trust a job to find your files until this is sorted.
     Check with: hermes config get terminal.cwd"
            return $false
        }
    }
}

# =============================================================================
# THE LEASH, TRANSLATED RATHER THAN RENAMED
#
# The Windows twin of kb_hermes_approvals in lib.sh, and the long note above that
# function carries the measurements. The short version:
#
# The Claude file this replaces grants a blanket allow plus a long deny list, because
# Claude Code has no floor of its own. Hermes has one, so a one-for-one copy would be
# a rename. Measured on stock Hermes 0.21.0 with `hermes approvals test`, which returns
# a verdict without executing anything: every command the kit itself runs is ALREADY
# allowed with nothing configured, so no allowlist is written here at all. What Hermes
# does not refuse on its own is a short list, and that is what goes in.
#
# The pattern shape matters more than the list. An approvals.deny entry is a glob over
# the WHOLE normalised command: "iptables" denies nothing, not even `iptables -F`, and
# even "iptables *" plus "sudo iptables *" is walked around by `/sbin/iptables -F`.
# Every phrase in the shipped list is wrapped in wildcards for that reason, and chosen
# to be one no ordinary hub command contains.
#
# WHY A WINDOWS PC GETS THE UNIX RULES. Because this is where the reader drives their
# server from. Hermes Desktop holds a connection list, and the whole point of Chapter 27
# is that the machine in front of you reaches the machine that never sleeps. A Hermes on
# this PC with an SSH connection open can run `systemctl stop ssh` on the reader's own
# server as easily as it can run `dir`, and would lock them out of it.
#
# WHAT IS STILL OWED, and it is not pretended otherwise: a Windows-native dangerous
# command set has NOT been measured. format, diskpart, bcdedit, vssadmin delete shadows,
# wevtutil cl and netsh advfirewall reset are the obvious candidates, and not one of
# them has been through `approvals test` on a stock Windows Hermes. Guessing a list
# would be exactly the thing this file spends its comments arguing against.
# =============================================================================

function Get-KitHermesDenyRules {
    <#  The shipped list. Kept as data so the self-check reads the same thing the
        writer wrote, rather than a second copy that drifts. #>
    @(
        '*shred *', '*userdel root*', '*usermod -L root*', '*passwd root*',
        '*iptables -F*', '*iptables -X*', '*ip6tables -F*', '*ip6tables -X*',
        '*ufw --force reset*',
        '*systemctl stop ssh*', '*systemctl disable ssh*',
        '*systemctl stop sshd*', '*systemctl disable sshd*', '*systemctl mask *',
        '*chmod 000 /etc*', '*chmod 777 /etc*',
        '*history -c*', '*rm -rf /var/log*'
    )
}

function Set-KitHermesApprovals {
    <#  Add the kit's deny rules to approvals.deny, keeping anything already there.
        `hermes config set` REPLACES a list, so this is read, merge, write.

        It never writes approvals.mode. The shipped default is 'smart', and an
        installer that turns the leash off to make its own life easier has sold the
        reader something the book spends a chapter arguing against. #>

    if (-not (Test-KitHermesHere)) {
        Write-KbOk "safety: Hermes is not on this PC yet, so there are no rules to give it. Run this again once it is."
        return $true
    }
    $bin = Get-KitHermesBin

    # Read through Get-KitHermesList, which UNQUOTES. Every rule below starts with `*`, so
    # Hermes hands them all back YAML-quoted, and a naive read adds all eighteen again on
    # every run. See ConvertFrom-KbYamlScalar.
    $cur = @(Get-KitHermesList -Key 'approvals.deny')

    $add = @(Get-KitHermesDenyRules | Where-Object { $cur -notcontains $_ })
    if ($add.Count -eq 0) {
        Write-KbOk "safety: the rules that keep an assistant from locking you out are already in place"
    } else {
        $json = '[' + (((@($cur) + $add) | ForEach-Object { ConvertTo-KbJsonString $_ }) -join ',') + ']'
        # Through Invoke-KitHermesConfigSet, never &: PowerShell 5.1 eats the JSON's
        # quotes on the way to a native argv, and Hermes then stores a string it
        # ignores - a leash that reads perfectly and stops nothing.
        if (-not (Invoke-KitHermesConfigSet -Key 'approvals.deny' -Value $json)) {
            Write-KbWarn "safety: could not add the deny rules. Your assistant can still be talked into
     switching off SSH on the server you reach from this PC. Run this by hand:
     hermes config set approvals.deny '$json'"
            return $false
        }
        # READ IT BACK. Hermes 0.20.0 stores a JSON list as one plain string, its
        # readers ignore a string, and the string echoes back through config get, so
        # before Get-KitHermesList learnt to filter, every run nested the list one
        # level deeper. A leash that cannot be read back as entries is a leash that
        # is NOT on, and the reader hears that instead of a success line.
        if (-not (@(Get-KitHermesList -Key 'approvals.deny') -contains '*ufw --force reset*')) {
            Write-KbWarn "safety: this Hermes stored the rules as text it does not enforce. The leash
     is NOT on. Update Hermes, run this again, and it will check again."
            return $false
        }
        Write-KbOk "safety: added $($add.Count) rule(s) Hermes does not refuse on its own, and kept the ones you had"
    }

    return (Test-KitHermesApprovals)
}

function Test-KitHermesApprovals {
    <#  Prove the rules bite, and prove they did not break ordinary work. `approvals
        test` never executes the command and never persists anything, and its exit
        codes are 0 allow, 2 ask, 3 deny, so this is deterministic with no model in it.

        Both directions, because either alone is a half-truth: a list that denied
        everything would sail through a deny-only check and make the hub unusable. #>
    if (-not (Test-KitHermesHere)) { return $true }
    $bin = Get-KitHermesBin
    $bad = $false

    & $bin approvals test -- git status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-KbWarn "safety: the rules went too far. Hermes would now stop to ask before ``git status``,
     which the hub uses constantly. Check: hermes config get approvals.deny"
        $bad = $true
    }
    & $bin approvals test -- ufw --force reset 2>&1 | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 3) {
        Write-KbWarn "safety: the rules are not biting. Hermes still answered $rc for a command that
     resets a firewall, where 3 means refused. Do not treat this setup as fenced."
        $bad = $true
    }
    if ($bad) { return $false }
    Write-KbOk "safety: checked both ways, the dangerous command is refused and ordinary work is not"
    return $true
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

# One real room, junctions to it, and it counts what it wired. Replaces three lines
# that pointed .agents\skills at .claude\skills whenever .claude\skills existed, which
# on a hub built by the book meant pointing every non-Claude assistant at the empty
# folder the top-up had just made.
Connect-KitSkills -Hub $Hub | Out-Null

# Where Hermes works. terminal.cwd, never `workspace`, and proved by a file read
# rather than by reading the setting back. See the long note above the function: four
# of the six known ways to do this are silent no-ops and the kit shipped one.
Set-KitHermesHub -Hub $Hub | Out-Null

# The leash. A translation of the Claude permissions file, not a rename: Hermes
# already allows every command the kit runs, so this writes no allowlist at all and
# only closes the gaps its own floor leaves open. Measured, both ways.
Set-KitHermesApprovals | Out-Null

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

# EXPLICIT, and it has to be. This script ends with wiring that calls Hermes, and
# `hermes approvals test` answers 3 when the leash is working, so without this line a
# completely successful join exits 3: PowerShell hands back whatever the last native
# command left in $LASTEXITCODE.
exit 0
