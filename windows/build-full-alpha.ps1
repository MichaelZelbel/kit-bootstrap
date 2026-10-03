param([Parameter(Mandatory)][string]$KitCheckout,[switch]$SkipCompilerInstall)
$ErrorActionPreference='Stop'
$KitCheckout=[IO.Path]::GetFullPath($KitCheckout)
$bootstrapCheckout=Split-Path -Parent $PSScriptRoot
foreach($checkout in @($KitCheckout,$bootstrapCheckout)){
  $dirty=& git -C $checkout status --porcelain --untracked-files=no
  if($LASTEXITCODE -ne 0 -or $dirty){throw 'Candidate builds require committed source in both repositories.'}
}
$kitCommit=(& git -C $KitCheckout rev-parse HEAD).Trim();$bootstrapCommit=(& git -C $bootstrapCheckout rev-parse HEAD).Trim()
$payload=Join-Path $PSScriptRoot 'full-alpha-payload'
New-Item -ItemType Directory -Force -Path $payload|Out-Null
# Version-specific output directory prevents an older build from contaminating a new one.
$payload=Join-Path $payload ($kitCommit.Substring(0,12)+'-'+$bootstrapCommit.Substring(0,12))
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'kit')|Out-Null
$archivePath=Join-Path $payload 'kit-source.zip'
& git -C $KitCheckout archive --format=zip ("--output="+$archivePath) $kitCommit
if($LASTEXITCODE -ne 0){throw 'Kit archive failed.'}
Expand-Archive -LiteralPath (Join-Path $payload 'kit-source.zip') -DestinationPath (Join-Path $payload 'kit') -Force
Remove-Item -LiteralPath (Join-Path $payload 'kit-source.zip')
$ui=Join-Path $KitCheckout 'notebook\ui\dist'
if(-not(Test-Path -LiteralPath (Join-Path $ui 'index.html'))){throw 'Build and verify the notebook UI before packaging.'}
Copy-Item -LiteralPath $ui -Destination (Join-Path $payload 'kit\notebook\ui\dist') -Recurse -Force
$nodeVersion='22.19.0';$filename='node-v'+$nodeVersion+'-win-x64.zip'
$download=Join-Path $payload $filename
$checksums=(Invoke-WebRequest -Uri ('https://nodejs.org/dist/v'+$nodeVersion+'/SHASUMS256.txt') -UseBasicParsing).Content
$checksum=($checksums -split "`n"|Where-Object {$_ -match ('\s'+[regex]::Escape($filename)+'\s*$')}) -split '\s+'|Select-Object -First 1
if(-not $checksum){throw 'Pinned Node checksum was not found.'}
Invoke-WebRequest -Uri ('https://nodejs.org/dist/v'+$nodeVersion+'/'+$filename) -OutFile $download -UseBasicParsing
if((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $checksum){throw 'Node runtime checksum mismatch.'}
Expand-Archive -LiteralPath $download -DestinationPath $payload -Force
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'runtime')|Out-Null
Copy-Item -LiteralPath (Join-Path $payload ('node-v'+$nodeVersion+'-win-x64\node.exe')) -Destination (Join-Path $payload 'runtime\node.exe') -Force
Copy-Item -LiteralPath (Join-Path $payload ('node-v'+$nodeVersion+'-win-x64\LICENSE')) -Destination (Join-Path $payload 'runtime\NODE-LICENSE') -Force
$unpacked=[IO.Path]::GetFullPath((Join-Path $payload ('node-v'+$nodeVersion+'-win-x64')))
if(-not $unpacked.StartsWith($payload+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe staging directory.'}
Remove-Item -LiteralPath $unpacked -Recurse -Force
Remove-Item -LiteralPath $download
$files=@(Get-ChildItem -LiteralPath (Join-Path $payload 'kit'),(Join-Path $payload 'runtime') -Recurse -File|ForEach-Object {[pscustomobject]@{path=$_.FullName.Substring($payload.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$manifest=[pscustomobject]@{channel='full-alpha';version='2.0.0-alpha.1';kitCommit=$kitCommit;bootstrapCommit=$bootstrapCommit;nodeVersion=$nodeVersion;nodeArchiveSha256=$checksum;dataFormat=1;files=$files}
$manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $payload 'candidate-manifest.json') -Encoding UTF8
$compiler=Get-Command iscc -ErrorAction SilentlyContinue
if($compiler){$iscc=$compiler.Source}else{$iscc=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'}
if(-not(Test-Path -LiteralPath $iscc)){$iscc=Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'}
if(-not(Test-Path -LiteralPath $iscc)){throw 'Inno Setup compiler is required.'}
Push-Location $PSScriptRoot
try{& $iscc /Qp ("/DPayloadRoot="+$payload) '/DCandidateVersion=2.0.0-alpha.1' 'full-alpha.iss';if($LASTEXITCODE -ne 0){throw 'Full alpha compilation failed.'}}finally{Pop-Location}
$exe=Join-Path $PSScriptRoot 'dist\GodspeedSetup-Full-Alpha.exe'
Get-FileHash -LiteralPath $exe -Algorithm SHA256|Format-List
Copy-Item -LiteralPath (Join-Path $payload 'candidate-manifest.json') -Destination (Join-Path $PSScriptRoot 'dist\candidate-manifest.json') -Force
