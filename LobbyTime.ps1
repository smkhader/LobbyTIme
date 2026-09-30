<#
.SYNOPSIS
LobbyTime.ps1 v2.1 - Interactive Lobby Display Clock

.DESCRIPTION
Creates a responsive HTML clock with advanced customization options, persistent JSON configuration,
and Microsoft Edge integration (kiosk or normal mode). Features a fully interactive settings menu
with background selection (Windows 11 wallpapers, preset colors, or custom hex), font sizing, 
color customization, and date/time format options.

.FEATURES
- Actions: create | kiosk | normal | menu
- Background options:
  * Windows 11 default wallpapers (auto-discovered, including subdirectories)
  * Preset solid colors (Red, Green, Blue, Cyan, Magenta, Yellow, Black, Gray)
  * Custom hex colors (6-digit, 3-digit, with/without # prefix, case-insensitive)
- Persistent JSON config (kiosk-config.json) stored next to script; auto-created on first run
- Interactive menu with back/exit navigation for settings
- Font customization: size, family, color presets
- Time/date format tokens for custom display
- Copies validated PNG/JPG backgrounds into HTML folder with relative path injection
- CLI parameter overrides (saved unless -DebugMode is used)
- HTML/CSS inline for single-file portability

.PARAMETER Action
The action to perform: create, kiosk, normal, or menu (default: menu)

.PARAMETER ScriptPath
Path to this script. If not supplied, auto-resolved to the running script.

.PARAMETER HtmlPath
Path where kiosk.html will be written. Defaults to same folder as ScriptPath.

.PARAMETER BackgroundImage
Path to source PNG/JPG to copy as background. Optional; validated before copy.

.PARAMETER TimeFontSize
Time display font size (e.g., "9vw", "120px"). Optional; overrides config.

.PARAMETER DateFontSize
Date display font size (e.g., "3vw", "40px"). Optional; overrides config.

.PARAMETER FontFamily
Font family CSS string (e.g., "Segoe UI, Arial, sans-serif"). Optional; overrides config.

.PARAMETER FontColor
Text color hex value (e.g., "#FFFFFF"). Optional; overrides config.

.PARAMETER TimeFormat
Time display format using tokens (HH, hh, mm, ss, A). Optional; overrides config.

.PARAMETER DateFormat
Date display format using tokens (YYYY, MMMM, dddd, D, etc). Optional; overrides config.

.PARAMETER DebugMode
If set, prevents writing changes to the config file (useful for testing).

.EXAMPLE
# Interactive menu
powershell.exe -ExecutionPolicy bypass -file .\LobbyTime.ps1

.EXAMPLE
# Create HTML with custom background and launch in kiosk mode
powershell.exe -ExecutionPolicy bypass -file .\LobbyTime.ps1 -Action kiosk -BackgroundImage "C:\path\to\image.jpg"

.VERSION
2.2 - Fixed background path resolution: copies to HTML folder, injects correct relative paths

.NOTES
- Requires Windows 7+ and PowerShell 3+
- Edge integration requires Microsoft Edge (msedge.exe)
- Config file is JSON; can be manually edited
- HTML is self-contained with embedded CSS/JavaScript
#>

param(
  [ValidateSet('create','kiosk','normal','menu')]
  [string]$Action = 'menu',

  [string]$ScriptPath = $null,
  [string]$HtmlPath = $null,
  [string]$BackgroundImage = $null,
  [string]$TimeFontSize = $null,
  [string]$DateFontSize = $null,
  [string]$FontFamily = $null,
  [string]$FontColor = $null,
  [string]$TimeFormat = $null,
  [string]$DateFormat = $null,
  [switch]$DebugMode
)

# -----------------------
# Path resolution
# -----------------------
if (-not $ScriptPath) {
  if ($PSCommandPath) { $ScriptPath = $PSCommandPath } else { $ScriptPath = $MyInvocation.MyCommand.Definition }
}
$ScriptFolder = Split-Path -Parent $ScriptPath
if (-not $HtmlPath) { $HtmlPath = Join-Path -Path $ScriptFolder -ChildPath "kiosk.html" }

# Windows 11 default wallpapers location
$Windows11WallpapersPath = "$env:WINDIR\Web\Screen"

# -----------------------
# Font size presets
# -----------------------
$FontSizePresets = @{
  "Small (5vw)"        = "5vw"
  "Medium (9vw)"       = "9vw"
  "Large (12vw)"       = "12vw"
  "Extra Large (15vw)" = "15vw"
}

# -----------------------
# Font family presets
# -----------------------
$FontFamilyPresets = @{
  "Default (Segoe UI, Roboto, Arial)" = "Segoe UI, Roboto, Arial, sans-serif"
  "Modern (Helvetica, Arial)"         = "Helvetica, Arial, sans-serif"
  "Monospace (Courier New)"           = "'Courier New', monospace"
  "Serif (Georgia)"                   = "Georgia, serif"
}

# -----------------------
# Text color presets
# -----------------------
$FontColorPresets = @{
  "White"      = "#FFFFFF"
  "Light Gray" = "#E0E0E0"
  "Yellow"     = "#FFFF00"
  "Cyan"       = "#00FFFF"
  "Green"      = "#00FF00"
}

# -----------------------
# Time format presets
# -----------------------
$TimeFormatPresets = @{
  "12-hour (2:45 PM)"            = "hh:mm A"
  "12-hour with seconds"         = "hh:mm:ss A"
  "24-hour (14:45)"              = "HH:mm"
  "24-hour with seconds"         = "HH:mm:ss"
}

# -----------------------
# Date format presets
# -----------------------
$DateFormatPresets = @{
  "Full (Monday, January 5, 2026)" = "dddd, MMMM D, YYYY"
  "Short (Mon, Jan 5, 2026)"       = "ddd, MMM D, YYYY"
  "Date only (01/05/2026)"         = "MM/DD/YYYY"
  "Month and day (January 5)"      = "MMMM D"
}

# -----------------------
# Background color presets (RGBCMY + Black + Gray)
# -----------------------
$BackgroundColorPresets = @{
  "Red"      = "#FF0000"
  "Green"    = "#00FF00"
  "Blue"     = "#0000FF"
  "Cyan"     = "#00FFFF"
  "Magenta"  = "#FF00FF"
  "Yellow"   = "#FFFF00"
  "Black"    = "#000000"
  "Gray"     = "#808080"
}

# -----------------------
# Config file helpers
# -----------------------

function Set-ConfigProperty {
  param(
    [Parameter(Mandatory = $true)] [object]$Config,
    [Parameter(Mandatory = $true)] [string]$PropertyName,
    [Parameter(Mandatory = $false)] [object]$Value = $null
  )

  if ($null -eq $Config) {
    return
  }

  $property = $Config.PSObject.Properties[$PropertyName]
  if ($null -ne $property) {
    $Config.$PropertyName = $Value
    return
  }

  $Config | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $Value -Force
}

function Get-ConfigPath {
  param([string]$ScriptPath)
  Join-Path -Path (Split-Path -Parent $ScriptPath) -ChildPath "kiosk-config.json"
}

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
    BackgroundFileName = ""
    BackgroundColor    = ""
    TimeFontSize       = "9vw"
    DateFontSize       = "3vw"
    FontFamily         = "Segoe UI, Roboto, Arial, sans-serif"
    FontColor          = "#FFFFFF"
    OverlayOpacity     = 0.18
    TimeFormat         = "hh:mm A"
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
# Hex color validation & normalization
# Accepts: #FFFFFF, FFFFFF, #FFF, FFF (case-insensitive)
# Returns: #RRGGBB format or $null if invalid
# -----------------------

function Normalize-HexColor {
  param([string]$ColorInput)
  $ColorInput = $ColorInput.Trim()
  
  if ($ColorInput.StartsWith('#')) {
    $ColorInput = $ColorInput.Substring(1)
  }
  
  $ColorInput = $ColorInput.ToUpper()
  
  # Expand 3-digit hex to 6-digit
  if ($ColorInput -match '^[0-9A-F]{3}$') {
    $ColorInput = [string]::Concat($ColorInput[0], $ColorInput[0], $ColorInput[1], $ColorInput[1], $ColorInput[2], $ColorInput[2])
  } elseif ($ColorInput -match '^[0-9A-F]{6}$') {
    # Already valid 6-digit
  } else {
    return $null
  }
  
  return "#$ColorInput"
}

# -----------------------
# Image file validation (PNG/JPG)
# Returns: 'png', 'jpg', or $false
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
    
    # PNG signature: 89 50 4E 47 0D 0A 1A 0A
    $pngSig = @([byte]0x89,[byte]0x50,[byte]0x4E,[byte]0x47,[byte]0x0D,[byte]0x0A,[byte]0x1A,[byte]0x0A)
    $isPng = $true
    for ($i=0; $i -lt 8; $i++) { if ($bytes[$i] -ne $pngSig[$i]) { $isPng = $false; break } }
    if ($isPng) { return 'png' }
    
    # JPEG signature: FF D8
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { return 'jpg' }
    
    return $false
  } catch {
    return $false
  }
}

