@echo off
REM Single-click admin script: install vchord + configure Postgres + restart service.
REM Right-click this file → "Run as administrator". Click YES on the UAC prompt.
REM Claude finishes everything else automatically once this completes.

setlocal

set "PG_LIB=C:\Program Files\PostgreSQL\17\lib"
set "PG_SHARE=C:\Program Files\PostgreSQL\17\share\extension"
set "PG_DATA=C:\Program Files\PostgreSQL\17\data"
set "PG_CONF=%PG_DATA%\postgresql.conf"
set "BUILD=G:\projects\vchord-windows-port\vchord\build"
set "SERVICE=postgresql-x64-17"

echo ============================================================
echo  vchord install + Postgres prep (admin)
echo ============================================================

REM Step 0: confirm we have the build artifacts
if not exist "%BUILD%\pkglibdir\vchord.dll" (
  echo ERROR: vchord.dll not found at %BUILD%\pkglibdir\vchord.dll
  echo Run the build first via step-build2.cmd
  pause
  exit /b 1
)

REM Step 1: copy DLL + extension files
echo.
echo [1/4] Copying vchord files into Postgres install...
copy /Y "%BUILD%\pkglibdir\vchord.dll" "%PG_LIB%\vchord.dll" || (echo Copy DLL failed && pause && exit /b 1)
copy /Y "%BUILD%\sharedir\extension\vchord--0.0.0.sql" "%PG_SHARE%\vchord--0.0.0.sql" || (echo Copy SQL failed && pause && exit /b 1)
copy /Y "%BUILD%\sharedir\extension\vchord.control" "%PG_SHARE%\vchord.control" || (echo Copy control failed && pause && exit /b 1)

REM Step 2: add vchord to shared_preload_libraries (idempotent)
echo.
echo [2/4] Updating postgresql.conf shared_preload_libraries...
powershell -NoProfile -Command ^
  "$conf = '%PG_CONF%';" ^
  "$content = Get-Content $conf -Raw;" ^
  "if ($content -match \"^\s*shared_preload_libraries\s*=\s*'([^']*)'\") {" ^
  "  $current = $Matches[1]; $entries = if ($current) { $current -split ',\s*' } else { @() };" ^
  "  if ($entries -notcontains 'vchord') { $entries += 'vchord' }" ^
  "  $new = ($entries -join ','); $content = [regex]::Replace($content, \"^\s*shared_preload_libraries\s*=\s*'[^']*'\", \"shared_preload_libraries = '$new'\", 'Multiline')" ^
  "} else { $content += \"`r`nshared_preload_libraries = 'vchord'`r`n\" }" ^
  "Set-Content -Path $conf -Value $content -Encoding ASCII;" ^
  "Write-Host 'shared_preload_libraries updated.'"

REM Step 3: stop Postgres service
echo.
echo [3/4] Restarting Postgres service to apply config...
net stop %SERVICE%
if errorlevel 1 (
  echo WARNING: Service stop returned errorlevel %errorlevel%. Continuing anyway.
)

REM Step 4: start Postgres service
net start %SERVICE%
if errorlevel 1 (
  echo ERROR: Failed to start Postgres service. Check the Event Viewer for details.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  ADMIN STEPS COMPLETE
echo ============================================================
echo.
echo  vchord installed:  %PG_LIB%\vchord.dll
echo  config updated:    %PG_CONF%
echo  Postgres restarted: %SERVICE%
echo.
echo  vchord is now installed and registered with Postgres.
echo.
echo  Next: in psql, run `CREATE EXTENSION vchord CASCADE;`
echo  to enable it on your database.
echo.
echo  If you reached this from an AI agent (Claude, Cursor, Cline, etc.),
echo  return to your agent and confirm the install completed — it will
echo  finish any remaining migration steps (column ALTER, re-embed, etc.).
echo.
pause
endlocal
