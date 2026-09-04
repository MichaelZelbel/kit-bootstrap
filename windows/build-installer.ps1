# =============================================================================
# kit-bootstrap / windows / build-installer.ps1
#
# Turns hub-setup.iss into dist\HubSetup.exe, fetching the compiler first if this
# PC has not got one. Run it from anywhere:
#
#   powershell -ExecutionPolicy Bypass -File build-installer.ps1
#
# The compiler is Inno Setup, which is free and is what most small Windows
# installers are built with.
# =============================================================================
param(
    [switch]$SkipCompilerInstall,
    # Build anyway with a pin that is not a tag at this commit. For trying something
    # locally. Never for anything a reader will download: the whole point of the pin is
    # that the .exe and the code it fetches are the same code.
    [switch]$AllowUnpinnedBuild
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Find-Iscc {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )) { if (Test-Path $p) { return $p } }
    return $null
}

$iscc = Find-Iscc
if (-not $iscc -and -not $SkipCompilerInstall) {
    Write-Host "Inno Setup is not on this PC. Installing it..." -ForegroundColor Cyan
    winget install --id JRSoftware.InnoSetup --exact --silent `
        --accept-source-agreements --accept-package-agreements
    $iscc = Find-Iscc
}
if (-not $iscc) {
    throw "No Inno Setup compiler. Install it with: winget install --id JRSoftware.InnoSetup"
}
Write-Host "compiler: $iscc"

# join.ps1 is the shared install code and this installer carries a copy of it for
# machines with no internet. Refusing to build without it is better than shipping
# an installer whose offline path silently does nothing.
if (-not (Test-Path (Join-Path $PSScriptRoot '..\join.ps1'))) {
    throw "..\join.ps1 is missing. Run this from inside a kit-bootstrap checkout."
}

# -----------------------------------------------------------------------------
# THE PIN HAS TO NAME THIS COMMIT, or the .exe lies about what it will fetch.
#
# hub-setup.iss carries #define KbPin, and the wizard passes it to setup-hub.ps1 as
# -KbBranch, so a reader gets exactly that tag's code. A pin left at the previous release
# would hand readers older code than the installer they downloaded, and nothing on screen
# would say so: it is the same silent drift install-hub.sh was written to avoid, and it is
# why that file's comment insists on an immutable tag.
#
# So it is checked here rather than trusted: the tag must exist, and it must name the very
# commit being built. Found the first time this ran: AppVersion still said 2.2.0 while
# 2.3.0 was already published.
# -----------------------------------------------------------------------------
# git, with no power to abort this script. The same trap Invoke-KitGit exists for in
# join.ps1: this file sets $ErrorActionPreference = 'Stop', and PowerShell 7.3+ turns any
# native stderr line into a terminating error, so `git rev-parse` on a tag that does not
# exist yet killed the build instead of reporting the missing pin. A local copy rather than
# a shared one, because this script deliberately loads nothing.
function git0 {
    param([Parameter(Mandatory, ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & git @GitArgs 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } }
    finally { $ErrorActionPreference = $eap }
}

$iss  = Get-Content 'hub-setup.iss' -Raw
$pin  = if ($iss -match '#define\s+KbPin\s+"([^"]+)"')      { $Matches[1] } else { $null }
$ver  = if ($iss -match '#define\s+AppVersion\s+"([^"]+)"') { $Matches[1] } else { $null }
if (-not $pin) { throw "hub-setup.iss has no #define KbPin, so this .exe would fetch the moving branch. Add one." }

$head     = @(git0 rev-parse HEAD)[0]
$pinnedAt = @(git0 rev-parse "$pin^{commit}")[0]
if ($LASTEXITCODE -ne 0) { $pinnedAt = $null }
if (-not $pinnedAt) {
    $msg = "the pin in hub-setup.iss is $pin, and no such tag exists here. Tag this commit first:  git tag -a $pin -m '...' ; git push origin $pin"
    if ($AllowUnpinnedBuild) { Write-Warning $msg } else { throw $msg }
} elseif ($pinnedAt -ne $head) {
    $msg = "the pin in hub-setup.iss is $pin, which names commit $($pinnedAt.Substring(0,7)), but you are building $($head.Substring(0,7)). A reader would download this installer and then fetch different code. Move the tag, or bump KbPin."
    if ($AllowUnpinnedBuild) { Write-Warning $msg } else { throw $msg }
} else {
    Write-Host "pin:      $pin (this commit)" -ForegroundColor Green
}
$dirty = @(git0 status --porcelain)
if ($dirty -and -not $AllowUnpinnedBuild) {
    throw "this checkout has uncommitted changes, so the .exe would carry code that is in no tag. Commit them, or pass -AllowUnpinnedBuild for a local try."
}
Write-Host "version:  $ver"

New-Item -ItemType Directory -Force 'dist' | Out-Null
& $iscc /Qp 'hub-setup.iss'
if ($LASTEXITCODE -ne 0) { throw "The compiler failed with exit code $LASTEXITCODE." }

$exe = Join-Path $PSScriptRoot 'dist\HubSetup.exe'
if (-not (Test-Path $exe)) { throw "The compiler reported success but produced no dist\HubSetup.exe." }

$size = [math]::Round((Get-Item $exe).Length / 1MB, 2)
$sha  = (Get-FileHash $exe -Algorithm SHA256).Hash

Write-Host ""
Write-Host "built: $exe" -ForegroundColor Green
Write-Host "size:  $size MB"
Write-Host "sha256:$sha"
Write-Host ""
Write-Host "Publish it with:"
Write-Host "  gh release create v<version> `"$exe`" --repo MichaelZelbel/teach-it-once-kit --title `"Windows installer v<version>`" --notes `"...`""
