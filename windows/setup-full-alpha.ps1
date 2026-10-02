param([string]$AppRoot=$PSScriptRoot,[string]$Workspace,[switch]$NoStart,[switch]$NoStartup)
$ErrorActionPreference='Stop'
$AppRoot=[IO.Path]::GetFullPath($AppRoot)
$payload=Join-Path $AppRoot 'payload'
$manifestPath=Join-Path $payload 'candidate-manifest.json'
if(-not(Test-Path -LiteralPath $manifestPath)){throw 'The candidate manifest is missing.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if($manifest.dataFormat -ne 1 -or $manifest.channel -ne 'full-alpha'){throw 'This is not a supported full alpha package.'}
foreach($file in $manifest.files){
  $target=[IO.Path]::GetFullPath((Join-Path $payload $file.path))
  if(-not $target.StartsWith($payload+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid package path.'}
  if(-not(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw "Candidate integrity check failed: $($file.path)"}
}
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
New-Item -ItemType Directory -Force -Path $state|Out-Null
$configFile=Join-Path $state 'installation.json'
if(Test-Path -LiteralPath $configFile){
  $config=Get-Content -LiteralPath $configFile -Raw|ConvertFrom-Json
  if($Workspace -and [IO.Path]::GetFullPath($Workspace) -ne $config.workspace){throw 'An upgrade cannot silently change the candidate workspace.'}
}else{
  if(-not $Workspace){$Workspace=Join-Path $env:USERPROFILE 'GodspeedMissionControl-Full-Alpha'}
  $Workspace=[IO.Path]::GetFullPath($Workspace)
  if((Test-Path -LiteralPath $Workspace) -and (Get-ChildItem -LiteralPath $Workspace -Force|Select-Object -First 1)){throw 'Choose an empty alpha workspace. Existing records are never adopted automatically.'}
  New-Item -ItemType Directory -Force -Path $Workspace|Out-Null
  $config=[pscustomobject]@{channel='full-alpha';workspace=$Workspace;media=(Join-Path $state 'media');port=47831;owner='local';appRoot=$AppRoot;dataFormat=1}
}
if($config.channel -ne 'full-alpha'){throw 'Refusing to modify a stable installation.'}
if(Test-Path -LiteralPath (Join-Path $AppRoot 'stop-full-alpha.ps1')){& (Join-Path $AppRoot 'stop-full-alpha.ps1')}
# Record and media backup precede replacement of runtime settings. Software changes never alter data format here.
if(Test-Path -LiteralPath (Join-Path $config.workspace 'records')){
  $backup=Join-Path $state ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  New-Item -ItemType Directory -Force -Path $backup|Out-Null
  Copy-Item -LiteralPath (Join-Path $config.workspace 'records') -Destination $backup -Recurse
  if(Test-Path -LiteralPath $config.media){Copy-Item -LiteralPath $config.media -Destination (Join-Path $backup 'media') -Recurse}
}
$config.appRoot=$AppRoot
$temporary=$configFile+'.tmp';$config|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -LiteralPath $temporary -Destination $configFile -Force
if(-not $NoStartup){
  $shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'Godspeed Mission Control Full Alpha.lnk'
  $shellObject=New-Object -ComObject WScript.Shell
  $shortcut=$shellObject.CreateShortcut($shortcutPath)
  $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $AppRoot 'start-full-alpha.ps1')+'"'
  $shortcut.WindowStyle=7;$shortcut.Save()
}
if(-not $NoStart){& (Join-Path $AppRoot 'start-full-alpha.ps1') -NoBrowser}
