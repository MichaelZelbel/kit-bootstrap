param([Parameter(Mandatory)][string]$KitCheckout)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-full-alpha-node.ps1')
# The copies an update makes before it changes anything: until 15 October 2026 none was ever removed,
# and until 21 October 2026 each was a whole copy of every durable folder (8.33 GB on one PC).
# KitCheckout is a checkout of godspeed-mission-control whose notebook has both rules
# (notebook/core/upgrade-copies.mjs and notebook/core/update-copy.mjs), as the payload of the setup carries it.
$taskNode=(Get-Command node -ErrorAction Stop).Source
$taskKit=[IO.Path]::GetFullPath($KitCheckout)
foreach($taskRule in 'upgrade-copies.mjs','update-copy.mjs'){if(-not(Test-Path -LiteralPath (Join-Path $taskKit ('notebook\core\'+$taskRule)))){throw ('KitCheckout has no notebook\core\'+$taskRule+'.')}}
$taskFixture=Join-Path $env:TEMP ('Godspeed-update-copies-'+[guid]::NewGuid().ToString('N'))
function New-TaskCopy([string]$Folder,[string]$Name){
 New-Item -ItemType Directory -Force -Path (Join-Path $Folder $Name)|Out-Null
 Set-Content -LiteralPath (Join-Path (Join-Path $Folder $Name) 'backup.json') -Value '{"format":1,"files":[]}'
 return $Name
}
function Get-TaskNames([string]$Folder){@(Get-ChildItem -LiteralPath $Folder -Force|ForEach-Object {$_.Name}|Sort-Object)}
function Invoke-TaskGit([string]$Folder,[string[]]$Arguments){
 $taskOutput=Invoke-FullAlphaNative -Command git -Arguments (@('-C',$Folder)+$Arguments)
 if($taskOutput.Code -ne 0){throw ('git '+($Arguments -join ' ')+' failed in the test fixture')}
 return $taskOutput.Output
}
try {
 # The setup's own copies, a nightly-style one, and a folder of the owner's own.
 $taskBackups=Join-Path $taskFixture 'backups'
 $taskOlder=foreach($taskDay in 1..5){New-TaskCopy $taskBackups ('2026100'+$taskDay+'-090000-00'+$taskDay)}
 New-Item -ItemType Directory -Force -Path (Join-Path $taskBackups 'my own folder'),(Join-Path $taskBackups '1760000000000')|Out-Null
 $taskMade=Join-Path $taskBackups (New-TaskCopy $taskBackups '20261015-101010-123')
 $taskSaid=@(Invoke-FullAlphaPruneUpdateCopies -Node $taskNode -Kit $taskKit -BackupRoot $taskBackups -Made $taskMade)
 if($taskSaid.Count){throw ('An update that worked said: '+($taskSaid -join ' '))}
 $taskWant=@('20261015-101010-123','1760000000000','my own folder')|Sort-Object
 if(((Get-TaskNames $taskBackups) -join '|') -ne ($taskWant -join '|')){throw ('After an update that worked the backups are: '+((Get-TaskNames $taskBackups) -join ', '))}
 Write-Output 'After an update that worked, the copy it made stays and older ones go; other folders stay.'

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

 # The copy itself, made the way the setup makes it, of a mission control that is its own Git
 # repository: only what its commit does not hold, never work/, and the commit kept by a ref.
 $taskWorkspace=Join-Path $taskFixture 'mission control'
 foreach($taskName in 'notebook','work','skills\mine'){New-Item -ItemType Directory -Force -Path (Join-Path $taskWorkspace $taskName)|Out-Null}
 Set-Content -LiteralPath (Join-Path $taskWorkspace '.gitignore') -Value '.godspeed/'
 Set-Content -LiteralPath (Join-Path $taskWorkspace 'AGENTS.md') -Value 'A fictional manual'
 Set-Content -LiteralPath (Join-Path $taskWorkspace 'notebook\Fictional page.md') -Value 'A fictional page'
 Invoke-TaskGit $taskWorkspace @('init','-q')|Out-Null
 Invoke-TaskGit $taskWorkspace @('add','-A')|Out-Null
 Invoke-TaskGit $taskWorkspace @('-c','user.name=Fictional','-c','user.email=fictional@example.invalid','commit','-q','-m','A fictional day')|Out-Null
 Set-Content -LiteralPath (Join-Path $taskWorkspace 'skills\mine\SKILL.md') -Value 'A recipe nobody committed'
 [IO.File]::WriteAllBytes((Join-Path $taskWorkspace 'work\recording.bin'),(New-Object byte[] 1048576))
 $taskCopies=Join-Path $taskFixture 'setup-backups'
 New-TaskCopy $taskCopies '20261001-090000-001'|Out-Null
 $taskCopy=Join-Path $taskCopies (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
 $env:GODSPEED_WORKSPACE=$taskWorkspace;$env:GODSPEED_MEDIA_ROOT=(Join-Path $taskFixture 'media')
 Invoke-FullAlphaNode -Node $taskNode -Arguments @((Join-Path $taskKit 'notebook\bin\godspeed.mjs'),'backup',$taskCopy,'--before-update') -Step 'Saving a copy of your notebook before the update'
 $taskManifest=Get-Content -LiteralPath (Join-Path $taskCopy 'backup.json') -Raw|ConvertFrom-Json
 $taskSaved=@($taskManifest.files|ForEach-Object {$_.path})
 if($taskManifest.format -ne 2 -or $taskManifest.kind -ne 'update-copy'){throw 'The copy made before the update is not the copy of what an update can change'}
 if(($taskSaved -join '|') -ne 'skills/mine/SKILL.md'){throw ('The copy holds: '+($taskSaved -join ', '))}
 if(Test-Path -LiteralPath (Join-Path $taskCopy 'work')){throw 'The copy holds work/'}
 $taskRef=Invoke-TaskGit $taskWorkspace @('rev-parse',$taskManifest.git.ref)
 if($taskRef -ne (Invoke-TaskGit $taskWorkspace @('rev-parse','HEAD'))){throw 'The copy does not keep the commit it was made at'}
 Write-Output 'The copy made before an update holds only what the commit does not, never work/, and keeps the commit.'

 # The next update that worked: its copy stays, the one before goes with its ref, and so does the
 # whole copy an earlier version made.
 Start-Sleep -Milliseconds 20
 $taskNext=Join-Path $taskCopies (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
 Invoke-FullAlphaNode -Node $taskNode -Arguments @((Join-Path $taskKit 'notebook\bin\godspeed.mjs'),'backup',$taskNext,'--before-update') -Step 'Saving a copy of your notebook before the update'
 $taskSaid=@(Invoke-FullAlphaPruneUpdateCopies -Node $taskNode -Kit $taskKit -BackupRoot $taskCopies -Made $taskNext)
 if($taskSaid.Count){throw ('An update that worked said: '+($taskSaid -join ' '))}
 if(((Get-TaskNames $taskCopies) -join '|') -ne (Split-Path -Leaf $taskNext)){throw ('After the next update the copies are: '+((Get-TaskNames $taskCopies) -join ', '))}
 $taskRefs=@((Invoke-TaskGit $taskWorkspace @('for-each-ref','--format=%(refname)','refs/godspeed/')) -split "`n"|Where-Object {$_})
 if(($taskRefs -join '|') -ne ('refs/godspeed/update-copies/'+(Split-Path -Leaf $taskNext))){throw ('After the next update the refs are: '+($taskRefs -join ', '))}
 Write-Output 'After the next update only its own copy and its ref are left.'
} finally {
 Remove-Item Env:GODSPEED_WORKSPACE,Env:GODSPEED_MEDIA_ROOT -ErrorAction SilentlyContinue
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
# And the copy it makes is the copy of what an update can change.
$taskBackupCall=@($taskSetup|Select-String -Pattern '^\s*[^#\s].*godspeed\.mjs''\),''backup'',\$backup,''--before-update''\)')
if($taskBackupCall.Count -ne 1){throw 'The setup does not ask for the copy of what an update can change'}
Write-Output 'The setup asks for the copy of what an update can change.'
