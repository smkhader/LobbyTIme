<#
LobbyTime.ps1
Creates a lobby HTML clock, supports background images, persistent JSON config, and can launch Edge in kiosk/normal mode.
Features:
 - Actions: create | kiosk | normal | install | remove | menu
 - Copies validated PNG/JPG backgrounds into the script folder as background.png or background.jpg
 - Uses kiosk-config.json (next to the script) to persist settings; created automatically on first run (unless -DebugMode is used)
 - Embedded .bat template used for ProgramData Startup installation
 - CLI options override config and are saved unless -DebugMode is provided
#>

param(
  [ValidateSet('create','kiosk','normal','install','remove','menu')]
  [string]$Action = 'menu',

  [string]$ScriptPath = $null,      # If not supplied, resolved to the running script path
  [string]$HtmlPath = $null,        # If not supplied, defaults to same folder as ScriptPath\kiosk.html

  [string]$StartupBatName = "Start-Kiosk.bat",

  [string]$BackgroundImage = $null,    # path to source image (PNG/JPG) - optional

  [string]$TimeFontSize = $null,       # e.g. "9vw" or "120px" - optional
  [string]$DateFontSize = $null,       # e.g. "3vw" - optional
  [string]$FontFamily = $null,         # e.g. "Segoe UI, Roboto, Arial, sans-serif"
  [string]$FontColor = $null,          # hex color e.g. "#FFFFFF"
  [string]$TimeFormat = $null,         # tokens: HH, hh, mm, ss, A, etc.
  [string]$DateFormat = $null,         # tokens: dddd, MMMM, D, YYYY, etc.

  [switch]$DebugMode                      # if set, do not write changes to the config file
)

# -----------------------
# Resolve script/install paths
# -----------------------
if (-not $ScriptPath) {
  # Prefer $PSCommandPath (PowerShell >= 3) else fall back to MyInvocation
  if ($PSCommandPath) { $ScriptPath = $PSCommandPath } else { $ScriptPath = $MyInvocation.MyCommand.Definition }
}
$ScriptFolder = Split-Path -Parent $ScriptPath
if (-not $HtmlPath) { $HtmlPath = Join-Path -Path $ScriptFolder -ChildPath "kiosk.html" }

# -----------------------
# Config helpers
# -----------------------
function Get-ConfigPath { param([string]$ScriptPath) Join-Path -Path (Split-Path -Parent $ScriptPath) -ChildPath "kiosk-config.json" }

function Load-Config {
  param([string]$ConfigPath)
  if (Test-Path $ConfigPath) {
    try {
      $json = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
      return $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
      Write-Warning "Failed to read config; using defaults. ($_)"
    }
  }
  return [PSCustomObject]@{
    BackgroundFileName = ""            # stored file name (background.png or background.jpg) relative to script folder
    TimeFontSize       = "9vw"
    DateFontSize       = "3vw"
    FontFamily         = "Segoe UI, Roboto, Arial, sans-serif"
    FontColor          = "#FFFFFF"
    OverlayOpacity     = 0.18
    TimeFormat         = "HH:mm:ss"
    DateFormat         = "dddd, MMMM D, YYYY"
    TextShadow         = "0 2px 6px rgba(0,0,0,0.6)"
  }
}

function Save-Config {
  param([string]$ConfigPath, [PSObject]$Config)
  try {
    $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8 -Force
    Write-Host "Config saved to: $ConfigPath"
    return $true
  } catch {
    Write-Warning "Failed to save config: $_"
    return $false
  }
}

# -----------------------
# Image validation + copy
# -----------------------
function Test-IsPngOrJpeg {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    $bytes = New-Object byte[] 8
    $read = $fs.Read($bytes, 0, 8)
    $fs.Close()
    if ($read -lt 2) { return $false }
    $pngSig = @([byte]0x89,[byte]0x50,[byte]0x4E,[byte]0x47,[byte]0x0D,[byte]0x0A,[byte]0x1A,[byte]0x0A)
    $isPng = $true
    for ($i=0; $i -lt 8; $i++) { if ($bytes[$i] -ne $pngSig[$i]) { $isPng = $false; break } }
    if ($isPng) { return 'png' }
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { return 'jpg' }
    return $false
  } catch {
    return $false
  }
}

