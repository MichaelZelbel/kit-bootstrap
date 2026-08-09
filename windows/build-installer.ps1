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
param([switch]$SkipCompilerInstall)

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
