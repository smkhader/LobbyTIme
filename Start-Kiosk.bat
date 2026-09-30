@echo off
REM This .bat starts the Create-Kiosk.ps1 in kiosk mode.
REM Place in: C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Start-Kiosk.bat
powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File .\LobbyTIme.ps1 -Action kiosk -HtmlPath \"C:\Users\Public\Documents\kiosk.html\"' -WindowStyle Hidden"
