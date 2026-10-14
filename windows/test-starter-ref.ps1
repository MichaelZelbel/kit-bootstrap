$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\join.ps1') -AsLibrary
$fixture = Join-Path $env:TEMP ('godspeed-starter-ref-' + [guid]::NewGuid().ToString('N'))
$oldRef = $env:GODSPEED_STARTER_REF
function Assert-Starter($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $repo = Join-Path $fixture 'source'
    $recipe = Join-Path $repo 'starter-godspeed\skills\next-action\SKILL.md'
    New-Item -ItemType Directory -Force (Split-Path $recipe) | Out-Null
    [IO.File]::WriteAllText($recipe, "release recipe`n")
    $shipped = Join-Path (Split-Path $recipe) '.shipped-sha256'
    [IO.File]::WriteAllText($shipped, ((Get-KitSha256Lf -Path $recipe) + "`n"))
    git -C $repo init --quiet
    git -C $repo config core.autocrlf false
    git -C $repo add .
    git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m release
    $release = (git -C $repo rev-parse HEAD).Trim()
    [IO.File]::WriteAllText($recipe, "later recipe`n")
    [IO.File]::AppendAllText($shipped, ((Get-KitSha256Lf -Path $recipe) + "`n"))
    git -C $repo add .
    git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m later
    $url = ([uri]$repo).AbsoluteUri
    $env:GODSPEED_STARTER_REF = $null
    $default = Join-Path $fixture 'default'
    Assert-Starter (Copy-KitStarterGodspeed -Path $default -StarterRepo $url) 'Default copy failed'
    Assert-Starter ((Get-Content (Join-Path $default 'skills\next-action\SKILL.md') -Raw).Replace("`r", '') -eq "later recipe`n") 'Default copy changed'
    $env:GODSPEED_STARTER_REF = $release
    $pinned = Join-Path $fixture 'pinned'
    Assert-Starter (Copy-KitStarterGodspeed -Path $pinned -StarterRepo $url) 'Pinned copy failed'
    $mine = Join-Path $pinned 'skills\next-action\SKILL.md'
    Assert-Starter ((Get-Content $mine -Raw).Replace("`r", '') -eq "release recipe`n") 'Pinned starter followed the moving branch'
    [IO.File]::WriteAllText($mine, "my edited recipe`n")
    Assert-Starter (Copy-KitStarterGodspeed -Path $pinned -StarterRepo $url) 'Pinned top-up failed'
    Assert-Starter ((Get-Content $mine -Raw).Replace("`r", '') -eq "my edited recipe`n") 'An edited recipe was replaced'
    foreach ($bad in 'main', '--help', ('f' * 40)) {
        $env:GODSPEED_STARTER_REF = $bad
        $rejected = Join-Path $fixture 'rejected'
        Assert-Starter (-not (Copy-KitStarterGodspeed -Path $rejected -StarterRepo $url)) 'Invalid or unavailable pin accepted'
        Assert-Starter (-not (Test-Path $rejected)) 'A rejected pin created a starter'
        Assert-Starter ($ErrorActionPreference -eq 'Stop') 'Native Git changed the caller error preference'
    }
    # main has no integrated notebook setup. Its manifest hook and tests live on
    # codex/godspeed-v2-native-integration at 68f6103; keep this generic floor test
    # independent of that product-specific entry point.
    Write-Output 'Default and pinned starters, edited recipes, and rejected pins verified.'
} finally {
    $env:GODSPEED_STARTER_REF = $oldRef
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
