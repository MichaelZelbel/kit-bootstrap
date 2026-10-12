# tracker-checks.ps1 -Mode fresh|upgrade
#
# The trackers a Windows reader has after GodspeedSetup.exe (D-321, the release after 12 October
# 2026's first one): "track belly 92 cm" asks once and then keeps the number, the cycle tracker,
# the headache tracker and the food tracker with its food table (the BLS 4.0; the Windows setup
# does not fetch it itself, the notebook fetches it once a minute after it starts, checked against
# its pinned checksum), and the recipes that take every message starting with "track". Everything
# goes through the notebook's own MCP door at 127.0.0.1, the way the reader's assistant reaches it;
# no model is needed, because the replies are worked out in code and relayed word for word.
# The same checks as the clean-install test's tracker-checks.sh. Exits 1 when anything fails.
param([ValidateSet('fresh','upgrade')][string]$Mode='fresh', [string]$Mc = (Join-Path $HOME 'godspeed-v2'), [string]$Base = 'http://127.0.0.1:47831')
$ErrorActionPreference = 'Continue'
$mc = $Mc
$base = $Base
$food = Join-Path $mc '.godspeed\food\bls-4.0'
$script:fail = 0
function Want($what, [scriptblock]$test) {
  $ok = $false; try { $ok = [bool](& $test) } catch { Write-Host "   $_" }
  if ($ok) { Write-Host "ok    $what" } else { Write-Host "FAIL  $what"; $script:fail++ }
}
# One call of the notebook's personal_operation tool: the object it answered, or one with .error.
function Op($arguments) {
  $body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'personal_operation'; arguments = $arguments } } | ConvertTo-Json -Depth 8 -Compress
  try {
    $r = Invoke-RestMethod "$base/mcp" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
    $text = $r.result.content[0].text
    if ($r.result.isError) { return [pscustomobject]@{ error = $text; reply = '' } }
    return ($text | ConvertFrom-Json)
  } catch { return [pscustomobject]@{ error = "$_"; reply = '' } }
}
function Show($said, $answer) { $line = "   ${said}: " + $(if ($answer.error) { 'ERROR: ' + $answer.error } else { $answer.reply }); Write-Host ($line.Substring(0, [Math]::Min(300, $line.Length))) }

Write-Host '== The recipes that take "track"'
foreach ($s in 'tracker','cycle-tracker','food-tracker','headache-tracker','coach') {
  Want "the $s recipe is in the mission control" { Test-Path (Join-Path $mc "skills\$s\SKILL.md") }
}
Want 'the tracker recipe takes every message that starts with "track"' { (Get-Content (Join-Path $mc 'skills\tracker\SKILL.md') -Raw).Contains('Use for every message that starts with "track"') }
Want 'the food tracker recipe is the one that uses the food table' { (Get-Content (Join-Path $mc 'skills\food-tracker\SKILL.md') -Raw) -match '(?i)food table' }

Write-Host '== "track belly 92 cm" (Chapter 14)'
$held = Op @{ type = 'tracker-hold'; name = 'Belly'; unit = 'cm'; value = 92; words = 'track belly 92 cm' }; Show 'track belly 92 cm' $held
Want 'an unknown name asks once before a tracker exists ("Start a new tracker called Belly?")' { "$($held.reply)".StartsWith('Start a new tracker called Belly') }
$made = Op @{ type = 'tracker-create'; proposal_id = $held.proposal_id; words = 'yes' }; Show 'yes' $made
Want 'the yes makes the tracker and keeps the number ("Tracked: Belly 92 cm.")' { "$($made.reply)".StartsWith('Tracked: Belly 92 cm.') }
$list = Op @{ type = 'tracker-list' }
Want 'the Trackers shelf lists Belly' { @($list.trackers | Where-Object { $_.name -eq 'Belly' }).Count -eq 1 }

Write-Host '== The headache tracker'
$h = Op @{ type = 'headache'; action = 'start'; pain = 5; side = 'right'; words = 'track headache, right side, 5 of 10' }; Show 'track headache, right side, 5 of 10' $h
Want 'a headache is tracked ("Tracked: ...")' { "$($h.reply)".StartsWith('Tracked:') }

Write-Host '== The cycle tracker'
$c = Op @{ type = 'cycle'; action = 'track'; words = 'track period' }; Show 'track period' $c
Want '"track period" asks once before a cycle tracker exists' { "$($c.reply)".StartsWith('Start a cycle tracker?') }
$c2 = Op @{ type = 'tracker-create'; proposal_id = $c.proposal_id; words = 'yes' }; Show 'yes' $c2
Want 'the yes starts it ("Tracked: period day 1.")' { "$($c2.reply)".StartsWith('Tracked: period day 1.') }
$f = Op @{ type = 'cycle'; action = 'forecast' }; Show 'when is my next period?' $f
Want 'a forecast carries the fixed line about what it is not for' { "$($f.reply)".Contains('Not for contraception') }

Write-Host '== The food tracker and its food table'
# The notebook fetches the table once a minute after it starts; this waits up to 5 minutes.
$waited = 0
while (-not (Test-Path (Join-Path $food 'foods.json')) -and $waited -lt 300) { Start-Sleep -Seconds 10; $waited += 10 }
Write-Host "   the table was there after $waited seconds of waiting"
Want 'the food table is installed (.godspeed\food\bls-4.0\foods.json)' { (Get-Item (Join-Path $food 'foods.json') -ErrorAction Stop).Length -gt 0 }
Want 'it is the BLS 4.0 with its pinned checksum' { (Get-Content (Join-Path $food 'source.json') -Raw).Contains('12b7a6ba62807ec9b301eb276f897dc85f99b2292311618dec3749a12d984c91') }
Want 'it holds the 7,140 foods' { @((Get-Content (Join-Path $food 'foods.json') -Raw | ConvertFrom-Json).foods).Count -eq 7140 }
Want 'its licence notice names the Max Rubner-Institut and CC BY 4.0' { $n = Get-Content (Join-Path $food 'NOTICE.md') -Raw; $n.Contains('Max Rubner-Institut') -and $n.Contains('CC BY 4.0') }
$s = Op @{ type = 'food'; action = 'search'; queries = @('Haferflocken') }
$oats = "$(@(@($s.results)[0].foods)[0].id)"
Write-Host "   search Haferflocken: $(if ($oats) { $oats } else { 'nothing ' + $s.error })"
Want 'a search finds oat flakes in the table' { $oats -ne '' }
$t = Op @{ type = 'food'; action = 'track'; items = @(@{ food = $oats; item = 'oat flakes'; grams = 50 }); words = 'track breakfast, 50 g oat flakes' }; Show 'track breakfast, 50 g oat flakes' $t
Want '"track breakfast" asks once before a food tracker exists' { "$($t.reply)".StartsWith('Start a food tracker?') }
$t2 = Op @{ type = 'tracker-create'; proposal_id = $t.proposal_id; words = 'yes' }; Show 'yes' $t2
Want 'the yes keeps the meal with its calories from the table ("Tracked: oat flakes 50 g: ... kcal")' { "$($t2.reply)" -match '^Tracked: oat flakes 50 g: [0-9,]+ kcal' }

if ($script:fail) { Write-Host "TRACKERS: $($script:fail) failed"; exit 1 } else { Write-Host 'TRACKERS: ALL PASS' }
