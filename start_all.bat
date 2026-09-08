@echo off
REM AniVerse - start everything (Windows). The twin of start_all.sh.
REM
REM   start_all.bat                servers + tunnel, and publish the tunnel URL
REM   start_all.bat --no-publish   servers + tunnel, print the URL instead
REM   start_all.bat --no-tunnel    servers only (this is what run.bat does)
REM
REM Publishing matters: every cloudflared start gets a fresh random URL, and the
REM Android app looks the current one up from the install site. Starting a
REM tunnel without publishing it leaves the app pointed at the previous, now
REM dead address - which looks exactly like the app being broken.
setlocal enabledelayedexpansion

REM `timeout /t` aborts with "Input redirection is not supported" whenever stdin
REM is redirected, which happens as soon as this is run from anything other than
REM an interactive console. ping to loopback sleeps just as well and does not care.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "WITH_TUNNEL=1"
set "WITH_PUBLISH=1"

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--no-tunnel" (set "WITH_TUNNEL=0" & shift & goto parse)
if /i "%~1"=="--no-publish" (set "WITH_PUBLISH=0" & shift & goto parse)
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo unknown option: %~1
exit /b 2

:usage
echo AniVerse - start everything.
echo.
echo   start_all.bat                servers + tunnel, and publish the tunnel URL
echo   start_all.bat --no-publish   servers + tunnel, print the URL instead
echo   start_all.bat --no-tunnel    servers only
exit /b 0

:parsed
set "PY=python"
if defined PYTHON set "PY=%PYTHON%"

REM --- dependency preflight ----------------------------------------------------
REM Without this a missing package just makes uvicorn exit on import, the restart
REM loop respawns it every 3s, and all you see is a health check timing out. The
REM usual cause is installing only the root requirements.txt, which does not
REM carry the backend's packages - Crypto (pycryptodome) is the one that bites.
echo.
echo ==^> Checking Python dependencies
set "MISSING="
for /f "delims=" %%M in ('%PY% "%ROOT%\scripts\check_deps.py" 2^>nul') do set "MISSING=%%M"
if not "!MISSING!"=="" (
    echo.
    echo Missing Python packages: !MISSING!
    echo.
    echo Install both requirements files with the same interpreter this script
    echo uses ^(%PY%^) -- the root one alone does not cover the backend:
    echo.
    echo   %PY% -m pip install -r AniVerseApiUrl\requirements.txt -r requirements.txt
    echo.
    pause
    exit /b 1
)
echo   dependencies ok

REM --- free the ports ----------------------------------------------------------
REM A leftover server keeps answering while the new one dies on a bind failure
REM and its restart loop spins, which reads exactly like a code change doing
REM nothing. Close the loop windows first or they just respawn the servers.
echo.
echo ==^> Clearing ports 8000 and 8001
taskkill /FI "WINDOWTITLE eq AniVerse-Backend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq AniVerse-Frontend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq AniVerse-Tunnel*" /F >nul 2>&1
REM Also the process itself: a surviving cloudflared keeps tunnel.log open, the
REM del below fails silently, and a previous run's URL gets scraped back out.
taskkill /IM cloudflared.exe /F >nul 2>&1
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000,8001 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }" >nul 2>&1
ping -n 3 127.0.0.1 >nul 2>&1

REM --- servers -----------------------------------------------------------------
echo.
echo ==^> Starting backend on 8001
start "AniVerse-Backend" /D "%ROOT%\AniVerseApiUrl" cmd /c "%ROOT%\run_backend_loop.bat"

set "OK=0"
for /L %%i in (1,1,30) do (
    if !OK! equ 0 (
        curl -fsS http://localhost:8001/health >nul 2>&1
        if !errorlevel! equ 0 (set "OK=1") else (ping -n 2 127.0.0.1 >nul 2>&1)
    )
)
if !OK! equ 0 (
    echo   backend did not come up -- see %LOG_DIR%\backend.log
    pause
    exit /b 1
)
echo   backend ok

