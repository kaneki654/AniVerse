@echo off
REM AniVerse launcher (Windows) — starts backend (8001) and frontend (8000), restarts either on crash.
REM NOTE: Linux uses libs/ (bundled .so binaries). Windows uses pip-installed packages instead.
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
REM Remove trailing backslash
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

REM Do NOT set PYTHONPATH to libs/ — those are Linux-only .so binaries.
REM Windows dependencies are installed via: pip install -r requirements.txt

set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM --- Stop anything already running on our ports ---
REM A server left over from a previous launch keeps the port, so the new one
REM exits 3 (bind failure) and the restart loop spins forever while the OLD
REM code carries on serving. Clear the ports before starting anything.
echo Stopping any previous AniVerse servers...

REM Close the restart-loop windows first, or they just respawn the servers.
taskkill /FI "WINDOWTITLE eq AniVerse-Backend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq AniVerse-Frontend*" /F >nul 2>&1

powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000,8001 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }" >nul 2>&1

REM Give Windows a moment to release the sockets.
timeout /t 2 /nobreak >nul

REM --- Start backend ---
echo [%date% %time%] starting backend >> "%LOG_DIR%\backend.log"
echo [%date% %time%] starting backend with: python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 1>&2
start "AniVerse-Backend" /D "%ROOT%\AniVerseApiUrl" cmd /c "%~dp0run_backend_loop.bat"

REM --- Wait for backend /health (up to 20s) before starting frontend ---
set "HEALTH_OK=0"
for /L %%i in (1,1,20) do (
    if !HEALTH_OK! equ 0 (
        curl -fsS http://localhost:8001/health >nul 2>&1
        if !errorlevel! equ 0 (
            set "HEALTH_OK=1"
        ) else (
            timeout /t 1 /nobreak >nul
        )
    )
)

REM --- Start frontend ---
echo [%date% %time%] starting frontend >> "%LOG_DIR%\frontend.log"
echo [%date% %time%] starting frontend with: python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 1>&2
start "AniVerse-Frontend" /D "%ROOT%" cmd /c "%~dp0run_frontend_loop.bat"

echo AniVerse is running. Close this window or press Ctrl+C to stop.
echo Backend  : http://localhost:8001
echo Frontend : http://localhost:8000
pause >nul
