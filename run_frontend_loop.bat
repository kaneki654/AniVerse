@echo off
REM Frontend restart loop (Windows) — equivalent to run_forever() in run.sh
REM Does NOT set PYTHONPATH to libs/ — uses pip-installed Windows packages.
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"

:loop
echo [%date% %time%] starting frontend >> "%LOG_DIR%\frontend.log"
echo [%date% %time%] starting frontend with: python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 1>&2
cd /d "%ROOT%"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 >> "%LOG_DIR%\frontend.log" 2>&1
echo [%date% %time%] frontend exited %errorlevel% — restarting in 3s >> "%LOG_DIR%\frontend.log"
timeout /t 3 /nobreak >nul
goto loop
