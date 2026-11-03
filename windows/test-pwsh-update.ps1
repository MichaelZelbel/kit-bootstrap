# =============================================================================
# kit-bootstrap / windows / test-pwsh-update.ps1
#
# The update, started from PowerShell 7 (ticket kb, 2.0.0-beta.17).
#
# On 3 November 2026 the public updater stopped before it replaced the app: its Windows PowerShell
# 5.1 said it could not find Get-FileHash. A 5.1 that PowerShell 7 starts the way a program starts
# a program (Start-Process, Process.Start, the setup's own Exec) inherits PowerShell 7's PSModulePath,
# which lists PowerShell 7's module folders first, so 5.1 loads PowerShell 7's
# Microsoft.PowerShell.Utility and the command is missing. (`& powershell.exe` typed in PowerShell 7
# is repaired by PowerShell 7 itself, so a person typing it never saw this.)
#
# This test is run BY PowerShell 7 (pwsh), never with the module path reset, and starts the real
# update-godspeed.ps1 in a 5.1 that inherits it:
#   - the failure is reproduced first, with a script that has no guard (if it does not reproduce on
#     a machine, that is said and the rest still runs);
#   - every script that runs under 5.1 carries the same guard;
#   - the update replaces the app (a stub setup stands for GodspeedSetup.exe) and checks its
#     checksum, and a download that does not match the release's checksum is still not run.
# Everything is written under TEMP.
#
#   pwsh -NoProfile -File windows/test-pwsh-update.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core') { Write-Host 'FAIL  this test must be started from PowerShell 7 (pwsh)'; exit 1 }
$script:fail = 0
function Want($what, [scriptblock]$test) {
    $ok = $false; try { $ok = [bool](& $test) } catch { Write-Host "   $_" }
    if ($ok) { Write-Host "ok    $what" } else { Write-Host "FAIL  $what"; $script:fail++ }
}
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$here = $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('godspeed-pwsh-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root | Out-Null

# A program starting a program: nothing PowerShell 7 does for a typed command.
function Start-Windows51([string[]]$Arguments, [hashtable]$Environment = @{}) {
    $psi = New-Object Diagnostics.ProcessStartInfo $ps51
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($k in $Environment.Keys) { $psi.EnvironmentVariables[$k] = [string]$Environment[$k] }
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(300000)) { $p.Kill(); return [pscustomobject]@{ Code = 999; Text = 'timed out' } }
    [pscustomobject]@{ Code = $p.ExitCode; Text = ($out.Result + "`n" + $err.Result) }
}

