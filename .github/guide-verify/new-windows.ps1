<#
  Pictures every visible top-level window that appears while it watches (for the guide's first
  setup on Windows: Settings, "Open the Windows assistant" opens the Hermes app outside the
  browser). Run it in the background before the click, with -Seconds long enough for the app's
  first start. It also saves a picture of the whole screen at the end.

    ./.github/guide-verify/new-windows.ps1 -Evidence evidence -Seconds 240
#>
param([string]$Evidence = 'evidence', [int]$Seconds = 240)
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
. (Join-Path $PSScriptRoot 'wiz-lib.ps1')
Add-Type -AssemblyName System.Windows.Forms

$known = @{}
foreach ($h in [Wiz]::Tops()) { $known["$h"] = 1 }
$until = (Get-Date).AddSeconds($Seconds); $k = 0
while ((Get-Date) -lt $until) {
  Start-Sleep -Seconds 5
  foreach ($h in [Wiz]::Tops()) {
    if ($known["$h"] -or -not [Wiz]::IsWindowVisible($h)) { continue }
    $title = [Wiz]::Text($h); $cls = [Wiz]::Cls($h)
    $r = New-Object Wiz+RECT; [void][Wiz]::GetWindowRect($h, [ref]$r)
    if (($r.Right - $r.Left) -lt 200 -or ($r.Bottom - $r.Top) -lt 150) { continue }
    $known["$h"] = 1; $k++
    $procId = 0; try { $procId = (Get-Process | Where-Object { $_.MainWindowHandle -eq $h } | Select-Object -First 1).Id } catch {}
    $name = if ($procId) { (Get-Process -Id $procId).ProcessName } else { '?' }
    "new window #${k}: title '$title', class $cls, process $name, $($r.Right - $r.Left)x$($r.Bottom - $r.Top)"
    Start-Sleep -Seconds 20   # let it draw its first page
    Picture $h (Join-Path $Evidence ('window-{0:d2}-{1}.png' -f $k, ($title -replace '[^A-Za-z0-9]+', '-')))
  }
}
try {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
  $bmp.Save((Join-Path $Evidence 'screen-after.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  '  picture: screen-after.png'
} catch { "  no screen picture: $_" }
'Hermes-like processes now:'
Get-Process | Where-Object { $_.ProcessName -match 'hermes|electron' } | ForEach-Object { "  $($_.ProcessName) $($_.Id) '$($_.MainWindowTitle)'" }
