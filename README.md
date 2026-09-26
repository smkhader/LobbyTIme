# LobbyTime

LobbyTime is a small, self-contained PowerShell utility that generates a single-page HTML lobby display showing the current date and time. It supports a background image, configurable fonts and colors, and can launch Microsoft Edge in kiosk (fullscreen) or normal mode. Settings are persisted in a JSON config file so the display keeps its appearance between runs.

> Note: The repository and script were designed to run on Windows with PowerShell and Microsoft Edge installed.

---

## Contents

- `Create-Kiosk.ps1` — main script (self-contained)
- `kiosk-config.json` — default configuration template (created/updated by the script)
- `Start-Kiosk.bat` — startup .bat template (also embedded in the script)
- `README.md` — this file
- `LICENSE` — MIT License

---

## Quick overview

The script can:

- Generate an HTML file (`kiosk.html`) that displays live time and date
- Accept a PNG or JPG image as a background (validated by file signature) and copy it into the script folder as `background.png` or `background.jpg`
- Persist display settings (font sizes, font family, color, overlay opacity, date/time format) in `kiosk-config.json`
- Launch Microsoft Edge in:
  - Kiosk (fullscreen) mode
  - Normal maximized window mode
- Install or remove a startup `.bat` in `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup` so the kiosk runs at user logon
- Provide an interactive menu for configuration and testing

---

## Installation

1. Clone the repository, or copy `Create-Kiosk.ps1` to the machine you want to use as the kiosk host:

```bash
git clone https://github.com/smkhader/LobbyTIme.git
