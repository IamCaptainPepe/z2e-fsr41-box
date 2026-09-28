@echo off
cd /d "%~dp0.."
where pwsh >nul 2>&1
if errorlevel 1 (
  echo PowerShell 7 required. Install pwsh, then run this again.
  pause
  exit /b 1
)
set "GUI_ARGS="
if "%Z2E_COMPACT%"=="1" set "GUI_ARGS=-Compact"
pwsh -NoProfile -File "%~dp0z2e-gui.ps1" %GUI_ARGS%
