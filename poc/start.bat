@echo off
cd /d "%~dp0"
set PYEXE=C:\Users\MichaelAllen\AppData\Local\Programs\Python\Python314\python.exe
if not exist "%PYEXE%" set PYEXE=python
set CHROME_EXE=C:\Program Files\Google\Chrome\Application\chrome.exe
if not defined PORT set PORT=8000

echo Starting CW-ETL-FIELDMAP server...
start "CW-ETL-FIELDMAP server" /min "%PYEXE%" app.py

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
