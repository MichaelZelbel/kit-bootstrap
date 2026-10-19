$ErrorActionPreference = 'Stop'
if ($env:CI -ne 'true' -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Use only on a fresh GitHub-hosted Windows runner.'
}
foreach ($name in @('RELEASE_COMMIT','PRODUCT_COMMIT','BOOTSTRAP_COMMIT')) {
    if ([Environment]::GetEnvironmentVariable($name) -cnotmatch '^[0-9a-f]{40}$') { throw "$name must name a full commit." }
}
foreach ($name in @('SETUP_SHA256','MANIFEST_SHA256')) {
    if ([Environment]::GetEnvironmentVariable($name) -cnotmatch '^[0-9a-f]{64}$') { throw "$name must be a SHA256." }
}
# These tests install into the real user's paths. Refuse any pre-existing Godspeed on this runner.
foreach ($path in @((Join-Path $HOME 'godspeed'),(Join-Path $HOME 'godspeed-v2'),(Join-Path $HOME '.godspeed'),
    (Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha'),
    (Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'))) {
    if (Test-Path -LiteralPath $path) { throw "The runner is not fresh: $path exists." }
}
$registered = @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Like 'Godspeed*')
if ($registered.Count) { throw 'The runner already has a registered Godspeed installation.' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bootstrap = Join-Path $root 'bootstrap'
$actualBootstrap = (& git -C $bootstrap rev-parse HEAD).Trim()
if ($LASTEXITCODE -or $actualBootstrap -cne $env:BOOTSTRAP_COMMIT) { throw 'The original test checkout is not the requested bootstrap commit.' }
$test = Join-Path $bootstrap 'windows/test-finish-page.ps1'
$testHash = (Get-FileHash -LiteralPath $test -Algorithm SHA256).Hash.ToLowerInvariant()
$candidate = Join-Path $root 'candidate'
$evidence = Join-Path $root 'evidence'
if (Test-Path -LiteralPath $candidate) { throw 'Candidate output already exists.' }
New-Item -ItemType Directory -Path $candidate,$evidence -Force | Out-Null
# Both URLs are unauthenticated, immutable public source URLs. No old fixture is requested.
$base = "https://raw.githubusercontent.com/MichaelZelbel/godspeed-mission-control/$env:RELEASE_COMMIT/installers"
foreach ($item in @(@{Name='GodspeedSetup.exe';Hash=$env:SETUP_SHA256},@{Name='windows-manifest.json';Hash=$env:MANIFEST_SHA256})) {
    $file = Join-Path $candidate $item.Name
    Invoke-WebRequest -Uri "$base/$($item.Name)" -OutFile $file -MaximumRedirection 0
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.Hash) { throw "Wrong public $($item.Name) bytes." }
}
& node (Join-Path $PSScriptRoot 'verify-candidate.mjs') (Join-Path $candidate 'windows-manifest.json') $env:PRODUCT_COMMIT $env:BOOTSTRAP_COMMIT
if ($LASTEXITCODE) { throw 'Candidate manifest verification failed.' }
@(
    'Coverage: fresh wizard only; Next on every page and the original final-page assertions.',
    'No silent install, legacy update, downgrade-refusal, updater or uninstall coverage is claimed.',
    'Only the new public committed installer and manifest were downloaded; no private fixtures or fixture credentials were used.',
    "Release commit: $env:RELEASE_COMMIT",
    "Runtime commit: $env:PRODUCT_COMMIT",
    "Bootstrap commit: $env:BOOTSTRAP_COMMIT",
    "Setup SHA256: $env:SETUP_SHA256",
    "Manifest SHA256: $env:MANIFEST_SHA256",
    "Unchanged bootstrap test SHA256: $testHash"
) | Set-Content -LiteralPath (Join-Path $evidence 'provenance.txt') -Encoding utf8
