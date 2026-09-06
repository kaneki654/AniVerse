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

REM Find cloudflared: PATH first, then the usual manual-download spots. Hardcoding
REM C:\Tools meant this script only ever worked on the machine it was written on.
set "CF="
for %%I in (cloudflared.exe) do if not defined CF set "CF=%%~$PATH:I"
if not defined CF if exist "C:\Tools\cloudflared.exe" set "CF=C:\Tools\cloudflared.exe"
if not defined CF if exist "%ProgramFiles%\cloudflared\cloudflared.exe" set "CF=%ProgramFiles%\cloudflared\cloudflared.exe"
if not defined CF if exist "%LOCALAPPDATA%\cloudflared\cloudflared.exe" set "CF=%LOCALAPPDATA%\cloudflared\cloudflared.exe"

if not defined CF (
    echo cloudflared was not found.
    echo.
    echo Put cloudflared.exe on your PATH, or at C:\Tools\cloudflared.exe
    echo Download: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
    echo.
    pause
    exit /b 1
)
echo Using %CF%

echo Starting Cloudflare tunnel to http://localhost:8000 ...
echo The public URL appears below and in %LOG%
echo.
REM cmd.exe has no `tee`; PowerShell's Tee-Object shows the URL and logs it.
powershell -NoProfile -Command "& '%CF%' tunnel --url http://localhost:8000 2>&1 | Tee-Object -FilePath '%LOG%'"
