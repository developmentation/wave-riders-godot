@echo off
rem Launch Wave Riders (Godot build) full screen on the best GPU.
rem   play.bat            - play
rem   play.bat --editor   - open the project in the Godot editor instead
setlocal
set GODOT=C:\dev\games\godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%. Download Godot 4.7.2 (win64) into C:\dev\games\godot\ or edit this file.
  pause
  exit /b 1
)
if "%1"=="--editor" (
  start "" "%GODOT%" --path "%~dp0." --editor
) else (
  start "" "%GODOT%" --path "%~dp0." --fullscreen
)
endlocal
