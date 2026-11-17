@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Add WinGet's portable command links for this process, including on first run.
set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WinGet\Links;%ProgramFiles%\WinGet\Links;%LOCALAPPDATA%\Microsoft\WindowsApps"
set "launch_path=%PATH%"
call :ensure DenoLand.Deno deno.exe || goto setup_failed
call :ensure yt-dlp.yt-dlp yt-dlp.exe || goto setup_failed
call :ensure Gyan.FFmpeg ffmpeg.exe ffprobe.exe || goto setup_failed

rem yt-dlp starts aria2c itself. Deno only needs to know if it is available.
set "YTMAX_ARIA2=0"
for %%A in (aria2c.exe) do if not "%%~$PATH:A"=="" set "YTMAX_ARIA2=1"
set "allowed=yt-dlp.exe,ffmpeg.exe,ffprobe.exe"
for %%E in (explorer.exe) do if not "%%~$PATH:E"=="" set "allowed=%allowed%,explorer.exe"
for %%D in (deno.exe) do set "deno_bin=%%~$PATH:D"
"%deno_bin%" run --no-config --no-lock --cached-only --allow-env=USERPROFILE,YTMAX_ARIA2 --allow-read --allow-write --allow-run=%allowed% "%~dp0downloader.ts"
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%

:ensure
call :present %2 %3 && exit /b 0
rem Pick up changes made by an installer since this terminal was opened.
call :refresh_path
call :present %2 %3 && exit /b 0
for %%W in (winget.exe) do set "winget_bin=%%~$PATH:W"
if not defined winget_bin (
  echo Cannot install %1: WinGet is missing. Install App Installer from Microsoft Store, then run again.
  exit /b 1
)
echo Installing missing dependency %1 with WinGet...
"%winget_bin%" install --source winget --id "%~1" --exact --no-upgrade
set "install_code=%errorlevel%"
call :refresh_path
call :present %2 %3 && exit /b 0
echo Setup could not find %2 %3 after WinGet exited with code %install_code%.
echo Open a new Terminal and try again. See README-FIRST.txt if the tools are still missing.
exit /b 1

:present
for %%E in (%*) do if "%%~$PATH:E"=="" exit /b 1
exit /b 0

:refresh_path
rem Preserve custom entries and import each registered PATH only once per group.

for /f "delims=" %%P in ('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -Command "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%launch_path%;%%P"
exit /b 0

:setup_failed
pause
exit /b 1