function Copy-BackgroundIfValid {
  param([string]$SourcePath, [string]$DestFolder)
  if ([string]::IsNullOrWhiteSpace($SourcePath)) { return $null }
  if (-not (Test-Path $SourcePath)) { Write-Warning "Background not found: $SourcePath"; return $null }
  $type = Test-IsPngOrJpeg -Path $SourcePath
  if (-not $type) { Write-Warning "Background file is not a valid PNG or JPG."; return $null }
  if (-not (Test-Path $DestFolder)) { New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null }
  $destName = "background.$type"
  $destPath = Join-Path -Path $DestFolder -ChildPath $destName
  try {
    Copy-Item -Path $SourcePath -Destination $destPath -Force
    Write-Host "Copied background to: $destPath"
    return $destName
  } catch {
    Write-Warning "Failed to copy background: $_"
    return $null
  }
}

# -----------------------
# Edge helpers
# -----------------------
function Find-Edge {
  $candidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) "Microsoft\Edge\Application\msedge.exe"),
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  if ($candidates.Count -gt 0) {
    return $candidates[0]
  }

  try {
    $command = Get-Command msedge.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
  } catch {}

  return $null
}

function Start-EdgeKiosk { param([string]$HtmlFile) 
  $edge = Find-Edge
  if (-not $edge) { Write-Error "Microsoft Edge (msedge.exe) not found."; return $false }
  $uri = "file:///" + ($HtmlFile -replace '\\','/')
  $args = @(
    "--profile-directory=Default",
    "--kiosk",
    $uri,
    "--edge-kiosk-type=fullscreen",
    "--no-first-run"
  )
  Write-Host "Starting Edge in kiosk mode..."
  Start-Process -FilePath $edge -ArgumentList $args -WindowStyle Hidden
  return $true
}

function Start-EdgeNormal { param([string]$HtmlFile)
  $edge = Find-Edge
  if (-not $edge) { Write-Error "Microsoft Edge (msedge.exe) not found."; return $false }
  $args = @(
    "--profile-directory=Default",
    "--start-maximized",
    "--no-first-run",
    $HtmlFile
  )
  Write-Host "Starting Edge in normal mode..."
  Start-Process -FilePath $edge -ArgumentList $args
  return $true
}

# -----------------------
# Startup .bat install/remove (embedded template)
# -----------------------
function Install-StartupBat {
  param([string]$ScriptToCall, [string]$HtmlFile, [string]$BatName)
  $startupFolder = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\Windows\Start Menu\Programs\Startup"
  $batPath = Join-Path -Path $startupFolder -ChildPath $BatName

  # Embedded template for the .bat (kept here inside the script)
  $escapedScript = $ScriptToCall -replace '\\','\\'
  $escapedHtml = $HtmlFile -replace '\\','\\'

  $batContent = @"
@echo off
REM This .bat starts the Create-Kiosk.ps1 in kiosk mode.
REM Place in: C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Start-Kiosk.bat
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" -Action ...
"@

  try {
    if (-not (Test-Path $startupFolder)) { throw "Startup folder not found: $startupFolder" }
    $testFile = Join-Path $startupFolder ".__kiosk_test__.tmp"
    try { New-Item -Path $testFile -ItemType File -Force | Out-Null; Remove-Item $testFile -Force } catch { throw "No write permission to $startupFolder. Run as Administrator to install the startup .bat." }
    $batContent | Out-File -FilePath $batPath -Encoding ASCII -Force
    Write-Host "Created startup .bat at: $batPath"
    return $true
  } catch {
    Write-Error "Failed to create startup .bat: $_"
    return $false
  }
}

