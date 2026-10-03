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
