param([string]$AppRoot=$PSScriptRoot,[string]$Workspace,[int]$Port=47831,[switch]$NoStart,[switch]$NoStartup,[switch]$SkipHermes,[switch]$OriginalStarter)
$ErrorActionPreference='Stop'
$env:GODSPEED_ORIGINAL_RUNTIME='on'
. (Join-Path $PSScriptRoot 'invoke-notebook-node.ps1')
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$env:NODE_NO_WARNINGS='1'
$AppRoot=[IO.Path]::GetFullPath($AppRoot)
$payload=Join-Path $AppRoot 'payload'
$manifestPath=Join-Path $payload 'candidate-manifest.json'
if(-not(Test-Path -LiteralPath $manifestPath)){throw 'The list of the notebook program''s files is missing. Download the installer again.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
# 'full-alpha' is the format's name, read by installed notebooks (installation.json) and never shown,
# so it stays while the folders and scripts that said "Full Alpha" do not.
if($manifest.dataFormat -ne 1 -or $manifest.channel -ne 'full-alpha'){throw 'This installer carries a notebook this setup cannot install. Download the newest installer.'}
foreach($file in $manifest.files){
  $target=[IO.Path]::GetFullPath((Join-Path $payload $file.path))
  if(-not $target.StartsWith($payload+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid package path.'}
  if(-not(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw "A file of the notebook program is damaged ($($file.path)). Download the installer again."}
}
# The new name, or the old one of an install made before 2.0.0-beta.11 (godspeed-folders.ps1).
$state=Get-GodspeedStateFolder
New-Item -ItemType Directory -Force -Path $state|Out-Null
$configFile=Join-Path $state 'installation.json'
if(Test-Path -LiteralPath $configFile){
  $config=Get-Content -LiteralPath $configFile -Raw|ConvertFrom-Json
  if($Workspace -and [IO.Path]::GetFullPath($Workspace) -ne $config.workspace){throw ('This PC''s notebook belongs to the mission control at '+$config.workspace+', and an update cannot move it to another folder.')}
}else{
  if(-not $Workspace){$Workspace=Join-Path $env:USERPROFILE 'godspeed-v2'}
  $Workspace=[IO.Path]::GetFullPath($Workspace)
  if((Test-Path -LiteralPath $Workspace) -and (Get-ChildItem -LiteralPath $Workspace -Force|Select-Object -First 1) -and -not($OriginalStarter -and (Test-Path -LiteralPath (Join-Path $Workspace 'rules')) -and (Test-Path -LiteralPath (Join-Path $Workspace 'AGENTS.md')))){throw 'That folder already holds files. Choose an empty folder, or a mission control folder made by an earlier Godspeed setup.'}
  New-Item -ItemType Directory -Force -Path $Workspace|Out-Null
  if($Port -lt 1024 -or $Port -gt 65535){throw 'Choose an unused port above 1023 for the notebook.'}
  $config=[pscustomobject]@{channel='full-alpha';workspace=$Workspace;media=(Join-Path $state 'media');port=$Port;owner='local';appRoot=$AppRoot;dataFormat=1}
}
if($config.channel -ne 'full-alpha'){throw 'The notebook record on this PC is not one this setup made, so it was left alone.'}
# An older installer never replaces a newer notebook on this PC (6 October 2026). Since 18 October
# 2026 the wizard refuses before it touches anything (detect-godspeed.ps1); this stays for a setup
# started some other way.
if($config.kitCommittedAt -and $manifest.kitCommittedAt -and ([datetimeoffset]$manifest.kitCommittedAt) -lt ([datetimeoffset]$config.kitCommittedAt)){
  throw ('This installer holds an older version ('+$manifest.kitCommit.Substring(0,7)+') than the one on this PC ('+$config.kitCommit.Substring(0,7)+'). Use the newest installer.')
}
foreach($name in 'kitCommit','kitCommittedAt'){if($manifest.$name){$config|Add-Member -NotePropertyName $name -NotePropertyValue $manifest.$name -Force}}
if(Test-Path -LiteralPath (Join-Path $AppRoot 'stop-notebook.ps1')){& (Join-Path $AppRoot 'stop-notebook.ps1')}
# Record and media backup precede replacement of runtime settings. Software changes never alter data format here.
# The notebook folder was records/ until 2026-10-05; an upgrade backs up either.
# --before-update (the product's notebook/core/update-copy.mjs): only what an update can change, never
# work/, and in a mission control that is its own Git repository only what its commit does not already
# hold. Until 21 October 2026 this copied every durable folder whole: on one PC 8.33 GB and sixteen
# minutes, and with 5.4 GB free the update refused to start. Now that PC's copy is 85 MB in seconds.
$backup=$null
if((Test-Path -LiteralPath (Join-Path $config.workspace 'notebook')) -or (Test-Path -LiteralPath (Join-Path $config.workspace 'records'))){
  $backupRoot=Get-NotebookBackupRoot -State $state
  $backup=Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
  $env:GODSPEED_WORKSPACE=$config.workspace;$env:GODSPEED_MEDIA_ROOT=$config.media
  Invoke-NotebookNode -Node (Join-Path $payload 'runtime\node.exe') -Arguments @((Join-Path $payload 'kit\notebook\bin\godspeed.mjs'),'backup',$backup,'--before-update') -Step 'Saving a copy of your notebook before the update'
}
$config.appRoot=$AppRoot
$env:GODSPEED_WORKSPACE=$config.workspace;$env:GODSPEED_MEDIA_ROOT=$config.media
Invoke-NotebookNode -Node (Join-Path $payload 'runtime\node.exe') -Arguments @((Join-Path $payload 'kit\notebook\bin\godspeed.mjs'),'init') -Step 'Setting up the notebook'
# The record of which workspace is this installation's, kept as soon as that workspace exists. Until
# 6 October 2026 it was written last, so a setup that stopped at a later step left a workspace that
# no start, stop or upgrade could find.
function Save-NotebookInstallation {
  $temporary=$configFile+'.tmp';$config|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $configFile -Force
}
Save-NotebookInstallation
# Joining: a mission control that is its own Git repository carries the notebook in that same
# repository. envy and x30 were switched by hand on 5 October 2026; now the installer does it,
# once, and a refusal (an ignore list to complete, a public repository) leaves the notebook
# working on this PC alone, with the reason in this log.
if(-not(Test-Path -LiteralPath (Join-Path $config.workspace '.godspeed\sync-config.json')) -and (Test-Path -LiteralPath (Join-Path $config.workspace '.git'))){
  $origin=Invoke-NotebookNative -Command git -Arguments @('-C',$config.workspace,'remote','get-url','origin')
  if($origin.Code -eq 0 -and $origin.Output){
    try{Invoke-NotebookNode -Node (Join-Path $payload 'runtime\node.exe') -Arguments @((Join-Path $payload 'kit\notebook\bin\godspeed.mjs'),'sync','folder') -Step 'Joining the mission control repository'}
    catch{Write-Output ('The notebook was not joined to the repository: '+$_.Exception.Message)}
  }
}
if(-not $SkipHermes){& (Join-Path $AppRoot 'ensure-hermes.ps1') -State $state -Workspace $config.workspace -Port $config.port -Provision|Out-Null}
Save-NotebookInstallation
# The notebook starts at sign-in, quietly. Until 18 October 2026 the entry left out -NoBrowser, so
# every sign-in opened the notebook in the browser, and it was named "... Full Alpha", which is what
# Windows shows under Startup apps. The old name is removed so there is only one.
if(-not $NoStartup){
  $startup=[Environment]::GetFolderPath('Startup')
  $oldShortcut=Join-Path $startup 'Godspeed Mission Control Full Alpha.lnk'
  if(Test-Path -LiteralPath $oldShortcut){Remove-Item -LiteralPath $oldShortcut -Force}
  $shortcutPath=Join-Path $startup 'Godspeed Mission Control.lnk'
  $shellObject=New-Object -ComObject WScript.Shell
  $shortcut=$shellObject.CreateShortcut($shortcutPath)
  $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $AppRoot 'start-notebook.ps1')+'" -NoBrowser'
  $shortcut.Description='Starts your Godspeed Mission Control notebook when you sign in'
  $shortcut.WindowStyle=7;$shortcut.Save()
  # The setup's own scripts were named ...-full-alpha.ps1 until 2.0.0-beta.11, and an update of an
  # install made before puts the new ones beside them. Once the Startup entry names the new start
  # script nothing points at the old ones, so they go.
  foreach($oldScript in 'setup-full-alpha.ps1','invoke-full-alpha-node.ps1','start-full-alpha.ps1','stop-full-alpha.ps1','ensure-hermes-full-alpha.ps1','open-hermes-full-alpha.ps1','computer-full-alpha.ps1'){
    Remove-Item -LiteralPath (Join-Path $AppRoot $oldScript) -Force -ErrorAction SilentlyContinue
  }
}
# ensure-hermes.ps1 above has just connected the assistant (-Wired): until 21 October 2026
# the start did it again, which on one PC cost two more minutes of the update.
$answered=$true
if(-not $NoStart){$answered=(@(& (Join-Path $AppRoot 'start-notebook.ps1') -NoBrowser -Wired:(-not $SkipHermes) -PassThru)|Select-Object -Last 1) -eq $true}
# Every step of the update worked: start-notebook.ps1 throws when the notebook did not start, which
# ends this setup before here, and says $false when it is still starting after its wait. Once it
# answered, the copy made before this update stays as the way back and every older one goes, the
# whole copies earlier versions made too (Invoke-NotebookPruneUpdateCopies). Until 15 October 2026
# none was ever removed; until 21 October 2026 the newest three stayed.
if($backup -and $answered){Invoke-NotebookPruneUpdateCopies -Node (Join-Path $payload 'runtime\node.exe') -Kit (Join-Path $payload 'kit') -BackupRoot $backupRoot -Made $backup}
elseif($backup){Write-Output 'Older copies made before updates are removed after the next update whose notebook answers.'}
