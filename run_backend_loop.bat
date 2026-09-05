@echo off
REM Backend restart loop (Windows) — equivalent to run_forever() in run.sh
REM Does NOT set PYTHONPATH to libs/ — uses pip-installed Windows packages.
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"

:loop
echo [%date% %time%] starting backend >> "%LOG_DIR%\backend.log"
echo [%date% %time%] starting backend with: python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 1>&2
cd /d "%ROOT%\AniVerseApiUrl"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 >> "%LOG_DIR%\backend.log" 2>&1
echo [%date% %time%] backend exited %errorlevel% — restarting in 3s >> "%LOG_DIR%\backend.log"
timeout /t 3 /nobreak >nul
goto loop
