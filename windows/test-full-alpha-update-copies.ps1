param([Parameter(Mandatory)][string]$KitCheckout)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-full-alpha-node.ps1')
# The copies an update makes before it changes anything: until 15 October 2026 none was ever removed.
# KitCheckout is a checkout of godspeed-mission-control whose notebook has the rule
# (notebook/core/upgrade-copies.mjs), as the payload of the setup carries it.
$taskNode=(Get-Command node -ErrorAction Stop).Source
$taskKit=[IO.Path]::GetFullPath($KitCheckout)
if(-not(Test-Path -LiteralPath (Join-Path $taskKit 'notebook\core\upgrade-copies.mjs'))){throw 'KitCheckout has no notebook\core\upgrade-copies.mjs.'}
$taskFixture=Join-Path $env:TEMP ('Godspeed-update-copies-'+[guid]::NewGuid().ToString('N'))
function New-TaskCopy([string]$Folder,[string]$Name){
 New-Item -ItemType Directory -Force -Path (Join-Path $Folder $Name)|Out-Null
 Set-Content -LiteralPath (Join-Path (Join-Path $Folder $Name) 'backup.json') -Value '{"format":1,"files":[]}'
 return $Name
}
function Get-TaskNames([string]$Folder){@(Get-ChildItem -LiteralPath $Folder -Force|ForEach-Object {$_.Name}|Sort-Object)}
try {
 # The setup's own copies, a nightly-style one, and a folder of the owner's own.
 $taskBackups=Join-Path $taskFixture 'backups'
 $taskOlder=foreach($taskDay in 1..5){New-TaskCopy $taskBackups ('2026100'+$taskDay+'-090000-00'+$taskDay)}
 New-Item -ItemType Directory -Force -Path (Join-Path $taskBackups 'my own folder'),(Join-Path $taskBackups '1760000000000')|Out-Null
 $taskMade=Join-Path $taskBackups (New-TaskCopy $taskBackups '20261015-101010-123')
 $taskSaid=@(Invoke-FullAlphaPruneUpdateCopies -Node $taskNode -Kit $taskKit -BackupRoot $taskBackups -Made $taskMade)
 if($taskSaid.Count){throw ('An update that worked said: '+($taskSaid -join ' '))}
 $taskWant=@($taskOlder[3],$taskOlder[4],'20261015-101010-123','1760000000000','my own folder')|Sort-Object
 if(((Get-TaskNames $taskBackups) -join '|') -ne ($taskWant -join '|')){throw ('After an update that worked the backups are: '+((Get-TaskNames $taskBackups) -join ', '))}
 Write-Output 'After an update that worked, the newest three copies stay and older ones go; other folders stay.'

 # A notebook version without the rule removes nothing and says nothing.
 $taskOld=Join-Path $taskFixture 'old-kit'
 New-Item -ItemType Directory -Force -Path (Join-Path $taskOld 'notebook\bin')|Out-Null
 Set-Content -LiteralPath (Join-Path $taskOld 'notebook\bin\godspeed.mjs') -Value 'process.exit(9)'
 foreach($taskDay in 6..9){New-TaskCopy $taskBackups ('2026100'+$taskDay+'-090000-00'+$taskDay)|Out-Null}
 $taskBefore=(Get-TaskNames $taskBackups) -join '|'
 $taskSaid=@(Invoke-FullAlphaPruneUpdateCopies -Node $taskNode -Kit $taskOld -BackupRoot $taskBackups -Made $taskMade)
 if($taskSaid.Count -or ((Get-TaskNames $taskBackups) -join '|') -ne $taskBefore){throw 'A notebook without the rule removed or said something'}
 Write-Output 'A notebook version without the rule removes nothing.'

 # A command that fails is said once, never thrown, and removes nothing.
 New-Item -ItemType Directory -Force -Path (Join-Path $taskOld 'notebook\core')|Out-Null
 Set-Content -LiteralPath (Join-Path $taskOld 'notebook\core\upgrade-copies.mjs') -Value ''
 $taskSaid=@(Invoke-FullAlphaPruneUpdateCopies -Node $taskNode -Kit $taskOld -BackupRoot $taskBackups -Made $taskMade)
 if($taskSaid.Count -ne 1 -or $taskSaid[0] -notmatch 'could not all be removed'){throw ('A failed removal said: '+($taskSaid -join ' '))}
 if(((Get-TaskNames $taskBackups) -join '|') -ne $taskBefore){throw 'A failed removal changed the backups'}
 Write-Output 'A removal that fails is said once and never fails the update.'
} finally {
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $taskFixture)){
  Remove-Item -LiteralPath $taskFixture -Recurse -Force
 }
}
# Only after every step of an update: the call comes after the notebook was started and answered
# (start-full-alpha.ps1 throws when it does not), and only when this setup made a copy.
$taskSetup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-full-alpha.ps1')
$taskStart=($taskSetup|Select-String -SimpleMatch "start-full-alpha.ps1') -NoBrowser").LineNumber
$taskPrune=@($taskSetup|Select-String -Pattern '^\s*[^#\s].*Invoke-FullAlphaPruneUpdateCopies')
if($taskPrune.Count -ne 1 -or $taskPrune[0].LineNumber -le $taskStart -or $taskPrune[0].Line -notmatch '^if\(\$backup\)'){throw 'The setup removes copies somewhere other than after the notebook answered'}
Write-Output 'The setup removes older copies only after the notebook answered, and only when it made one.'
