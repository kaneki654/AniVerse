@echo off
REM Exposes the AniVerse web app (port 8000) on a public https URL so the mobile
REM app works from any network, with no LAN IP and no shared Wi-Fi.
REM
REM The API is NOT tunnelled separately: the web app proxies it under
REM /api/anime/*, so one tunnel is enough.
REM
REM Free trycloudflare URLs are assigned fresh on every start. When the URL
REM changes, update `host` in aniverse_mobile\lib\services\api_service.dart and
REM rebuild the APK.

setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%ROOT%\logs\tunnel.log"
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

if not exist "C:\Tools\cloudflared.exe" (
    echo cloudflared not found at C:\Tools\cloudflared.exe
    pause
    exit /b 1
)

echo Starting Cloudflare tunnel to http://localhost:8000 ...
echo The public URL appears below and in %LOG%
echo.
REM cmd.exe has no `tee`; PowerShell's Tee-Object shows the URL and logs it.
powershell -NoProfile -Command "& 'C:\Tools\cloudflared.exe' tunnel --url http://localhost:8000 2>&1 | Tee-Object -FilePath '%LOG%'"
