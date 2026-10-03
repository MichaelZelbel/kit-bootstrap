function Get-FullAlphaBackupRoot {
 param([Parameter(Mandatory)][string]$State)
 $taskRoot=Join-Path $State 'backups'
 if(Test-Path -LiteralPath $taskRoot){
  $taskDirectory=Get-Item -LiteralPath $taskRoot -Force
  if(-not $taskDirectory.PSIsContainer){throw 'The retained backup location is not a directory.'}
  if($taskDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint){
   $taskTarget=@($taskDirectory.Target)|Select-Object -First 1
   if(-not $taskTarget){throw 'The retained backup link has no readable destination.'}
   if(-not [IO.Path]::IsPathRooted($taskTarget)){$taskTarget=Join-Path $taskDirectory.Parent.FullName $taskTarget}
   $taskRoot=[IO.Path]::GetFullPath($taskTarget)
   if(-not(Test-Path -LiteralPath $taskRoot -PathType Container)){throw 'The retained backup destination is unavailable.'}
  }
 }
 return $taskRoot
}
function Invoke-FullAlphaNode {
 param([Parameter(Mandatory)][string]$Node,[Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$Step)
 # Windows PowerShell 5.1 turns native stderr into ErrorRecord objects. Stop
 # would abort at the first stack line before the process exit can be checked.
 $taskPreviousPreference=$ErrorActionPreference
 try {
  $ErrorActionPreference='Continue'
  $taskOutput=@(& $Node @Arguments 2>&1)
  $taskCode=$LASTEXITCODE
 } finally {$ErrorActionPreference=$taskPreviousPreference}
 if($taskCode -ne 0){
  foreach($taskLine in $taskOutput){Write-Output ([string]$taskLine)}
  throw ($Step+' failed (exit '+$taskCode+'). Upgrade stopped; retained recovery copies are unchanged.')
 }
}
