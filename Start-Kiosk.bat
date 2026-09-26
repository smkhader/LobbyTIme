@echo off
REM This .bat starts the Create-Kiosk.ps1 in kiosk mode.
REM Place in: C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Start-Kiosk.bat
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"C:\Users\Public\Documents\Create-Kiosk.ps1\" -Action kiosk -HtmlPath \"C:\Users\Public\Documents\kiosk.html\"' -WindowStyle Hidden"
