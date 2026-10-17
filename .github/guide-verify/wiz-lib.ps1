# Window helpers shared by wizard.ps1 and silent-watch.ps1: find the setup's wizard and its
# message boxes, read every text on them, picture them, and press their buttons. Dot-source it
# after setting $Evidence. Based on test-finish-page.ps1 (16 October 2026).
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Wiz {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Text(IntPtr h) { var s = new StringBuilder(16384); IntPtr r; SendMessageTimeout(h, 0x000D, (IntPtr)16384, s, 2, 3000, out r); return s.ToString(); }
  public static void SetText(IntPtr h, string t) { SendMessage(h, 0x000C, IntPtr.Zero, t); }
  public static List<IntPtr> Tops() { var l = new List<IntPtr>(); EnumWindows((h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static List<IntPtr> Kids(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  // A wizard button: BN_CLICKED to its parent, posted so the wizard's own work never blocks this script.
  public static void Click(IntPtr b) { PostMessage(GetParent(b), 0x0111, IntPtr.Zero, b); }
  // A message box button: BM_CLICK.
  public static void Press(IntPtr b) { PostMessage(b, 0x00F5, IntPtr.Zero, IntPtr.Zero); }
  // A click inside a control at client point (x, y), as posted mouse messages.
  public static void PostClick(IntPtr h, int x, int y) { IntPtr p = (IntPtr)((y << 16) | (x & 0xFFFF)); PostMessage(h, 0x0201, (IntPtr)1, p); PostMessage(h, 0x0202, IntPtr.Zero, p); }
  // The same with the real mouse, on the screen.
  public static void RealClick(IntPtr h, int x, int y) { RECT r; GetWindowRect(h, out r); SetCursorPos(r.Left + x, r.Top + y); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
  // The space bar on a list's first item (LB_SETCURSEL 0, then WM_KEYDOWN/WM_KEYUP VK_SPACE).
  public static void Space(IntPtr h) { SendMessage(h, 0x0186, IntPtr.Zero, IntPtr.Zero); PostMessage(h, 0x0100, (IntPtr)0x20, (IntPtr)0x00390001); PostMessage(h, 0x0101, (IntPtr)0x20, unchecked((IntPtr)(int)0xC0390001)); }
}
'@

function Wizard {
  foreach ($h in [Wiz]::Tops()) { if ([Wiz]::IsWindowVisible($h) -and [Wiz]::Cls($h) -eq 'TWizardForm') { return $h } }
  return [IntPtr]::Zero
}
function Dialogs { foreach ($h in [Wiz]::Tops()) { if ([Wiz]::IsWindowVisible($h) -and [Wiz]::Cls($h) -eq '#32770' -and [Wiz]::Text($h) -match 'Setup|Godspeed|Uninstall') { $h } } }
function Controls($w) { foreach ($k in [Wiz]::Kids($w)) { if ([Wiz]::IsWindowVisible($k)) { $t = [Wiz]::Text($k); [pscustomobject]@{ H = $k; Class = [Wiz]::Cls($k); Text = $t; Name = ($t -replace '&', '' -replace '[<>]', '').Trim(); Enabled = [Wiz]::IsWindowEnabled($k) } } } }
function Picture($w, $file) {
  try {
    $r = New-Object Wiz+RECT; [void][Wiz]::GetWindowRect($w, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap ([Math]::Max(1, $r.Right - $r.Left)), ([Math]::Max(1, $r.Bottom - $r.Top))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    try { [void][Wiz]::PrintWindow($w, $hdc, 2) } finally { $g.ReleaseHdc($hdc); $g.Dispose() }
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "  picture: $(Split-Path -Leaf $file)"
  } catch { "  no picture ($file): $_" }
}
$script:n = 0
function Dump($w, $what) {
  $script:n++
  $c = @(Controls $w)
  $lines = $c | Where-Object { $_.Text -or $_.Class -match 'CheckListBox|Edit|Memo' } | ForEach-Object { "  [$($_.Class)$(if (-not $_.Enabled) { ', off' })] $($_.Text)" }
  "---- $what (#$script:n) ----"; $lines
  $lines | Set-Content (Join-Path $Evidence ('{0:d2}-{1}.txt' -f $script:n, ($what -replace '[^A-Za-z0-9]+', '-'))) -Encoding utf8
  Picture $w (Join-Path $Evidence ('{0:d2}-{1}.png' -f $script:n, ($what -replace '[^A-Za-z0-9]+', '-')))
}
# A message box: read it, picture it, answer it. Returns its words.
function Answer-Dialog($d, [string[]]$prefer) {
  $c = @(Controls $d)
  $words = ($c | Where-Object { $_.Class -eq 'Static' -and $_.Text } | ForEach-Object Text) -join ' | '
  $title = [Wiz]::Text($d)
  Dump $d "message box $title" | Out-Host
  foreach ($want in $prefer) {
    $b = $c | Where-Object { $_.Class -eq 'Button' -and $_.Name -eq $want } | Select-Object -First 1
    if ($b) { "  answered: $want" | Out-Host; [Wiz]::Press($b.H); Start-Sleep 2; return "$title :: $words" }
  }
  "  no button of: $($prefer -join ', ')" | Out-Host
  return "$title :: $words"
}
function Heading($c) {
  $known = 'You already have a mission control', 'Where your mission control goes', 'Your conversations', 'Your browser', 'Ready to Install', 'Preparing to Install', 'Installing', 'Information', 'Welcome'
  foreach ($k in $known) { if ($c | Where-Object { $_.Text -like "$k*" -and $_.Class -eq 'TNewStaticText' }) { return $k } }
  $first = $c | Where-Object { $_.Class -eq 'TNewStaticText' -and $_.Text } | Select-Object -First 1
  if ($first) { return $first.Text.Split("`n")[0].Trim() } else { return '(no heading)' }
}
function Close-Setup($p) {
  if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -match '\\is-[^\\]+\.tmp\\' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

