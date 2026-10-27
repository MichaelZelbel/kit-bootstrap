param([int]$WaitSeconds=900,[string]$Report)
# =============================================================================
# kit-bootstrap / windows / open-notebook.ps1
#
# What the Start menu's "Open my notebook" runs, in a hidden window.
#
# Until 26 October 2026 that entry was the notebook's address and nothing else, so it worked only
# while the notebook was already running. On one laptop the computer started at 12:59 and the
# notebook (started by the Startup entry) answered at 13:07; for those eight minutes the entry
# showed "This site can't be reached". It was also an Internet shortcut, which Windows' Start
# search does not offer: typing "Open my notebook" found only a web search. Now it is a shortcut
# to this script, which Start search offers as an app, and:
#
#   running         the notebook opens in the browser at once, and nothing is started
#   starting        the start under way is waited for, never a second one; a short note says so
#   stopped         it is started (start-full-alpha.ps1), waited for, then opened
#   cannot start    a plain message says so and what to do; nothing is left half open
#
# A second click while the first still waits says the notebook is starting and opens nothing, so
# the browser gets one tab. The entry keeps its name, "Open my notebook": the book and the setup's
# last page name it.
#
#   -Report <file>  for the tests: what would be shown or opened is written to this file instead.
# =============================================================================
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$title='Godspeed Mission Control'
$guide='https://godspeedmissioncontrol.com/guide/troubleshooting-install#the-notebook-did-not-start'

# Icons of the Windows message: 16 stop, 48 warning, 64 information. 4096 keeps it in front, as
# this window is hidden and the click that started it may be minutes ago. -Guide asks whether to
# open the guide's page about it (4: Yes and No buttons; 6 is Yes), so nobody types an address.
function Show-Words([string]$Text,[int]$Icon,[switch]$Wait,[switch]$Guide){
  if($Guide){$Text+="`n`nOpen the guide's page about this?"}
  if($Report){Add-Content -LiteralPath $Report -Value ('said: '+$Text.Replace("`n",' '));return}
  if($Wait){
    $buttons=if($Guide){4}else{0}
    $pressed=(New-Object -ComObject WScript.Shell).Popup($Text,0,$title,$Icon+$buttons+4096)
    if($Guide -and $pressed -eq 6){Start-Process $guide}
    return
  }
  # A note that must not hold up the wait: its own hidden window, gone after half a minute, or
  # sooner when the wait is over (Close-Note), so it never stands in front of the notebook.
  $command='[void](New-Object -ComObject WScript.Shell).Popup('''+$Text.Replace("'","''")+''',30,'''+$title+''','+($Icon+4096)+')'
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $script:note=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
}
function Close-Note{try{if($script:note -and -not $script:note.HasExited){Stop-Process -Id $script:note.Id -Force}}catch{}}
function Open-Address([string]$Address){
  if($Report){Add-Content -LiteralPath $Report -Value ('opened: '+$Address);return}
  Start-Process $Address
}
$starting='Your notebook is starting. It opens in your browser by itself when it is ready. The first start after the computer starts can take a few minutes.'

$configFile=Join-Path $state 'installation.json'
if(-not(Test-Path -LiteralPath $configFile)){
  Show-Words ('Your notebook is not set up on this PC. Run GodspeedSetup.exe again. Your notes are unchanged.') 48 -Wait
  exit 1
}
try{$config=Get-Content -LiteralPath $configFile -Raw|ConvertFrom-Json}catch{
  Show-Words ('The record of your notebook on this PC cannot be read. Run GodspeedSetup.exe again. Your notes are unchanged.') 48 -Wait
  exit 1
}
$address='http://127.0.0.1:'+$config.port+'/'

# One click waits at a time. The name is this PC user's own and this installation's.
$sha=[Security.Cryptography.SHA256]::Create()
$name='Local\GodspeedMissionControlOpenNotebook-'+([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($state.ToLowerInvariant()))).Replace('-','').Substring(0,24))
$waiting=New-Object Threading.Mutex($false,$name)
$owned=$false
try{$owned=$waiting.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
if(-not $owned){
  Show-Words $starting 64
  $waiting.Dispose()
  exit 0
}

$failed=$null;$answered=$false
try{
  # Answering already: opened at once. Not answering: the note first, since the wait can be minutes.
  $up=$false
  try{$health=Invoke-RestMethod -Uri ($address+'health') -TimeoutSec 2;$up=[bool]$health.ok}catch{}
  if(-not $up){Show-Words $starting 64}
  $answered=(@(& (Join-Path $PSScriptRoot 'start-full-alpha.ps1') -NoBrowser -PassThru -WaitSeconds $WaitSeconds 6>$null)|Select-Object -Last 1) -eq $true
}catch{
  # The script's own sentences are plain already (a throw of words has them as its id); anything
  # else Windows said is kept, after a plain first line.
  $why=$_.Exception.Message
  if($_.FullyQualifiedErrorId -eq $why){$failed=$why}else{$failed='Your notebook did not start. Your notes are unchanged. ('+$why+')'}
}finally{
  $waiting.ReleaseMutex();$waiting.Dispose()
  Close-Note
}
if($failed){
  Show-Words ($failed+"`n`nRestart the computer, then choose Open my notebook again.") 16 -Wait -Guide
  exit 1
}
if(-not $answered){
  Show-Words "Your notebook is still starting and does not answer yet. Your notes are unchanged.`n`nChoose Open my notebook again in a few minutes. If it does not open then, restart the computer." 48 -Wait -Guide
  exit 0
}
Open-Address $address
exit 0
