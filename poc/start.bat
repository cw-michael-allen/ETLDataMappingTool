@echo off
cd /d "%~dp0"
set PYEXE=C:\Users\MichaelAllen\AppData\Local\Programs\Python\Python314\python.exe
if exist "%PYEXE%" (
    "%PYEXE%" app.py
) else (
    python app.py
)
pause
