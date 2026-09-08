@echo off
REM Stops everything start_all.bat started.
REM
REM Needed because the .bat launches its loops in detached windows, so unlike
REM start_all.sh there is no Ctrl+C that reaches them. Closing the launcher
REM window leaves the servers and the tunnel running.
setlocal

REM `timeout /t` aborts with "Input redirection is not supported" whenever stdin
REM is redirected, which happens as soon as this is run from anything other than
REM an interactive console. ping to loopback sleeps just as well and does not care.

echo Stopping AniVerse...

REM Loop windows first, or they respawn the servers as fast as they are killed.
taskkill /FI "WINDOWTITLE eq AniVerse-Backend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq AniVerse-Frontend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq AniVerse-Tunnel*" /F >nul 2>&1

powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000,8001 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }" >nul 2>&1
taskkill /IM cloudflared.exe /F >nul 2>&1

ping -n 3 127.0.0.1 >nul 2>&1

powershell -NoProfile -Command "$p = Get-NetTCPConnection -LocalPort 8000,8001 -State Listen -ErrorAction SilentlyContinue; if ($p) { Write-Host '  still listening:'; $p | ForEach-Object { Write-Host ('    port ' + $_.LocalPort + ' pid ' + $_.OwningProcess) } } else { Write-Host '  ports 8000 and 8001 are clear' }"

echo Done.