try {
    Want 'this run is PowerShell 7 and its module path lists the PowerShell 7 folders' {
        $env:PSModulePath -match '(?i)[\\/]PowerShell[\\/](7[^\\/;]*|Modules)([\\/;]|$)'
    }

    # 1. The failure, reproduced with a script that has no guard.
    $probe = Join-Path $root 'probe.txt'; Set-Content -LiteralPath $probe -Value 'x'
    $bare = Join-Path $root 'bare.ps1'
    Set-Content -LiteralPath $bare -Value '(Get-FileHash -LiteralPath $args[0] -Algorithm SHA256).Hash'
    $r = Start-Windows51 @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bare, $probe)
    if ($r.Text -match 'Get-FileHash.*not recognized') { Write-Host 'ok    reproduced: a 5.1 started from PowerShell 7 cannot find Get-FileHash without the guard' }
    else { Write-Host 'note  the failure does not reproduce on this machine (PowerShell 7 here leaves 5.1 its own modules); the checks below still run' }

    # 2. Every script that runs under 5.1 carries the guard, the same text in each.
    $update = Get-Content -LiteralPath (Join-Path $here 'update-godspeed.ps1') -Raw
    $guard = ($update -split "\r?\n" | Where-Object { $_.StartsWith('if($PSVersionTable.PSEdition -eq ''Desktop''') } | Select-Object -First 1)
    Want 'update-godspeed.ps1 has the guard' { [bool]$guard }
    $entry = 'build-godspeed-setup.ps1', 'build-installer.ps1', 'computer-helper.ps1', 'detect-godspeed.ps1', 'ensure-hermes.ps1', 'move-to-new-folders.ps1',
        'open-hermes.ps1', 'open-notebook.ps1', 'setup-godspeed.ps1', 'setup-notebook.ps1', 'start-notebook.ps1', 'stop-notebook.ps1',
        'uninstall-godspeed.ps1', 'update-godspeed.ps1', 'vendor\hermes-install.ps1', '..\join.ps1'
    foreach ($f in $entry) {
        Want "$f has the guard" { (Get-Content -LiteralPath (Join-Path $here $f) -Raw).Contains($guard) }
    }
    # Any other script of windows\ that asks for Get-FileHash must be one of them or be dot-sourced.
    Want 'no script that uses Get-FileHash is left without the guard' {
        $left = Get-ChildItem -LiteralPath $here -Filter *.ps1 | Where-Object { $_.Name -notlike 'test-*' } |
            Where-Object { $c = Get-Content -LiteralPath $_.FullName -Raw; $c.Contains('Get-FileHash') -and -not $c.Contains($guard) }
        if ($left) { Write-Host "   without the guard: $($left.Name -join ', ')" }
        -not $left
    }

    # 3. The guard itself: repairs the path from PowerShell 7, leaves a clean path alone.
    $g = Join-Path $root 'guarded.ps1'
    Set-Content -LiteralPath $g -Value ($guard + "`r`n" + '$env:PSModulePath; (Get-FileHash -LiteralPath $args[0] -Algorithm SHA256).Hash')
    $want = (Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash
    $r = Start-Windows51 @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $g, $probe)
    Want 'a guarded script hashes a file in a 5.1 that inherits PowerShell 7''s module path' { $r.Code -eq 0 -and $r.Text.Contains($want) }
    $clean = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
    Want 'the guard sets the path to the user''s Windows PowerShell modules and the machine''s own path' {
        $r.Text.Contains((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules') + ';' + $clean)
    }
    $r = Start-Windows51 @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $g, $probe) @{ PSModulePath = $clean }
    Want 'with the machine''s own path, the guard changes nothing' { $r.Code -eq 0 -and $r.Text.Contains($clean) -and $r.Text.Contains($want) }

    # 4. The update itself, from PowerShell 7, with a stub for GodspeedSetup.exe.
    $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $stubSource = Join-Path $root 'stub.cs'
    Set-Content -LiteralPath $stubSource -Value @'
using System; using System.IO;
class Stub { static int Main() {
  string s = Environment.GetEnvironmentVariable("STUB_STATE");
  File.WriteAllText(Path.Combine(s, "installation.json"), "{\"kitCommit\":\"" + Environment.GetEnvironmentVariable("STUB_COMMIT") + "\"}");
  File.WriteAllText(Path.Combine(s, "stub-ran.txt"), "yes");
  return 0; } }
'@
    $stubExe = Join-Path $root 'GodspeedSetup.exe'
    & $csc /nologo /out:$stubExe $stubSource | Out-Null
    Want 'the stand-in setup is built' { Test-Path -LiteralPath $stubExe }

    $new = 'b' * 40
    function New-Release([string]$Name, [bool]$GoodSums) {
        $dir = Join-Path $root $Name; New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item -LiteralPath $stubExe -Destination (Join-Path $dir 'GodspeedSetup.exe')
        (@{ channel = 'full-alpha'; version = '2.0.0-test'; kitCommit = $new; kitCommittedAt = '2026-11-04T10:00:00+01:00' } | ConvertTo-Json) |
            Set-Content -LiteralPath (Join-Path $dir 'windows-manifest.json')
        $lines = foreach ($n in 'GodspeedSetup.exe', 'windows-manifest.json') {
            $h = (Get-FileHash -LiteralPath (Join-Path $dir $n) -Algorithm SHA256).Hash.ToLowerInvariant()
            if (-not $GoodSums) { $h = ('0' * 64) }
            "$h  $n"
        }
        Set-Content -LiteralPath (Join-Path $dir 'SHA256SUMS') -Value $lines -Encoding ascii
        $dir
    }
    function New-State([string]$Name) {
        $dir = Join-Path $root $Name; New-Item -ItemType Directory -Force -Path $dir | Out-Null
        (@{ channel = 'full-alpha'; kitCommit = ('a' * 40); kitCommittedAt = '2026-10-18T10:00:00+02:00' } | ConvertTo-Json) |
            Set-Content -LiteralPath (Join-Path $dir 'installation.json') -Encoding UTF8
        $dir
    }
    function Invoke-Update([string]$Release, [string]$State) {
        Start-Windows51 @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'update-godspeed.ps1'), '-ReleaseBase', $Release, '-State', $State, '-NoPause') @{ STUB_STATE = $State; STUB_COMMIT = $new }
    }

    $state = New-State 'state-good'
    $r = Invoke-Update (New-Release 'release-good' $true) $state
    Want 'the update started from PowerShell 7 finishes: the setup ran and the PC has the new version' {
        $r.Code -eq 0 -and (Test-Path (Join-Path $state 'stub-ran.txt')) -and $r.Text.Contains('is up to date') -and
            ((Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw | ConvertFrom-Json).kitCommit -eq $new)
    }
    Want 'the update never says Get-FileHash is missing' { $r.Text -notmatch 'Get-FileHash' }

    $state = New-State 'state-bad'
    $r = Invoke-Update (New-Release 'release-bad' $false) $state
    Want 'a download that does not match the release''s checksums is still not run' {
        $r.Code -eq 1 -and $r.Text.Contains('does not match the release''s checksum') -and -not (Test-Path (Join-Path $state 'stub-ran.txt'))
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { Write-Host "$script:fail check(s) FAILED"; exit 1 }
Write-Host 'all checks passed'
