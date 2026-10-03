$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-full-alpha-node.ps1')
$taskFixture=Join-Path $env:TEMP ('Godspeed-backup-root-'+[guid]::NewGuid().ToString('N'))
$taskState=Join-Path $taskFixture 'state'
$taskRetained=Join-Path $taskFixture 'retained'
New-Item -ItemType Directory -Path $taskState,$taskRetained|Out-Null
$taskLink=Join-Path $taskState 'backups'
try {
 if((Get-FullAlphaBackupRoot -State $taskState) -ne $taskLink){throw 'Ordinary backup location changed'}
 Set-Content -LiteralPath (Join-Path $taskRetained 'retained.txt') -Value 'Fictional retained recovery data'
 New-Item -ItemType Junction -Path $taskLink -Target $taskRetained|Out-Null
 if((Get-FullAlphaBackupRoot -State $taskState) -ne $taskRetained){throw 'Linked backup destination was not resolved'}
 if((Get-Content -LiteralPath (Join-Path $taskRetained 'retained.txt')) -ne 'Fictional retained recovery data'){throw 'Retained recovery data changed'}
 Write-Output 'Ordinary and linked backup locations resolved; retained content unchanged.'
} finally {
 # Remove the junction itself before removing the verified temporary fixture.
 if(Test-Path -LiteralPath $taskLink){[IO.Directory]::Delete($taskLink)}
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $taskFixture -Recurse -Force
 }
}
