@echo off
REM Builds GarminRace2 for the Venu 2 and signs it with your developer key.
REM Output: bin\GarminRace2.prg  (copy to the watch's GARMIN\APPS folder, or run in the simulator)
REM
REM Key lookup order: %DEV_KEY% env var, then developer_key next to this file,
REM then ..\..\GarminRace\developer_key. Never commit your key.

set SDK=%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2
set DEVICE=venu2

cd /d "%~dp0"
set KEY=%DEV_KEY%
if "%KEY%"=="" if exist "%~dp0developer_key" set KEY=%~dp0developer_key
if "%KEY%"=="" set KEY=%~dp0..\..\GarminRace\developer_key

if not exist bin mkdir bin
call "%SDK%\bin\monkeyc.bat" -d %DEVICE% -f monkey.jungle -o bin\GarminRace2.prg -y "%KEY%" -w
if %ERRORLEVEL% EQU 0 (echo. & echo Build successful: bin\GarminRace2.prg) else (echo. & echo Build failed.)
pause
