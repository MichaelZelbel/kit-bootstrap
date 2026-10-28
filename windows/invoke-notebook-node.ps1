function Get-NotebookBackupRoot {
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
# A native command whose failure is an answer, not an error: git asked for a remote that a new
# mission control does not have yet. Under Stop, Windows PowerShell 5.1 turns its stderr into a
# terminating error, which until 6 October 2026 ended every first install at the repository step.
function Invoke-NotebookNative {
 param([Parameter(Mandatory)][string]$Command,[string[]]$Arguments=@())
 # A missing program leaves $LASTEXITCODE at whatever ran before, which may read as success.
 if(-not(Get-Command $Command -ErrorAction SilentlyContinue)){return [pscustomobject]@{Code=127;Output=''}}
 $taskPreviousPreference=$ErrorActionPreference
 try {
  $ErrorActionPreference='Continue'
  $taskOutput=@(& $Command @Arguments 2>$null)
  $taskCode=$LASTEXITCODE
 } finally {$ErrorActionPreference=$taskPreviousPreference}
 [pscustomobject]@{Code=$taskCode;Output=(($taskOutput|ForEach-Object {[string]$_}) -join "`n").Trim()}
}
function Invoke-NotebookNode {
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
# After an update that worked, the copy it made before stays and older ones go, by the notebook's
# own rule (the product's notebook/core/upgrade-copies.mjs, which also never touches a folder no
# installer made, and lets go of the Git ref a copy made with Git keeps). Until 15 October 2026
# every update added one and none was removed; one PC had nine, 36 GB. A notebook version without
# that rule removes nothing, and a copy that cannot be removed is said once and never fails the
# update that worked.
function Invoke-NotebookPruneUpdateCopies {
 param([Parameter(Mandatory)][string]$Node,[Parameter(Mandatory)][string]$Kit,[Parameter(Mandatory)][string]$BackupRoot,[Parameter(Mandatory)][string]$Made)
 if(-not(Test-Path -LiteralPath (Join-Path $Kit 'notebook\core\upgrade-copies.mjs'))){return}
 $taskPrune=Invoke-NotebookNative -Command $Node -Arguments @((Join-Path $Kit 'notebook\bin\godspeed.mjs'),'prune-backups',$BackupRoot,'--made',$Made)
 if($taskPrune.Code -ne 0){Write-Output ('Older backups made before updates could not all be removed. They are in '+$BackupRoot)}
}