function Remove-StartupBat { param([string]$BatName)
  $startupFolder = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\Windows\Start Menu\Programs\Startup"
  $batPath = Join-Path -Path $startupFolder -ChildPath $BatName
  if (Test-Path $batPath) {
    try { 
      Remove-Item -Path $batPath -Force
      Write-Host "Removed: $batPath"
      return $true 
    } catch { 
      Write-Error "Failed to remove $($batPath): $_"
      return $false 
    }
  } else {
    Write-Warning "Startup .bat not found: $batPath"; return $false
  }
}

# -----------------------
# HTML generation
# -----------------------
function New-KioskHtml {
  param([string]$Path, [PSObject]$Config)

  $dir = Split-Path -Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

  if ($Config.BackgroundFileName -and $Config.BackgroundFileName -ne "") {
    $bgCss = "background: url('$($Config.BackgroundFileName)') center/cover no-repeat; background-color:#0b1220;"
  } else {
    $bgCss = "background:#0b1220;"
  }

  $fontFamilyCss = $Config.FontFamily -replace '"','\"'

  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Lobby Kiosk</title>
  <style>
    html,body { height:100%; margin:0; }
    body { display:flex; align-items:center; justify-content:center; color:$($Config.FontColor); font-family: $fontFamilyCss; $bgCss }
    .container { text-align:center; width:100%; }
    .time { font-size:$($Config.TimeFontSize); font-weight:600; letter-spacing:2px; text-shadow: $($Config.TextShadow); }
    .date { font-size:$($Config.DateFontSize); margin-top:0.5rem; opacity:0.95; text-shadow: $($Config.TextShadow); }
    .container::before {
      content: "";
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,$($Config.OverlayOpacity));
      pointer-events: none;
      z-index: 0;
    }
    .container > * { position: relative; z-index: 1; }
  </style>
