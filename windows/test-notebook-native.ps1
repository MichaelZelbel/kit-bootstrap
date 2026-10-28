$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-notebook-node.ps1')
# Until 6 October 2026 a first install ended at "git remote get-url origin": a new mission control has
# no remote, and Windows PowerShell 5.1 turns git's complaint into a terminating error under Stop.
$taskFixture=Join-Path $env:TEMP ('Godspeed-native-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskFixture|Out-Null
try {
 $taskInit=Invoke-NotebookNative -Command git -Arguments @('-C',$taskFixture,'init','-q')
 if($taskInit.Code -ne 0){throw 'git init failed in the fixture'}
 $taskOrigin=Invoke-NotebookNative -Command git -Arguments @('-C',$taskFixture,'remote','get-url','origin')
 if($taskOrigin.Code -eq 0 -or $taskOrigin.Output){throw 'A repository without a remote read as having one'}
 if($ErrorActionPreference -ne 'Stop'){throw 'The caller''s error preference was not restored'}
 $null=Invoke-NotebookNative -Command git -Arguments @('-C',$taskFixture,'remote','add','origin','https://example.invalid/fixture.git')
 $taskOrigin=Invoke-NotebookNative -Command git -Arguments @('-C',$taskFixture,'remote','get-url','origin')
 if($taskOrigin.Code -ne 0 -or $taskOrigin.Output -ne 'https://example.invalid/fixture.git'){throw 'A configured remote was not read back'}
 if((Invoke-NotebookNative -Command 'godspeed-no-such-program').Code -ne 127){throw 'A missing program read as success'}
 Write-Output 'A missing remote, a configured remote and a missing program each read back as they are.'
} finally {
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $taskFixture -Recurse -Force
 }
}
# The same mistake must not come back in another script: a native command whose stderr is redirected
# runs only inside the two helpers, which lower the error preference first.
# The notebook's scripts: they were all named ...-full-alpha.ps1 until 2.0.0-beta.11.
$taskScripts=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*-notebook*.ps1')+@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1'|Where-Object {$_.Name -in 'ensure-hermes.ps1','open-hermes.ps1','computer-helper.ps1','build-godspeed-setup.ps1','test-full-alpha.ps1'})
if($taskScripts.Count -lt 12){throw ('Only '+$taskScripts.Count+' of the notebook''s scripts were found to look at')}
$taskOffenders=foreach($taskScript in $taskScripts){
 if($taskScript.Name -in 'invoke-notebook-node.ps1','test-notebook-native.ps1'){continue}
 Select-String -LiteralPath $taskScript.FullName -Pattern '^\s*[^#].*&\s*(git|\$node|node)\b.*2>(\$null|&1)'|ForEach-Object {$taskScript.Name+':'+$_.LineNumber}
}
if($taskOffenders){throw ('A native command redirects its errors under Stop: '+($taskOffenders -join ', '))}
Write-Output 'No script of the notebook redirects a native command''s errors outside the helpers.'
