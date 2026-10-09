param([Parameter(Mandatory)][string]$State,[Parameter(Mandatory)][string]$Workspace,[int]$Port=47831,[switch]$Provision,[switch]$ForceIsolatedInstall)
$ErrorActionPreference='Stop'
$runtimeHome=Join-Path $State 'hermes-runtime'
$profileHome=Join-Path $State 'hermes-profile'
New-Item -ItemType Directory -Force -Path $profileHome|Out-Null
$executable=$null;$sourceRoot=$null
$managedSource=Join-Path $runtimeHome 'hermes-agent'
if(-not $ForceIsolatedInstall -and (Test-Path -LiteralPath (Join-Path $runtimeHome 'bin\hermes.exe')) -and (Test-Path -LiteralPath (Join-Path $managedSource 'apps\desktop\release\win-unpacked\Hermes.exe'))){$executable=Join-Path $runtimeHome 'bin\hermes.exe';$sourceRoot=$managedSource}
if(-not $ForceIsolatedInstall -and -not $sourceRoot){
  $installed=Get-Command hermes.exe -ErrorAction SilentlyContinue
  if($installed){
    $executable=$installed.Source
    $possible=Join-Path (Split-Path -Parent (Split-Path -Parent $executable)) 'hermes-agent'
    if(Test-Path -LiteralPath (Join-Path $possible 'apps\desktop\release\win-unpacked\Hermes.exe')){$sourceRoot=$possible}
  }
}
if(-not $sourceRoot -and $Provision){
  $installer=Join-Path $PSScriptRoot 'vendor\hermes-install.ps1'
  $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vendor\hermes-source.json') -Raw|ConvertFrom-Json
  $canonical=[Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $installer -Raw -Encoding UTF8).Replace("`r`n","`n"))
  $canonicalHash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($canonical)).Replace('-','').ToLowerInvariant()
  if($canonicalHash -ne $source.sha256){throw 'Hermes installer integrity check failed.'}
  $sourceRoot=Join-Path $runtimeHome 'hermes-agent'
  $log=Join-Path $State 'hermes-install.log'
  $env:UV_NO_MODIFY_PATH='1'
  $env:UV_UNMANAGED_INSTALL=Join-Path $runtimeHome 'bin'
  $env:UV_CACHE_DIR=Join-Path $runtimeHome 'uv-cache'
  $env:UV_TOOL_DIR=Join-Path $runtimeHome 'uv-tools'
  $env:NPM_CONFIG_CACHE=Join-Path $runtimeHome 'npm-cache'
  $env:PLAYWRIGHT_BROWSERS_PATH=Join-Path $runtimeHome 'browser-cache'
  $env:GIT_CONFIG_COUNT='2'
  $env:GIT_CONFIG_KEY_0='windows.appendAtomically';$env:GIT_CONFIG_VALUE_0='false'
  $env:GIT_CONFIG_KEY_1='core.longpaths';$env:GIT_CONFIG_VALUE_1='true'
  $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$installer+'"'),'-HermesHome',('"'+$runtimeHome+'"'),'-InstallDir',('"'+$sourceRoot+'"'),'-Commit',$source.commit,'-NonInteractive','-SkipSetup','-SkipComputerUse','-IncludeDesktop') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $State 'hermes-install-error.log')
  if($process.ExitCode -ne 0){throw 'The isolated Hermes desktop installation failed. The notebook files remain available; the installer log is in candidate state.'}
  $executable=Join-Path $runtimeHome 'bin\hermes.exe'
}
$desktop=if($sourceRoot){Join-Path $sourceRoot 'apps\desktop\release\win-unpacked\Hermes.exe'}else{$null}
if(-not $desktop -or -not(Test-Path -LiteralPath $desktop)){
  if($Provision){throw 'Hermes provisioning did not produce the candidate desktop. Check the saved candidate provisioning logs.'}
  [pscustomobject]@{verified=$false;reason='Hermes desktop is not installed in the candidate runtime.'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $State 'assistant.json') -Encoding UTF8
  return
}
# Only new candidate configuration is written. The installed default profile is never read or changed.
$config=Join-Path $profileHome 'config.yaml'
if(-not(Test-Path -LiteralPath $config)){
  $workspaceJson=ConvertTo-Json $Workspace -Compress
  $skillsJson=ConvertTo-Json @((Join-Path $Workspace 'skills')) -Compress
  @("terminal:","  cwd: $workspaceJson","skills:","  external_dirs: $skillsJson","memory:","  memory_enabled: false")|Set-Content -LiteralPath $config -Encoding UTF8
}
$descriptor=[pscustomobject]@{verified=$true;kind='hermes';executable=$executable;desktop=$desktop;sourceRoot=$sourceRoot;home=$profileHome;workspace=$Workspace}
$descriptor|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $State 'assistant.json') -Encoding UTF8
$env:GODSPEED_WORKSPACE=$Workspace;$env:GODSPEED_PORT=[string]$Port;$env:GODSPEED_DEVICE='local';$env:NODE_NO_WARNINGS='1'
$config=Get-Content -LiteralPath (Join-Path $State 'installation.json') -Raw -ErrorAction SilentlyContinue|ConvertFrom-Json
$appRoot=if($config){$config.appRoot}else{$PSScriptRoot}
& (Join-Path $appRoot 'payload\runtime\node.exe') (Join-Path $appRoot 'payload\kit\notebook\scripts\wire-assistant.mjs') $profileHome|Out-Null
if($LASTEXITCODE -ne 0){throw 'Candidate assistant connection settings could not be saved.'}
# The mail tool in this assistant's own profile, after wire-assistant gave it the notebook tool (the other
# order would leave the notebook tool out). Connect-KitMail in join.ps1 runs before this profile exists
# and wires only the default Hermes, so until 8 October 2026 the assistant the reader talks to had no
# mail tool. mc-mail setup finds this profile through assistant.json. Email is optional: this never
# stops the setup.
$mailTool=Join-Path $appRoot 'payload\kit\tools\mc-mail.js'
if(Test-Path -LiteralPath $mailTool){
  $env:GODSPEED_DIR=$Workspace
  try{& (Join-Path $appRoot 'payload\runtime\node.exe') $mailTool setup|Out-Null}catch{}
  $global:LASTEXITCODE=0
}
$descriptor
