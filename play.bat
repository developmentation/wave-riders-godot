@echo off
rem Launch Wave Riders (Godot build) full screen on the best GPU.
rem   play.bat            - play
rem   play.bat --editor   - open the project in the Godot editor instead
setlocal
set GODOT=C:\dev\games\godot\Godot_v4.7.2-stable_win64.exe
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
if not exist "%GODOT%" goto :missing
if "%~1"=="--editor" goto :editor
start "" "%GODOT%" --path "%ROOT%" --fullscreen
goto :end
:editor
start "" "%GODOT%" --path "%ROOT%" --editor
goto :end
:missing
echo Godot not found at %GODOT%
echo Download Godot 4.7.2 win64 from godotengine.org into C:\dev\games\godot\ or edit this file.
pause
:end
endlocal