# -----------------------
# Copy validated image to HTML folder
# Returns: filename (background.png or background.jpg) or $null
# -----------------------

function Copy-BackgroundIfValid {
  param([string]$SourcePath, [string]$HtmlFolderPath)
  if ([string]::IsNullOrWhiteSpace($SourcePath)) { return $null }
  if (-not (Test-Path $SourcePath)) { Write-Warning "Background not found: $SourcePath"; return $null }
  
  $type = Test-IsPngOrJpeg -Path $SourcePath
  if (-not $type) { Write-Warning "Background file is not a valid PNG or JPG."; return $null }
  
  if (-not (Test-Path $HtmlFolderPath)) { New-Item -Path $HtmlFolderPath -ItemType Directory -Force | Out-Null }
  
  $destName = "background.$type"
  $destPath = Join-Path -Path $HtmlFolderPath -ChildPath $destName
  
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
# Discover Windows 11 default wallpapers (recursive, including subdirectories)
# Returns: ordered hashtable with display label => full path
# -----------------------

function Get-Windows11Wallpapers {
  $wallpapers = @{}
  if (Test-Path $Windows11WallpapersPath) {
    $files = @(Get-ChildItem -Path $Windows11WallpapersPath -Include "*.jpg", "*.png" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -eq $false })
    foreach ($file in $files) {
      $relativePath = $file.FullName -replace [regex]::Escape("$Windows11WallpapersPath\"), ""
      $displayLabel = $relativePath
      $wallpapers[$displayLabel] = $file.FullPath
    }
  }
  return $wallpapers
}

# -----------------------
# Edge detection and launch
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

function Start-EdgeKiosk {
  param([string]$HtmlFile)
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
  Start-Process -FilePath $edge -ArgumentList $args -WindowStyle Hidden | Out-Null
  return $true
}

function Start-EdgeNormal {
  param([string]$HtmlFile)
  $edge = Find-Edge
  if (-not $edge) { Write-Error "Microsoft Edge (msedge.exe) not found."; return $false }
  
  $args = @(
    "--profile-directory=Default",
    "--start-maximized",
    "--no-first-run",
    $HtmlFile
  )
  Write-Host "Starting Edge in normal mode..."
  Start-Process -FilePath $edge -ArgumentList $args | Out-Null
  return $true
}

# -----------------------
# HTML generation
# Inlines all CSS and JavaScript for portability
# Background file is copied to same folder as HTML and referenced with relative path
# -----------------------

function New-KioskHtml {
  param([string]$Path, [PSObject]$Config)

  $dir = Split-Path -Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

  if ($Config.BackgroundFileName -and $Config.BackgroundFileName -ne "") {
    $bgCss = "background: url('$($Config.BackgroundFileName)') center/cover no-repeat; background-color:#0b1220;"
  } elseif ($Config.BackgroundColor -and $Config.BackgroundColor -ne "") {
    $bgCss = "background:$($Config.BackgroundColor);"
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
# Menu helpers with back/exit navigation
# -----------------------

function Show-MenuOptions {
  param([hashtable]$Options, [string]$Title = "")
  if ($Title) {
    Write-Host $Title
  }
  $choices = @($Options.Keys)
  for ($i = 0; $i -lt $choices.Count; $i++) {
    Write-Host "$($i+1)) $($choices[$i])"
  }
  Write-Host "B) Back"
  Write-Host "X) Exit to Main Menu"
  Write-Host ""
  $choice = Read-Host "Enter choice (1-$($choices.Count), B, or X)"
  
  if ($choice -eq "B" -or $choice -eq "b") {
    return @{ "action" = "back" }
  }
  if ($choice -eq "X" -or $choice -eq "x") {
    return @{ "action" = "exit" }
  }
  
  $index = [int]$choice - 1
  if ($index -ge 0 -and $index -lt $choices.Count) {
    return @{ "action" = "select"; "value" = $Options[$choices[$index]] }
  }
  return @{ "action" = "none" }
}

# -----------------------
# Background menu (Windows 11 wallpapers, preset colors, custom hex)
# -----------------------

function Show-BackgroundMenu {
  param([PSObject]$Config)
  
  Clear-Host
  Write-Host "=== Choose Background ==="
  Write-Host ""
  Write-Host "1) Windows 11 Default Wallpapers"
  Write-Host "2) Solid Color (Preset: RGBCMY, Black, Gray)"
  Write-Host "3) Solid Color (Custom Hex: #RRGGBB or #RGB)"
  Write-Host "4) Clear background (use default dark blue)"
  Write-Host "B) Back"
  Write-Host "X) Exit to Main Menu"
  Write-Host ""
  
  $choice = Read-Host "Enter choice (1-4, B, or X)"
  
  if ($choice -eq "B" -or $choice -eq "b") {
    return @{ "action" = "back" }
  }
  if ($choice -eq "X" -or $choice -eq "x") {
    return @{ "action" = "exit" }
  }
  
  switch ($choice) {
    '1' {
      $wallpapers = Get-Windows11Wallpapers
      if ($wallpapers.Count -eq 0) {
        Write-Host "No wallpapers found at: $Windows11WallpapersPath"
        Read-Host "Press Enter to continue..."
        return @{ "action" = "back" }
      }
      
      Clear-Host
      Write-Host "=== Windows 11 Default Wallpapers ==="
      Write-Host ""
      $wallpaperList = @($wallpapers.Keys | Sort-Object)
      for ($i = 0; $i -lt $wallpaperList.Count; $i++) {
        Write-Host "$($i+1)) $($wallpaperList[$i])"
      }
      Write-Host "B) Back"
      Write-Host ""
      
      $wallChoice = Read-Host "Enter choice (1-$($wallpaperList.Count)) or B"
      
      if ($wallChoice -eq "B" -or $wallChoice -eq "b") {
        return @{ "action" = "back" }
      }
      
      $wallIndex = [int]$wallChoice - 1
      if ($wallIndex -ge 0 -and $wallIndex -lt $wallpaperList.Count) {
        $selectedWallpaper = $wallpapers[$wallpaperList[$wallIndex]]
        $htmlFolder = Split-Path -Parent $HtmlPath
        $bgFile = Copy-BackgroundIfValid -SourcePath $selectedWallpaper -HtmlFolderPath $htmlFolder
        if ($bgFile) {
          Write-Host "Wallpaper selected: $($wallpaperList[$wallIndex])"
          Read-Host "Press Enter to continue..."
          return @{ "action" = "select"; "fileName" = $bgFile; "color" = "" }
        }
      }
      return @{ "action" = "back" }
    }
    
    '2' {
      Clear-Host
      Write-Host "=== Solid Color (Preset) ==="
      Write-Host ""
      $result = Show-MenuOptions $BackgroundColorPresets
      if ($result.action -eq "select") {
        Write-Host "Color selected: $($result.value)"
        Read-Host "Press Enter to continue..."
        return @{ "action" = "select"; "fileName" = ""; "color" = $result.value }
      }
      return @{ "action" = "back" }
    }
    
    '3' {
      Clear-Host
      Write-Host "=== Solid Color (Custom Hex) ==="
      Write-Host ""
      Write-Host "Enter a hex color value:"
      Write-Host "  - 6-digit: #FFFFFF or FFFFFF"
      Write-Host "  - 3-digit: #FFF or FFF (expands to #FFFFFF)"
      Write-Host "  - Case insensitive"
      Write-Host ""
      
      $hexInput = Read-Host "Enter hex color"
      $normalized = Normalize-HexColor -ColorInput $hexInput
      
      if ($normalized) {
        Write-Host "Color selected: $normalized"
        Read-Host "Press Enter to continue..."
        return @{ "action" = "select"; "fileName" = ""; "color" = $normalized }
      } else {
        Write-Warning "Invalid hex color format. Use #FFFFFF, FFFFFF, #FFF, or FFF"
        Read-Host "Press Enter to continue..."
        return @{ "action" = "back" }
      }
    }
    
    '4' {
      Write-Host "Background cleared (using default dark blue)"
      Read-Host "Press Enter to continue..."
      return @{ "action" = "select"; "fileName" = ""; "color" = "" }
    }
    
    default {
      Write-Warning "Invalid option"
      return @{ "action" = "back" }
    }
  }
}

# -----------------------
# Settings submenu
# -----------------------

function Edit-Settings {
  param([PSObject]$Config, [string]$ConfigPath)
  $continueSettings = $true
  while ($continueSettings) {
    Clear-Host
    Write-Host "=== Edit Settings ==="
    Write-Host ""

    # Background selection
    Write-Host "Background (currently: $(if ($Config.BackgroundFileName) { $Config.BackgroundFileName } elseif ($Config.BackgroundColor) { $Config.BackgroundColor } else { 'Default (dark blue)' }))"
    $result = Show-BackgroundMenu -Config $Config
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "BackgroundFileName" -Value $result.fileName
      Set-ConfigProperty -Config $Config -PropertyName "BackgroundColor" -Value $result.color
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Time Font Size (currently: $($Config.TimeFontSize))"
    $result = Show-MenuOptions $FontSizePresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "TimeFontSize" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Date Font Size (currently: $($Config.DateFontSize))"
    $result = Show-MenuOptions $FontSizePresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "DateFontSize" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Font Family (currently: $($Config.FontFamily))"
    $result = Show-MenuOptions $FontFamilyPresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "FontFamily" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Font Color (currently: $($Config.FontColor))"
    $result = Show-MenuOptions $FontColorPresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "FontColor" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Time Format (currently: $($Config.TimeFormat))"
    $result = Show-MenuOptions $TimeFormatPresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "TimeFormat" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }
    
    if (-not $continueSettings) { break }
    Write-Host ""
    Write-Host "Date Format (currently: $($Config.DateFormat))"
    $result = Show-MenuOptions $DateFormatPresets
    if ($result.action -eq "select") {
      Set-ConfigProperty -Config $Config -PropertyName "DateFormat" -Value $result.value
    } elseif ($result.action -eq "exit") {
      $continueSettings = $false
      if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
      break
    }

    if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
    $continueSettings = $false
  }
}

# -----------------------
# Main menu
# -----------------------

function Show-Menu {
  param([PSObject]$Config, [string]$ConfigPath)
  $continueMenu = $true
  while ($continueMenu) {
    Clear-Host
    Write-Host "=== LobbyTime v2.2 - Kiosk Display Helper ==="
    Write-Host ""
    Write-Host "1) Create HTML only"
    Write-Host "2) Create HTML and launch Edge (Kiosk Fullscreen)"
    Write-Host "3) Create HTML and launch Edge (Normal Window)"
    Write-Host "4) Edit settings"
    Write-Host "5) Exit"
    Write-Host ""
    Write-Host "Current settings (from config):"
    Write-Host "  Background: $(if ($Config.BackgroundFileName) { $Config.BackgroundFileName } elseif ($Config.BackgroundColor) { $Config.BackgroundColor } else { 'Default (dark blue)' })"
    Write-Host "  Time Font Size: $($Config.TimeFontSize)"
    Write-Host "  Date Font Size: $($Config.DateFontSize)"
    Write-Host "  Font Family: $($Config.FontFamily)"
    Write-Host "  Font Color: $($Config.FontColor)"
    Write-Host "  Time Format: $($Config.TimeFormat)"
    Write-Host "  Date Format: $($Config.DateFormat)"
    Write-Host ""
    $choice = Read-Host "Enter choice (1-5)"
    switch ($choice) {
      '1' {
         New-KioskHtml -Path $HtmlPath -Config $Config
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '2' {
         if (New-KioskHtml -Path $HtmlPath -Config $Config) { Start-EdgeKiosk -HtmlFile $HtmlPath | Out-Null }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '3' {
         if (New-KioskHtml -Path $HtmlPath -Config $Config) { Start-EdgeNormal -HtmlFile $HtmlPath | Out-Null }
         if (-not $DebugMode) { Save-Config -ConfigPath $ConfigPath -Config $Config | Out-Null }
         Read-Host "Press Enter to continue..."
      }
      '4' {
         Edit-Settings -Config $Config -ConfigPath $ConfigPath
      }
      '5' { $continueMenu = $false }
      default { Write-Warning "Invalid option"; Read-Host "Press Enter to continue..." }
    }
  }
}

# -----------------------
# Main execution
# -----------------------

$ConfigPath = Get-ConfigPath -ScriptPath $ScriptPath
$ConfigExistsBefore = Test-Path $ConfigPath
$config = Load-Config -ConfigPath $ConfigPath

# Create config file if it doesn't exist
if (-not $ConfigExistsBefore -and -not $DebugMode) {
  Save-Config -ConfigPath $ConfigPath -Config $config | Out-Null
  Write-Host "Created new config at $ConfigPath with defaults."
} elseif (-not $ConfigExistsBefore -and $DebugMode) {
  Write-Host "Config would be created at $ConfigPath, but DebugMode prevents writing."
}

# Apply CLI parameter overrides
if ($PSBoundParameters.ContainsKey('BackgroundImage') -and $BackgroundImage) {
  $htmlFolder = Split-Path -Parent $HtmlPath
  $copied = Copy-BackgroundIfValid -SourcePath $BackgroundImage -HtmlFolderPath $htmlFolder
  if ($copied) { Set-ConfigProperty -Config $config -PropertyName "BackgroundFileName" -Value $copied }
}
if ($PSBoundParameters.ContainsKey('TimeFontSize') -and $TimeFontSize) { Set-ConfigProperty -Config $config -PropertyName "TimeFontSize" -Value $TimeFontSize }
if ($PSBoundParameters.ContainsKey('DateFontSize') -and $DateFontSize) { Set-ConfigProperty -Config $config -PropertyName "DateFontSize" -Value $DateFontSize }
if ($PSBoundParameters.ContainsKey('FontFamily') -and $FontFamily) { Set-ConfigProperty -Config $config -PropertyName "FontFamily" -Value $FontFamily }
if ($PSBoundParameters.ContainsKey('FontColor') -and $FontColor) { Set-ConfigProperty -Config $config -PropertyName "FontColor" -Value $FontColor }
if ($PSBoundParameters.ContainsKey('TimeFormat') -and $TimeFormat) { Set-ConfigProperty -Config $config -PropertyName "TimeFormat" -Value $TimeFormat }
if ($PSBoundParameters.ContainsKey('DateFormat') -and $DateFormat) { Set-ConfigProperty -Config $config -PropertyName "DateFormat" -Value $DateFormat }

# Save config with CLI overrides (unless DebugMode)
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
  'menu' {
    Show-Menu -Config $config -ConfigPath $ConfigPath
  }
  default {
    Write-Error "Unknown action: $Action"
  }
}