</head>
<body>
  <div class="container">
    <div class="time" id="time">--:--:--</div>
    <div class="date" id="date">Loading date...</div>
  </div>
  <script>
    function pad(n){return n.toString().padStart(2,'0');}
    function monthNames(){ return ['January','February','March','April','May','June','July','August','September','October','November','December']; }
    function monthShortNames(){ return ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']; }
    function weekdayNames(){ return ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']; }
    function weekdayShort(){ return ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']; }

    function formatToken(d, fmt){
      return fmt.replace(/YYYY|YY|MMMM|MMM|MM|M|DD|D|dddd|ddd|HH|hh|mm|ss|A/g, function(token){
        switch(token){
          case 'YYYY': return d.getFullYear();
          case 'YY': return String(d.getFullYear()).slice(-2);
          case 'MMMM': return monthNames()[d.getMonth()];
          case 'MMM': return monthShortNames()[d.getMonth()];
          case 'MM': return pad(d.getMonth()+1);
          case 'M': return d.getMonth()+1;
          case 'DD': return pad(d.getDate());
          case 'D': return d.getDate();
          case 'dddd': return weekdayNames()[d.getDay()];
          case 'ddd': return weekdayShort()[d.getDay()];
          case 'HH': return pad(d.getHours());
          case 'hh': { var h = d.getHours() % 12; if(h===0) h=12; return pad(h); }
          case 'mm': return pad(d.getMinutes());
          case 'ss': return pad(d.getSeconds());
          case 'A': return d.getHours() >= 12 ? 'PM' : 'AM';
          default: return token;
        }
      });
    }

    var timeFmt = "$($Config.TimeFormat)";
    var dateFmt = "$($Config.DateFormat)";

    function update(){
      var d = new Date();
      document.getElementById('time').textContent = formatToken(d, timeFmt);
      document.getElementById('date').textContent = formatToken(d, dateFmt);
    }
    update();
    setInterval(update, 1000);
    document.addEventListener('visibilitychange', function(){ if(!document.hidden) update(); });
  </script>
</body>
</html>
"@

  try {
    $html | Out-File -FilePath $Path -Encoding UTF8 -Force
    Write-Host "HTML written to: $Path"
    return $true
  } catch {
    Write-Error "Failed to write HTML: $_"
    return $false
  }
}

# -----------------------
# Interactive menu
# -----------------------
function Show-Menu {
  param([PSObject]$Config, [string]$ConfigPath)
  $continueMenu = $true
  while ($continueMenu) {
    Clear-Host
    Write-Host "Kiosk helper - choose an action:"
    Write-Host "1) Create HTML only"
    Write-Host "2) Create HTML and launch Edge (Kiosk Fullscreen)"
    Write-Host "3) Create HTML and launch Edge (Normal Window)"
    Write-Host "4) Install autorun .bat to ProgramData Startup (requires admin)"
    Write-Host "5) Remove autorun .bat from ProgramData Startup"
    Write-Host "6) Edit settings"
    Write-Host "7) Exit"
    Write-Host ""
    Write-Host "Current settings (from config):"
    $Config | Format-List
    $choice = Read-Host "Enter choice (1-7)"
    switch ($choice) {
      '1' {
         $inputBg = Read-Host "Path to background image (PNG/JPG) or leave blank to keep current"
         if ($inputBg) {
           $bgFile = Copy-BackgroundIfValid -SourcePath $inputBg -DestFolder $ScriptFolder
           if ($bgFile) { $Config.BackgroundFileName = $bgFile }
         }
         New-KioskHtml -Path $HtmlPath -Config $Config
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '2' {
         $inputBg = Read-Host "Path to background image (PNG/JPG) or leave blank to keep current"
         if ($inputBg) {
           $bgFile = Copy-BackgroundIfValid -SourcePath $inputBg -DestFolder $ScriptFolder
           if ($bgFile) { $Config.BackgroundFileName = $bgFile }
         }
         if (New-KioskHtml -Path $HtmlPath -Config $Config) { Start-EdgeKiosk -HtmlFile $HtmlPath }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '3' {
         $inputBg = Read-Host "Path to background image (PNG/JPG) or leave blank to keep current"
         if ($inputBg) {
           $bgFile = Copy-BackgroundIfValid -SourcePath $inputBg -DestFolder $ScriptFolder
           if ($bgFile) { $Config.BackgroundFileName = $bgFile }
         }
         if (New-KioskHtml -Path $HtmlPath -Config $Config) { Start-EdgeNormal -HtmlFile $HtmlPath }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '4' {
         $inputBg = Read-Host "Path to background image (PNG/JPG) or leave blank to keep current"
         if ($inputBg) {
           $bgFile = Copy-BackgroundIfValid -SourcePath $inputBg -DestFolder $ScriptFolder
           if ($bgFile) { $Config.BackgroundFileName = $bgFile }
         }
         if (New-KioskHtml -Path $HtmlPath -Config $Config) { Install-StartupBat -ScriptToCall $ScriptPath -HtmlFile $HtmlPath -BatName $StartupBatName }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '5' {
         Remove-StartupBat -BatName $StartupBatName
         Read-Host "Press Enter to continue..."
      }
      '6' {
         Write-Host "Leave blank to keep current value."
         $val = Read-Host "Time font size (e.g. 9vw or 120px) [current: $($Config.TimeFontSize)]"
         if ($val -ne '') { $Config.TimeFontSize = $val }
         $val = Read-Host "Date font size (e.g. 3vw) [current: $($Config.DateFontSize)]"
         if ($val -ne '') { $Config.DateFontSize = $val }
         $val = Read-Host "Font family (CSS font-family) [current: $($Config.FontFamily)]"
         if ($val -ne '') { $Config.FontFamily = $val }
         $val = Read-Host "Font color (hex) [current: $($Config.FontColor)]"
         if ($val -ne '') { $Config.FontColor = $val }
         $val = Read-Host "Overlay opacity 0.0-0.9 [current: $($Config.OverlayOpacity)]"
         if ($val -ne '') { [double]$Config.OverlayOpacity = [double]$val }
         $val = Read-Host "Time format tokens (e.g. HH:mm:ss) [current: $($Config.TimeFormat)]"
         if ($val -ne '') { $Config.TimeFormat = $val }
         $val = Read-Host "Date format tokens (e.g. dddd, MMMM D, YYYY) [current: $($Config.DateFormat)]"
         if ($val -ne '') { $Config.DateFormat = $val }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '7' { $continueMenu = $false }
      default { Write-Warning "Invalid option"; Read-Host "Press Enter to continue..." }
    }
  }
}

# -----------------------
# Main: load config, create if missing, apply CLI overrides, then dispatch
# -----------------------
$ConfigPath = Get-ConfigPath -ScriptPath $ScriptPath
$ConfigExistsBefore = Test-Path $ConfigPath
$config = Load-Config -ConfigPath $ConfigPath

# If config didn't exist before and not DebugMode, create it now (persist defaults)
if (-not $ConfigExistsBefore -and -not $DebugMode) {
  Save-Config -ConfigPath $ConfigPath -Config $config | Out-Null
  Write-Host "Created new config at $ConfigPath with defaults."
} elseif (-not $ConfigExistsBefore -and $DebugMode) {
  Write-Host "Config would be created at $ConfigPath, but DebugMode prevents writing."
}

# Apply CLI-provided overrides
if ($PSBoundParameters.ContainsKey('BackgroundImage') -and $BackgroundImage) {
  $copied = Copy-BackgroundIfValid -SourcePath $BackgroundImage -DestFolder $ScriptFolder
  if ($copied) { $config.BackgroundFileName = $copied }
}
if ($PSBoundParameters.ContainsKey('TimeFontSize') -and $TimeFontSize) { $config.TimeFontSize = $TimeFontSize }
if ($PSBoundParameters.ContainsKey('DateFontSize') -and $DateFontSize) { $config.DateFontSize = $DateFontSize }
if ($PSBoundParameters.ContainsKey('FontFamily') -and $FontFamily) { $config.FontFamily = $FontFamily }
if ($PSBoundParameters.ContainsKey('FontColor') -and $FontColor) { $config.FontColor = $FontColor }
if ($PSBoundParameters.ContainsKey('TimeFormat') -and $TimeFormat) { $config.TimeFormat = $TimeFormat }
if ($PSBoundParameters.ContainsKey('DateFormat') -and $DateFormat) { $config.DateFormat = $DateFormat }

# Save updated config unless DebugMode
if (-not $DebugMode) {
  Save-Config -ConfigPath $ConfigPath -Config $config | Out-Null
} else {
  Write-Host "DebugMode: not writing config changes to $ConfigPath"
}

# Dispatch action
switch ($Action) {
  'create' {
    New-KioskHtml -Path $HtmlPath -Config $config | Out-Null
  }
  'kiosk' {
    if (New-KioskHtml -Path $HtmlPath -Config $config) { Start-EdgeKiosk -HtmlFile $HtmlPath | Out-Null }
  }
  'normal' {
    if (New-KioskHtml -Path $HtmlPath -Config $config) { Start-EdgeNormal -HtmlFile $HtmlPath | Out-Null }
  }
  'install' {
    if (New-KioskHtml -Path $HtmlPath -Config $config) { Install-StartupBat -ScriptToCall $ScriptPath -HtmlFile $HtmlPath -BatName $StartupBatName | Out-Null }
  }
  'remove' {
    Remove-StartupBat -BatName $StartupBatName | Out-Null
  }
  'menu' {
    Show-Menu -Config $config -ConfigPath $ConfigPath
  }
  default {
    Write-Error "Unknown action: $Action"
  }
}
