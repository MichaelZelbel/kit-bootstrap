# Run the actual downloaded executable on a disposable hosted Windows runner.
param([Parameter(Mandatory)][string]$ArtifactDir, [ValidateSet('fresh','upgrade')][string]$Route = 'fresh')
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'This test requires a disposable GitHub-hosted Windows runner.' }
$candidate = Join-Path $ArtifactDir 'HubSetup.exe'
$manifest = Get-Content (Join-Path $ArtifactDir 'candidate.json') -Raw | ConvertFrom-Json
if ((Get-FileHash $candidate -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Candidate checksum mismatch.' }
$readerHub = Join-Path $env:USERPROFILE 'hub'
if (Test-Path $readerHub) { throw 'This journey requires a clean reader account.' }
$clientDir = Join-Path $env:APPDATA 'Hermes'
New-Item -ItemType Directory -Force $clientDir | Out-Null
$connectionFile = Join-Path $clientDir 'connections.json'
$client = '{"version":2,"connections":[{"id":"example","kind":"ssh","label":"Example server","host":"example.org","token":"fictional-reader-token"}]}'
[IO.File]::WriteAllText($connectionFile, $client)
git config --global user.name 'Example Reader'
git config --global user.email 'reader@example.org'
function Install-Artifact([string]$Exe, [string]$Name, [int]$ExpectedCode = 0) {
    $log = Join-Path $ArtifactDir ($Name + '.log')
    $process = Start-Process -FilePath $Exe -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + $log + '"')) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(900000)) { $process.Kill(); throw "$Name did not finish in 15 minutes." }
    $engineLog = Join-Path $env:LOCALAPPDATA 'Hub/setup-log.txt'
    if (Test-Path $engineLog) { Copy-Item -LiteralPath $engineLog -Destination (Join-Path $ArtifactDir ($Name + '-engine.log')) }
    if ($process.ExitCode -ne $ExpectedCode) { throw "$Name returned $($process.ExitCode); expected $ExpectedCode. Read $log." }
    return $log
}
if ($Route -eq 'upgrade') {
    # Previous installer needs at least one detected tool: its empty selection was
    # passed as a bare dash, which PowerShell 5.1 rejects. Fresh tests cover the fix.
    New-Item -ItemType Directory -Force (Join-Path $env:USERPROFILE '.claude/projects') | Out-Null
    $baseline = Join-Path $ArtifactDir 'HubSetup-v2.3.1.exe'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/MichaelZelbel/teach-it-once-kit/releases/download/v2.3.1/HubSetup.exe' -OutFile $baseline
    if ((Get-FileHash $baseline -Algorithm SHA256).Hash -ne 'dc5a80a97671f2f37d5db748575e910639955681994d2ac3dc72a465b3da0aa7') {
        throw 'The previous public installer differs from the inspected baseline.'
    }
    Install-Artifact $baseline 'baseline' | Out-Null
    if (-not (Test-Path (Join-Path $readerHub 'AGENTS.md'))) { throw 'The baseline did not create a reader hub.' }
    [IO.File]::WriteAllText((Join-Path $readerHub 'reader-note.txt'),'Keep this personal note exactly.')
}
$log = Install-Artifact $candidate 'candidate'
if (-not (Test-Path (Join-Path $readerHub 'AGENTS.md'))) { throw 'The candidate did not create a reader hub.' }
if ((Get-Content $connectionFile -Raw) -ne $client) { throw 'The saved remote connection or credential changed.' }
if ($Route -eq 'upgrade' -and (Get-Content (Join-Path $readerHub 'reader-note.txt') -Raw) -ne 'Keep this personal note exactly.') {
    throw 'The update changed a personal file.'
}
$status = Get-Content (Join-Path $env:USERPROFILE '.hub\chat\setup-status.json') -Raw | ConvertFrom-Json
Copy-Item -LiteralPath (Join-Path $env:USERPROFILE '.hub\chat\setup-status.json') -Destination (Join-Path $ArtifactDir 'setup-status.json')
if ($status.state -ne 'remote_update_pending' -or $status.notice -notmatch 'not checked') { throw 'Desktop setup did not explain the separate server check.' }
if ((Get-Content $log -Raw) -notmatch 'Hub setup engine exit code: 0') { throw 'The wizard did not record the engine outcome.' }
if ((Get-Content $log -Raw) -notmatch 'not checked') { throw 'The server notice did not reach the wizard result.' }
if (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'hermes.*gateway\s+run' }) {
    throw 'Desktop setup started an unexpected gateway.'
}
# A real engine failure must reach the executable's caller and its final page.
$env:KB_TOOLS_REF = 'invalid-fixture-ref'
try {
    $failedLog = Install-Artifact $candidate 'failed-update' 1
    if ((Get-Content $failedLog -Raw) -notmatch 'The hub setup did not finish') { throw 'The wizard hid the failed setup.' }
} finally { Remove-Item Env:KB_TOOLS_REF }
Write-Host "PASS: actual $Route executable journey; remote check remains explicit; personal data preserved; engine failure surfaced."
