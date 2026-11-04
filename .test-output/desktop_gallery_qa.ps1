param([string]$Step = 'start')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class GalleryQA {
 public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
 [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int count);
 public static IntPtr FindWindowForProcess(int processId) {
  IntPtr result = IntPtr.Zero;
  EnumWindows((window, parameter) => {
   uint owner; GetWindowThreadProcessId(window, out owner);
   var name = new System.Text.StringBuilder(256); GetClassName(window, name, 256);
   if (owner == processId && name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") { result=window; return false; }
   return true;
  }, IntPtr.Zero);
  return result;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w, out Rect r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr w, ref Point p);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr w, int mode);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr w, uint m, IntPtr a, IntPtr b);
}
'@
$qaRoot = 'O:\Da-Downloader\.test-output'
$stateFile = Join-Path $qaRoot 'desktop-gallery-state.json'
if ($Step -eq 'start') {
 $app = Start-Process -FilePath 'O:\Da-Downloader\wallpaper\build\windows\x64\runner\Release\wallpaper.exe' -WorkingDirectory 'O:\Da-Downloader' -WindowStyle Hidden -PassThru
 for ($i=0; $i -lt 50; $i++) {
  Start-Sleep -Milliseconds 200
  $app.Refresh()
  if ([GalleryQA]::FindWindowForProcess($app.Id) -ne [IntPtr]::Zero) { break }
 }
 @{ pid = $app.Id; handle = $app.MainWindowHandle.ToInt64() } | ConvertTo-Json | Set-Content -LiteralPath $stateFile
 Start-Sleep -Seconds 3
} else {
 $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
 $app = Get-Process -Id $saved.pid
}
$window = [GalleryQA]::FindWindowForProcess($app.Id)
if ($window -eq 0) { throw 'No app window' }
[void][GalleryQA]::ShowWindow($window, 9)
[void][GalleryQA]::SetForegroundWindow($window)
$bounds = New-Object GalleryQA+Rect
[void][GalleryQA]::GetClientRect($window, [ref]$bounds)
$scale = [GalleryQA]::GetDpiForWindow($window) / 96.0
$logicalWidth = $bounds.Right / $scale
$logicalHeight = $bounds.Bottom / $scale
function Click-Gallery([double]$x, [double]$y) {
 $point = New-Object GalleryQA+Point
 $point.X = [int]($x*$scale)
 $point.Y = [int]($y*$scale)
 [void][GalleryQA]::ClientToScreen($window, [ref]$point)
 [void][GalleryQA]::SetCursorPos($point.X, $point.Y)
 [GalleryQA]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
 [GalleryQA]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}
switch ($Step) {
 'multi' { Click-Gallery ($logicalWidth - 302) 46 }
 'second' { Click-Gallery 560 170 }
 'all' { Click-Gallery ($logicalWidth - 302) 46 }
 'hideSelected' { Click-Gallery ($logicalWidth - 214) 46 }
 'preview' { Click-Gallery 320 170; Start-Sleep -Milliseconds 75; Click-Gallery 320 170 }
 'return' { Click-Gallery 40 40 }
 'hide' { Click-Gallery ($logicalWidth - 162) ($logicalHeight - 40) }
 'hidden' { Click-Gallery ($logicalWidth - 258) 46 }
 'select' { Click-Gallery 320 170 }
 'restore' { Click-Gallery ($logicalWidth - 214) 46 }
 'home' { Click-Gallery ($logicalWidth - 258) 46 }
 'close' { [void][GalleryQA]::SendMessage($window, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); exit }
}
Start-Sleep -Milliseconds 800
$origin = New-Object GalleryQA+Point
[void][GalleryQA]::ClientToScreen($window, [ref]$origin)
$bitmap = New-Object System.Drawing.Bitmap($bounds.Right, $bounds.Bottom)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bitmap.Size)
$outputFile = Join-Path $qaRoot "desktop-gallery-$Step.png"
$bitmap.Save($outputFile, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
@{ screenshot = $outputFile; width = $bounds.Right; height = $bounds.Bottom; scale = $scale; pid = $app.Id } | ConvertTo-Json
