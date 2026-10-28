$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-notebook-node.ps1')
$taskFixture=Join-Path $env:TEMP ('Godspeed-backup-root-'+[guid]::NewGuid().ToString('N'))
$taskState=Join-Path $taskFixture 'state'
$taskRetained=Join-Path $taskFixture 'retained'
New-Item -ItemType Directory -Path $taskState,$taskRetained|Out-Null
$taskLink=Join-Path $taskState 'backups'
# Compared as folders, not as spellings: on a GitHub machine TEMP is a short 8.3 path
# (C:\Users\RUNNER~1\...), while the junction hands back its target in the long form.
Add-Type -Namespace KbTest -Name LongPath -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern uint GetLongPathName(string s, System.Text.StringBuilder l, uint n);'
function Get-TaskLongPath([string]$Path){$taskBuffer=New-Object System.Text.StringBuilder 1024;if([KbTest.LongPath]::GetLongPathName($Path,$taskBuffer,1024) -gt 0){return $taskBuffer.ToString().TrimEnd('\')};return $Path.TrimEnd('\')}
try {
 if((Get-TaskLongPath (Get-NotebookBackupRoot -State $taskState)) -ne (Get-TaskLongPath $taskLink)){throw 'Ordinary backup location changed'}
 Set-Content -LiteralPath (Join-Path $taskRetained 'retained.txt') -Value 'Fictional retained recovery data'
 New-Item -ItemType Junction -Path $taskLink -Target $taskRetained|Out-Null
 if((Get-TaskLongPath (Get-NotebookBackupRoot -State $taskState)) -ne (Get-TaskLongPath $taskRetained)){throw 'Linked backup destination was not resolved'}
 if((Get-Content -LiteralPath (Join-Path $taskRetained 'retained.txt')) -ne 'Fictional retained recovery data'){throw 'Retained recovery data changed'}
 Write-Output 'Ordinary and linked backup locations resolved; retained content unchanged.'
} finally {
 # Remove the junction itself before removing the verified temporary fixture.
 if(Test-Path -LiteralPath $taskLink){[IO.Directory]::Delete($taskLink)}
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $taskFixture -Recurse -Force
 }
}
