param([Parameter(Mandatory)][string]$State,[Parameter(Mandatory)][string]$Workspace,[switch]$Provision,[switch]$ForceIsolatedInstall)
$ErrorActionPreference='Stop'
$runtimeHome=Join-Path $State 'hermes-runtime'
$profileHome=Join-Path $State 'hermes-profile'
New-Item -ItemType Directory -Force -Path $profileHome|Out-Null
$executable=$null;$sourceRoot=$null
if(-not $ForceIsolatedInstall){
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
  $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','"'+$installer+'"','-HermesHome','"'+$runtimeHome+'"','-InstallDir','"'+$sourceRoot+'"','-Commit',$source.commit,'-NonInteractive','-SkipSetup','-SkipComputerUse','-IncludeDesktop') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $State 'hermes-install-error.log')
  if($process.ExitCode -ne 0){throw 'The isolated Hermes desktop installation failed. The notebook files remain available; the installer log is in candidate state.'}
  $executable=Join-Path $runtimeHome 'bin\hermes.exe'
}
$desktop=if($sourceRoot){Join-Path $sourceRoot 'apps\desktop\release\win-unpacked\Hermes.exe'}else{$null}
if(-not $desktop -or -not(Test-Path -LiteralPath $desktop)){
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
$descriptor
