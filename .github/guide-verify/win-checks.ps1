<#
  What a reader has after GodspeedSetup.exe on Windows, checked against the public guide
  (install-windows, check-it-works, folders-and-settings, terminal-commands, notebook-command,
  troubleshooting; release godspeed-v2-integrated-2026-10-16-2). Evidence only: every command and
  its whole answer are printed; it never fails the job by itself.

    ./.github/guide-verify/win-checks.ps1 -Part places|startup|commands|notebook
#>
param([ValidateSet('places','startup','commands','notebook')][string]$Part, [string]$Evidence = 'evidence')
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
$state = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$app = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha'
$mc = Join-Path $env:USERPROFILE 'godspeed-v2'
function Section($t) { "`n`n########## $t" }
function Have($p) { if (Test-Path -LiteralPath $p) { "present  $p" } else { "ABSENT   $p" } }
# T "<command>" runs it in a NEW Windows PowerShell 5.1 (the PowerShell a reader opens), with the
# PATH a new window gets from the registry, and prints its whole answer and exit code.
function T([string]$cmd, [string]$Shell = 'powershell', [int]$Seconds = 180) {
  "`n> $cmd   [$Shell]"
  $file = Join-Path $env:RUNNER_TEMP ('t-' + [guid]::NewGuid().ToString('N'))
  if ($Shell -eq 'bash') {
    Set-Content -LiteralPath "$file.sh" -Value ("export PATH=""`$HOME/.local/bin:`$PATH""`n" + $cmd) -Encoding ascii
    $exe = 'C:\Program Files\Git\bin\bash.exe'; $argv = @('-l', "$file.sh")
  } else {
    $pre = '$env:Path = [Environment]::GetEnvironmentVariable(''Path'',''Machine'') + '';'' + [Environment]::GetEnvironmentVariable(''Path'',''User'');'
    Set-Content -LiteralPath "$file.ps1" -Value ($pre + "`n" + $cmd + "`nexit `$LASTEXITCODE") -Encoding utf8
    $exe = $(if ($Shell -eq 'pwsh') { 'pwsh.exe' } else { 'powershell.exe' }); $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$file.ps1")
  }
  $p = Start-Process -FilePath $exe -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput "$file.out" -RedirectStandardError "$file.err" -WorkingDirectory $(if ($script:Here) { $script:Here } else { $PWD.Path })
  if (-not $p.WaitForExit($Seconds * 1000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "[still running after $Seconds s, stopped]" }
  Get-Content "$file.out" -ErrorAction SilentlyContinue; Get-Content "$file.err" -ErrorAction SilentlyContinue
  "[exit $($p.ExitCode)]"
}
function Shortcut($path) {
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
  "  target: $($s.TargetPath)`n  arguments: $($s.Arguments)`n  window style: $($s.WindowStyle)"
}

if ($Part -eq 'places') {
  Section 'the installer record and the release (updates-and-versions: Your release on Windows)'
  Get-Content (Join-Path $state 'installation.json') -Raw
  $i = Get-Content (Join-Path $state 'installation.json') -Raw | ConvertFrom-Json
  "kitCommit: $($i.kitCommit)"
  $m = Invoke-RestMethod 'https://github.com/MichaelZelbel/godspeed-mission-control/releases/download/godspeed-v2-integrated-2026-10-16-2/windows-manifest.json'
  "kitCommit in the release's windows-manifest.json: $($m.kitCommit)"
  Get-Content (Join-Path $state 'assistant.json') -Raw -ErrorAction SilentlyContinue

  Section 'health and pages (check-it-works)'
  try { (Invoke-WebRequest http://127.0.0.1:47831/health -UseBasicParsing -TimeoutSec 15).Content } catch { "health: $_" }
  try { $r = Invoke-WebRequest http://127.0.0.1:47831/ -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction SilentlyContinue; "/: $($r.StatusCode) $($r.Headers.Location)" } catch { "/: $_" }
  try { $r = Invoke-WebRequest http://127.0.0.1:47831/dashboard -UseBasicParsing -TimeoutSec 15; "/dashboard: $($r.StatusCode) root element: $($r.Content -match 'id=""root""')" } catch { "/dashboard: $_" }

  Section 'Start menu group (install-windows: What you have now)'
  $group = Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'
  Get-ChildItem $group -Force -ErrorAction SilentlyContinue | ForEach-Object {
    "entry: $($_.Name)"
    if ($_.Extension -eq '.lnk') { Shortcut $_.FullName }
    if ($_.Extension -eq '.url') { '  ' + ((Get-Content $_.FullName) -match '^URL=') }
  }
  Get-ChildItem ([Environment]::GetFolderPath('CommonPrograms')) -Filter '*Godspeed*' -ErrorAction SilentlyContinue | ForEach-Object { "all-users Start menu: $($_.FullName)" }

  Section 'Startup folder'
  $startup = [Environment]::GetFolderPath('Startup')
  Get-ChildItem $startup -Force | ForEach-Object { "startup entry: $($_.Name)"; if ($_.Extension -eq '.lnk') { Shortcut $_.FullName } }

  Section 'scheduled tasks'
  Get-ScheduledTask | Where-Object { $_.TaskName -like '*Godspeed*' -or $_.TaskName -like '*godspeed*' } | ForEach-Object {
    "task: $($_.TaskName)  state: $($_.State)"; $_.Actions | ForEach-Object { "  action: $($_.Execute) $($_.Arguments)" }; $_.Triggers | ForEach-Object { "  trigger: $($_.CimClass.CimClassName) $($_.StartBoundary) every $($_.Repetition.Interval)" }
  }

  Section 'Apps list entry'
  Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { $p = Get-ItemProperty $_.PSPath; if ($p.DisplayName -like '*Godspeed*') { "$($_.PSChildName): $($p.DisplayName) $($p.DisplayVersion) uninstall=$($p.UninstallString)" } }

  Section 'the installer file properties'
  Get-ChildItem $env:USERPROFILE\Downloads\GodspeedSetup.exe -ErrorAction SilentlyContinue | ForEach-Object { "size: $($_.Length) bytes = $([math]::Round($_.Length/1MB,1)) MB; file version: $($_.VersionInfo.FileVersion); product version: $($_.VersionInfo.ProductVersion)" }

  Section 'folders (install-windows: These are the places it uses; folders-and-settings)'
  foreach ($p in @($mc, $app, $state, (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt'), (Join-Path $state 'installation.json'), (Join-Path $state 'media'),
                   (Join-Path $state 'backups'), (Join-Path $state 'hermes-profile'), (Join-Path $state 'hermes-profile\bin'), (Join-Path $state 'service-error.log'), (Join-Path $state 'service.log'),
                   (Join-Path $state 'hermes-install.log'), (Join-Path $state 'hermes-install-error.log'),
                   (Join-Path $env:USERPROFILE '.local\bin'), (Join-Path $env:USERPROFILE '.godspeed\device.env'), (Join-Path $app 'payload\runtime\node.exe'),
                   (Join-Path $app 'payload\kit\notebook\bin\godspeed.mjs'), (Join-Path $app 'start-full-alpha.ps1'), (Join-Path $app 'unins000.exe'))) { Have $p }
  foreach ($f in 'AGENTS.md','CLAUDE.md','README.md','FULL-ALPHA.md','procedures.md','decisions.md','.mcp.json','.gitignore','.gitattributes','profile\about-me.md','profile\people.md','profile\projects.md','profile\voice.md','rules','skills','assistant\extra-instructions.md','inbox','dev','secrets\expires.txt','notebook','notebook\_system','observations\MEMORY.md','goals','work','forecasts','ideas','due','world','prompts\archive','prompts\library','.godspeed','.claude','.godspeed\food\bls-4.0\NOTICE.md') { Have (Join-Path $mc $f) }
  "rules: " + @(Get-ChildItem (Join-Path $mc 'rules') -File).Count + " files"; Get-ChildItem (Join-Path $mc 'rules') -Name
  "skills: " + @(Get-ChildItem (Join-Path $mc 'skills') -Directory).Count + " folders, " + @(Get-ChildItem (Join-Path $mc 'skills') -Filter SKILL.md -Recurse -Depth 1).Count + " SKILL.md"
  'mission control top:'; Get-ChildItem $mc -Force -Name
  'state folder:'; Get-ChildItem $state -Force | ForEach-Object { "  $($_.Mode) $($_.Name)" }
  'program folder:'; Get-ChildItem $app -Force -Name
  '.local\bin:'; Get-ChildItem (Join-Path $env:USERPROFILE '.local\bin') -Name -ErrorAction SilentlyContinue
  'hermes-profile\bin:'; Get-ChildItem (Join-Path $state 'hermes-profile\bin') -Name -ErrorAction SilentlyContinue | Select-Object -First 80
  'device.env (values that could be secret hidden):'; (Get-Content (Join-Path $env:USERPROFILE '.godspeed\device.env') -ErrorAction SilentlyContinue) -replace '((KEY|TOKEN|SECRET|PASS|CODE)[A-Z_]*=).*', '$1(hidden)'
  'user PATH:'; [Environment]::GetEnvironmentVariable('Path', 'User')
  'setup-log, last 40 lines:'; Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt') -Tail 40 -ErrorAction SilentlyContinue
  'service-error.log, last 20 lines:'; Get-Content (Join-Path $state 'service-error.log') -Tail 20 -ErrorAction SilentlyContinue
}

if ($Part -eq 'startup') {
  Section 'stop the notebook, then start it the way the Startup shortcut does (and the troubleshooting page''s command)'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'stop-full-alpha.ps1'); "stop exit: $LASTEXITCODE"
  try { Invoke-RestMethod http://127.0.0.1:47831/health -TimeoutSec 5 | ConvertTo-Json -Compress } catch { "after stopping, health: $($_.Exception.Message)" }
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Godspeed Mission Control Full Alpha.lnk'))
  "running: $($s.TargetPath) $($s.Arguments)"
  # Not Start-Process -Wait: that waits for the notebook it starts as well, which never ends.
  $p = Start-Process -FilePath $s.TargetPath -ArgumentList $s.Arguments -PassThru
  if (-not $p.WaitForExit(180000)) { 'the Startup shortcut''s PowerShell still runs after 3 minutes' } else { "start exit: $($p.ExitCode)" }
  Start-Sleep -Seconds 5
  try { (Invoke-WebRequest http://127.0.0.1:47831/health -UseBasicParsing -TimeoutSec 15).Content } catch { "health after the Startup shortcut: $_" }
  Section 'the same once more with the troubleshooting page''s command, while it runs'
  T 'powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Godspeed Mission Control Full Alpha\start-full-alpha.ps1"'
  try { (Invoke-WebRequest http://127.0.0.1:47831/health -UseBasicParsing -TimeoutSec 15).Content } catch { "health: $_" }
  Get-Process msedge, chrome -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { "a browser was opened: $($_.ProcessName) $($_.MainWindowTitle)" }
}

if ($Part -eq 'commands') {
  $script:Here = $mc
  Section 'commands on PATH in a new PowerShell (terminal-commands: Windows)'
  T 'Get-Command mc-due, mc-goals, mc-work, mc-forecast, mc-compile-rules, mc-check-keys, mc-search, mc-prompt-archive, mc-prompt-harvest, mc-mail, mc-observed-state, mc-run, mc-decide, mc-work-run, mc-check-built-on, mc-research, mc-menerio-connect, hermes, godspeed -ErrorAction Continue | Format-Table Name, Source -AutoSize | Out-String -Width 300'
  T 'mc-due'
  T 'mc-due --help'
  T 'mc-due add nodate --title "No day" --done-when "x"'
  T 'mc-due add dentist --title "Book the dentist" --target 2026-11-15 --done-when "an appointment is booked"'
  T 'mc-due'
  T 'mc-due done dentist --evidence "booked for 20 November"'
  T 'mc-goals help'
  T 'mc-goals list'
  T 'mc-goals file --kind outcome --title "Run a 10 km race" --source "said in chat, 2026-10-17" --area health --measure "a finished 10 km race"'
  T 'mc-goals adopt run-a-10-km-race --why "I said yes on 2026-10-17"'
  T 'mc-work going-out'
  T 'mc-forecast score'
  T 'mc-compile-rules --check'
  T 'mc-check-keys'
  T 'mc-search dentist'
  T 'mc-prompt-archive search zzqqxx-nothing'
  T 'mc-prompt-archive sources'
  T 'mc-prompt-harvest --verbose --no-push'
  T 'mc-mail'
  T 'mc-mail nonsense-word'
  T 'mc-run --list'
  T 'mc-decide --dry-run'
  T 'mc-work-run --dry-run'
  T 'mc-observed-state' -Seconds 60
  T 'mc-menerio-connect --check'
  T 'mc-due --godspeed "$env:USERPROFILE\godspeed-v2"'
  T 'hermes --version'
  Section 'the same in Command Prompt'
  T 'cmd /c "mc-due & mc-compile-rules --check"'
  Section 'the Git Bash only commands (terminal-commands: Windows)'
  T 'mc-check-built-on' -Shell powershell
  T 'mc-research --dry-run' -Shell powershell
  T 'cd ~/godspeed-v2; mc-check-built-on; mc-check-built-on --claim nonsense; mc-research --dry-run; command -v mc-due mc-run' -Shell bash
}

if ($Part -eq 'notebook') {
  $script:Here = $env:USERPROFILE
  Section 'notebook-command.md, the Windows block in PowerShell, then validate'
  $block = @'
$app = "$env:LOCALAPPDATA\Godspeed Mission Control Full Alpha\payload"
$node = "$app\runtime\node.exe"
$notebook = "$app\kit\notebook\bin\godspeed.mjs"
$env:GODSPEED_WORKSPACE = "$env:USERPROFILE\godspeed-v2"
$env:GODSPEED_MEDIA_ROOT = "$env:LOCALAPPDATA\Godspeed Mission Control Full Alpha State\media"
'@
  T ($block + "`n" + '& $node $notebook validate')
  T ($block + "`n" + '& $node $notebook backup "$env:USERPROFILE\godspeed-backups\2026-10-17"; Get-ChildItem "$env:USERPROFILE\godspeed-backups\2026-10-17" -Name')
  T ($block + "`n" + '& $node $notebook export > export-ps51.json; Get-Content export-ps51.json -Encoding Byte -TotalCount 4')
  T ($block + "`n" + '& $node $notebook export > export-ps7.json; Get-Content export-ps7.json -AsByteStream -TotalCount 4') -Shell pwsh
  T ($block + "`n" + 'New-Item -ItemType Directory -Force "$env:USERPROFILE\imp51" | Out-Null; $env:GODSPEED_WORKSPACE = "$env:USERPROFILE\imp51"; & $node $notebook import export-ps51.json')
  T ($block + "`n" + 'New-Item -ItemType Directory -Force "$env:USERPROFILE\imp7" | Out-Null; $env:GODSPEED_WORKSPACE = "$env:USERPROFILE\imp7"; & $node $notebook import export-ps7.json; & $node $notebook import export-ps7.json')
  T ($block + "`n" + 'New-Item -ItemType Directory -Force "$env:USERPROFILE\restored\workspace","$env:USERPROFILE\restored\media" | Out-Null; $env:GODSPEED_WORKSPACE = "$env:USERPROFILE\restored\workspace"; $env:GODSPEED_MEDIA_ROOT = "$env:USERPROFILE\restored\media"; & $node $notebook restore "$env:USERPROFILE\godspeed-backups\2026-10-17"')
  T ($block + "`n" + '& $node $notebook assistant profiles; & $node $notebook food-table status; & $node $notebook init')
  Section 'notebook-command.md, the Git Bash block, then export and import there'
  $bash = @'
APP="$LOCALAPPDATA/Godspeed Mission Control Full Alpha/payload"
NODE="$APP/runtime/node.exe"
NOTEBOOK="$APP/kit/notebook/bin/godspeed.mjs"
export GODSPEED_WORKSPACE="$USERPROFILE/godspeed-v2"
export GODSPEED_MEDIA_ROOT="$LOCALAPPDATA/Godspeed Mission Control Full Alpha State/media"
'@
  T ($bash + "`n" + '"$NODE" "$NOTEBOOK" validate && "$NODE" "$NOTEBOOK" export > export-bash.json && head -c 120 export-bash.json; echo; mkdir -p "$USERPROFILE/impbash" && GODSPEED_WORKSPACE="$USERPROFILE/impbash" "$NODE" "$NOTEBOOK" import export-bash.json') -Shell bash
  Section 'assistant select on Windows (Not yet verified on the page)'
  T ($block + "`n" + '& $node $notebook assistant select no-such-profile')
  Section 'workspace-move plan (changes nothing)'
  T ($block + "`n" + '& $node $notebook workspace-move plan "$env:USERPROFILE\godspeed-moved" "$env:LOCALAPPDATA\Godspeed Mission Control Full Alpha State\installation.json"')
}