echo.
echo ==^> Starting frontend on 8000
start "AniVerse-Frontend" /D "%ROOT%" cmd /c "%ROOT%\run_frontend_loop.bat"

set "OK=0"
for /L %%i in (1,1,30) do (
    if !OK! equ 0 (
        curl -fsS http://localhost:8000/ >nul 2>&1
        if !errorlevel! equ 0 (set "OK=1") else (ping -n 2 127.0.0.1 >nul 2>&1)
    )
)
if !OK! equ 0 (
    echo   frontend did not come up -- see %LOG_DIR%\frontend.log
    pause
    exit /b 1
)
echo   frontend ok

if "%WITH_TUNNEL%"=="0" goto done_notunnel

REM --- tunnel ------------------------------------------------------------------
REM Delegated to run_tunnel.bat, which already finds cloudflared and tees to the
REM log -- the same way the servers are delegated to their loop scripts. Doing it
REM inline needed cmd /c with nested quotes around the exe path, which cmd
REM mis-parsed: the tunnel never launched and the failure was silent.
echo.
echo ==^> Starting tunnel
set "TUNNEL_LOG=%LOG_DIR%	unnel.log"
if exist "%TUNNEL_LOG%" del "%TUNNEL_LOG%" >nul 2>&1
start "AniVerse-Tunnel" /D "%ROOT%" "%ROOT%\run_tunnel.bat"

set "URL="
for /L %%i in (1,1,40) do (
    if not defined URL (
        for /f "delims=" %%U in ('powershell -NoProfile -Command "try { (Select-String -Path '%TUNNEL_LOG%' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches -ErrorAction Stop | Select-Object -First 1).Matches[0].Value } catch { '' }" 2^>nul') do set "URL=%%U"
        if not defined URL ping -n 3 127.0.0.1 >nul 2>&1
    )
)

if not defined URL (
    echo   no tunnel URL appeared -- see %TUNNEL_LOG%
    echo   servers are still running on localhost.
    goto done_notunnel
)
echo   !URL!

REM --- publish the address -----------------------------------------------------
REM Without this the app keeps using whatever address was published last, which
REM is now dead - the most common reason "the app stopped working".
if "%WITH_PUBLISH%"=="1" (
    echo.
    echo ==^> Publishing the address so the app can find it
    %PY% "%ROOT%\aniverse_site\build_site.py" --host "!URL!" >nul
    if !errorlevel! neq 0 (
        echo   build_site.py failed; the app was not told about this URL.
    ) else (
        where vercel >nul 2>&1
        if !errorlevel! equ 0 (
            pushd "%ROOT%\aniverse_site"
            call vercel deploy --prod --yes >nul 2>&1
            if !errorlevel! equ 0 (
                echo   published to https://aniversesite.vercel.app
            ) else (
                echo   vercel deploy failed -- publish manually:
                echo     cd aniverse_site ^&^& vercel deploy --prod
            )
            popd
        ) else (
            echo   vercel CLI not installed, so the app was NOT told about this URL.
            echo   Install it ^(npm i -g vercel^) and re-run, or from a machine that has it:
            echo     python aniverse_site\build_site.py --host !URL!
            echo     cd aniverse_site ^&^& vercel deploy --prod
        )
    )
)

echo.
echo ==^> AniVerse is running
echo   Frontend : http://localhost:8000
echo   Backend  : http://localhost:8001
echo   Public   : !URL!
echo   Logs     : %LOG_DIR%
echo.
echo On the phone: the app finds this address by itself from build 8 onward.
echo On an older build, paste the Public URL under the gear icon.
echo.
echo Close this window or run stop_all.bat to stop everything.
pause >nul
exit /b 0

:done_notunnel
echo.
echo ==^> AniVerse is running
echo   Frontend : http://localhost:8000
echo   Backend  : http://localhost:8001
echo   Logs     : %LOG_DIR%
echo.
echo Close this window or run stop_all.bat to stop everything.
pause >nul
exit /b 0
