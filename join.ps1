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
    @(
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
    ) | Set-Content -Path $idx -Encoding utf8NoBOM
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

if ($AsLibrary) { return }

# ---------------------------------------------------------------- run standalone
if (-not $Hub) { $Hub = if ($env:HUB) { $env:HUB } else { Join-Path $HOME 'hub' } }
if (-not (Test-Path $Hub)) {
    Write-Error "There is no folder at $Hub. Clone your hub there first, then run this again. If your hub is somewhere else, pass the path: join.ps1 C:\path\to\your\hub"
    exit 1
}
$Hub = (Resolve-Path $Hub).Path

Write-KbSay "Joining this machine to the hub at $Hub"

if (Test-Path (Join-Path $Hub '.git')) {
    $branch = (git -C $Hub rev-parse --abbrev-ref HEAD 2>$null)
    git -C $Hub pull --rebase --autostash -q origin $branch 2>$null
    if ($LASTEXITCODE -eq 0) { Write-KbOk "pulled the latest version of your hub" }
    else { Write-KbWarn "could not pull (no network, or a conflict to sort out by hand). Continuing with the copy already on this machine, which may be out of date." }
} else {
    Write-KbWarn "$Hub is not a git folder, so there is nothing to pull. Continuing."
}

Join-KitMemory -Hub $Hub

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
