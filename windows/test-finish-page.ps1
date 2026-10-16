<#
  The last page of GodspeedSetup.exe, read the way a reader sees it (16 October 2026).

  The release checks run the setup with /VERYSILENT, and a silent setup never shows its last
  page, so nothing had ever looked at what that page says. This runs the setup with its wizard
  on screen, clicks Next on every page the way a reader who changes nothing does, waits through
  the installation, and on the finish page reads every text the wizard shows, saves a picture
  of the page, and checks the three lines: where the mission control is, how to start talking to
  it, and the newsletter. The label must be tall enough for all of its words (measured with the
  label's own font, as Setup itself measures), and the box under it must not cover it.

  KB_UNATTENDED=1 only stops the setup's console window from asking its own questions (nobody
  is there to answer them on a test machine); the wizard and its pages are unchanged by it.

    ./windows/test-finish-page.ps1 -Setup .\GodspeedSetup.exe -Evidence evidence
#>
param(
  [Parameter(Mandatory)][string]$Setup,
  [string]$Evidence = 'evidence',
  [int]$TimeoutMinutes = 80
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Wiz {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int DrawText(IntPtr dc, string s, int n, ref RECT r, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Text(IntPtr h) { var s = new StringBuilder(16384); IntPtr r; SendMessageTimeout(h, 0x000D, (IntPtr)16384, s, 2, 3000, out r); return s.ToString(); }
  public static List<IntPtr> Tops() { var l = new List<IntPtr>(); EnumWindows((h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static List<IntPtr> Kids(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  // A click on a button: BN_CLICKED to its parent, posted so the wizard's own work never blocks this script.
  public static void Click(IntPtr b) { PostMessage(GetParent(b), 0x0111, IntPtr.Zero, b); }
  // The height a label's words need at its width, in its own font: DrawText with DT_CALCRECT and
  // DT_WORDBREAK, which is how Setup fits a label. -1 when the label names no font.
  public static int Needed(IntPtr label, string text) {
    IntPtr font = SendMessage(label, 0x0031, IntPtr.Zero, IntPtr.Zero);
    if (font == IntPtr.Zero) return -1;
    RECT c; GetClientRect(label, out c);
    IntPtr dc = GetDC(label); IntPtr old = SelectObject(dc, font);
    RECT r = new RECT(); r.Right = c.Right - c.Left;
    DrawText(dc, text, -1, ref r, 0x0400 | 0x0010 | 0x0800);
    SelectObject(dc, old); ReleaseDC(label, dc);
    return r.Bottom - r.Top;
  }
}
'@

function Wizard {
  foreach ($h in [Wiz]::Tops()) {
    if ([Wiz]::IsWindowVisible($h) -and ([Wiz]::Cls($h) -eq 'TWizardForm' -or [Wiz]::Text($h) -like 'Setup - Godspeed*')) { return $h }
  }
  return [IntPtr]::Zero
}
function Dialogs { foreach ($h in [Wiz]::Tops()) { if ([Wiz]::IsWindowVisible($h) -and [Wiz]::Cls($h) -eq '#32770' -and [Wiz]::Text($h) -match 'Setup|Godspeed') { $h } } }
function Controls($w) { foreach ($k in [Wiz]::Kids($w)) { if ([Wiz]::IsWindowVisible($k)) { $t = [Wiz]::Text($k); [pscustomobject]@{ H = $k; Class = [Wiz]::Cls($k); Text = $t; Name = ($t -replace '&', '' -replace '[<>]', '').Trim(); Enabled = [Wiz]::IsWindowEnabled($k) } } } }
# A setup still running when this ends (a check that failed part way) is closed, so the next
# step starts on a clean desktop and no leftover window keeps this step's output open.
function Close-Setup($p) {
  if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -match '\\is-[^\\]+\.tmp\\' } | Stop-Process -Force -ErrorAction SilentlyContinue
}
function Picture($w, $file) {
  try {
    $r = New-Object Wiz+RECT; [void][Wiz]::GetWindowRect($w, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap ([Math]::Max(1, $r.Right - $r.Left)), ([Math]::Max(1, $r.Bottom - $r.Top))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    try { [void][Wiz]::PrintWindow($w, $hdc, 2) } finally { $g.ReleaseHdc($hdc); $g.Dispose() }
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "picture: $file"
  } catch { "no picture ($file): $_" }
}

$env:KB_UNATTENDED = '1'
# A reader starts the setup from Explorer; from PowerShell 7 its Windows PowerShell 5.1 would
# inherit PowerShell 7's module path and lose Get-FileHash (as in release-windows.yml).
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$log = Join-Path $Evidence 'finish-page-setup.log'
$p = Start-Process (Resolve-Path $Setup).Path -ArgumentList "/LOG=`"$log`"" -PassThru
"setup started (process $($p.Id)), with its wizard on screen"
try {
$deadline = (Get-Date).AddMinutes($TimeoutMinutes); $last = ''; $finish = $null; $n = 0
$clicked = ''; $clickedAt = Get-Date; $tries = @{}
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  foreach ($d in Dialogs) {
    $words = (Controls $d | Where-Object Text | ForEach-Object Text) -join ' | '
    Picture $d (Join-Path $Evidence "message-box-$n.png"); $n++
    throw "the setup showed a message box: $words"
  }
  $w = Wizard
  if ($w -eq [IntPtr]::Zero) { if ($p.HasExited) { throw "the setup ended (exit $($p.ExitCode)) before its last page" }; continue }
  $c = @(Controls $w)
  $buttons = @($c | Where-Object { $_.Class -eq 'TNewButton' })
  $page = (@($c | Where-Object { $_.Class -eq 'TNewStaticText' -and $_.Text }) | Select-Object -First 2 | ForEach-Object Text) -join ' / '
  if ($page -ne $last) { "page: $page   [buttons: $(($buttons | ForEach-Object { $_.Text + $(if ($_.Enabled) { '' } else { ' (off)' }) }) -join ', ')]"; $last = $page }
  if ($buttons | Where-Object { $_.Name -eq 'Finish' -and $_.Enabled }) {
    Start-Sleep -Seconds 2; $finish = @(Controls $w); Picture $w (Join-Path $Evidence 'finish-page.png'); break
  }
  $next = $buttons | Where-Object { ($_.Name -eq 'Next' -or $_.Name -eq 'Install') -and $_.Enabled } | Select-Object -First 1
  if (-not $next) { continue }
  $sig = "$page|$($next.Text)"
  # One click per page: the next only when the page has not moved on for a minute, so a click
  # still waiting in the queue can never land on a later page (the Finish button above all).
  if ($sig -eq $clicked -and ((Get-Date) - $clickedAt).TotalSeconds -lt 60) { continue }
  $tries[$sig] = 1 + [int]$tries[$sig]
  if ($tries[$sig] -gt 3) { Picture $w (Join-Path $Evidence 'stuck.png'); throw "the wizard does not move on from: $page" }
  "click: $($next.Text)"
  [void][Wiz]::SetForegroundWindow($w); [Wiz]::Click($next.H); $clicked = $sig; $clickedAt = Get-Date
}
if (-not $finish) { $w = Wizard; if ($w -ne [IntPtr]::Zero) { Picture $w (Join-Path $Evidence 'timeout.png') }; throw "no finish page after $TimeoutMinutes minutes" }

$texts = $finish | Where-Object Text | ForEach-Object { "[$($_.Class)] $($_.Text)" }
$texts | Set-Content (Join-Path $Evidence 'finish-page.txt') -Encoding utf8
'--- every text on the finish page ---'; $texts; '-------------------------------------'
$label = $finish | Where-Object { $_.Class -eq 'TNewStaticText' -and $_.Text -clike 'Your mission control *' } | Select-Object -First 1
$fail = 0
function Want($what, [bool]$ok) { if ($ok) { "ok    $what" } else { "FAIL  $what"; $script:fail++ } }
$mc = Join-Path $HOME 'godspeed-v2'
Want 'the page does not say the setup failed' (-not ($finish | Where-Object { $_.Text -eq 'Setup did not finish' }))
Want "it says where the mission control is ($mc)" ([bool]$label -and $label.Text.Contains("Your mission control is in $mc."))
Want 'it says how to start talking to it' ([bool]$label -and $label.Text.Contains('To talk to it, open your notebook: Start menu, Open my notebook. The first time, connect your own AI account in Settings.'))
Want 'it ends with the newsletter line' ([bool]$label -and $label.Text.TrimEnd().EndsWith('I write about what it does and what broke, free: https://michaelzelbel.substack.com/subscribe'))
Want 'the stock text is gone' (-not ($finish | Where-Object { $_.Text -match 'Setup has finished installing' }))
if ($label) {
  $lr = New-Object Wiz+RECT; [void][Wiz]::GetWindowRect($label.H, [ref]$lr)
  $need = [Wiz]::Needed($label.H, $label.Text)
  "label: $($lr.Right - $lr.Left) x $($lr.Bottom - $lr.Top) pixels; its words need $need"
  if ($need -lt 0) { 'the label names no font, so its height is judged from the picture only' }
  else { Want 'the label is tall enough for all its words' (($lr.Bottom - $lr.Top) -ge $need) }
  $box = $finish | Where-Object { $_.Class -eq 'TNewCheckListBox' } | Select-Object -First 1
  if ($box) {
    $br = New-Object Wiz+RECT; [void][Wiz]::GetWindowRect($box.H, [ref]$br)
    Want 'the box below starts under the words, not over them' ($br.Top -ge $lr.Bottom)
  }
}
$fb = $finish | Where-Object { $_.Name -eq 'Finish' } | Select-Object -First 1
if ($fb) { [Wiz]::Click($fb.H) }
if (-not $p.WaitForExit(120000)) { 'the setup did not close after Finish'; $fail++ } else { "setup exit: $($p.ExitCode)" }
} finally { Close-Setup $p }
if ($fail) { "$fail failed"; exit 1 } else { 'ALL PASS' }
