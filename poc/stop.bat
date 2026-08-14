@echo off
if not defined PORT set PORT=8000

echo Stopping CW-ETL-FIELDMAP server...
echo Asking it to shut down gracefully first (flushes any queued shared-mapping-log confirmations)...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri http://127.0.0.1:%PORT%/api/shutdown -Method POST -TimeoutSec 20 -UseBasicParsing | Out-Null } catch {}"

timeout /t 2 /nobreak >nul

powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*app.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Done.
pause
