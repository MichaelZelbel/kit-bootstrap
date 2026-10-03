$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-full-alpha-node.ps1')
$taskNode=(Get-Command node -ErrorAction Stop).Source
# Successful warnings must not make a valid upgrade fail on native 5.1.
Invoke-FullAlphaNode -Node $taskNode -Arguments @('-e',"process.stderr.write('Fictional harmless warning\n');process.exit(0)") -Step 'Fictional success'
$taskTranscript=@()
try{
 Invoke-FullAlphaNode -Node $taskNode -Arguments @('-e',"process.stderr.write('Fictional error first line\nFictional error second line\n');process.exit(7)") -Step 'Fictional failure' | ForEach-Object {$taskTranscript += [string]$_}
 throw 'Nonzero native exit was accepted'
}catch{
 if($_.Exception.Message -notmatch 'Fictional failure failed \(exit 7\)'){throw}
}
if(($taskTranscript -join "`n") -notmatch 'Fictional error second line'){throw 'Complete native diagnostic was lost'}
Write-Output 'Successful native warning accepted; complete failed-process diagnostic retained.'
