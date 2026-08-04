@echo off
cd /d "%~dp0"

if not exist "..\reference\target_schema_full.json" (
    echo ERROR: Can't find ..\reference\target_schema_full.json
    echo This "poc" folder must stay inside the full ETLGetProject checkout -
    echo copy/share the WHOLE project folder, not just "poc" on its own.
    pause
    exit /b 1
)

where py >nul 2>nul
if %ERRORLEVEL%==0 (
    set "PYCMD=py"
) else (
    where python >nul 2>nul
    if %ERRORLEVEL%==0 (
        set "PYCMD=python"
    ) else (
        echo ERROR: Python was not found on this machine.
        echo Install it from https://www.python.org/downloads/ and check
        echo "Add python.exe to PATH" during setup, then run this again.
        pause
        exit /b 1
    )
)

set CHROME_EXE=C:\Program Files\Google\Chrome\Application\chrome.exe
if not exist "%CHROME_EXE%" set "CHROME_EXE=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME_EXE%" set "CHROME_EXE=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not defined PORT set PORT=8000

echo Starting CW-ETL-FIELDMAP server...
start "CW-ETL-FIELDMAP server" /min %PYCMD% app.py

timeout /t 2 /nobreak >nul

if exist "%CHROME_EXE%" (
    start "" "%CHROME_EXE%" --app=http://127.0.0.1:%PORT% --new-window
) else (
    start http://127.0.0.1:%PORT%
)

echo.
echo Server is running in a minimized window (check your taskbar) - closing THIS window will NOT stop it.
echo To stop the server, run stop.bat.
echo.
pause
