@echo off
REM Uninstall vchord from PostgreSQL 17 on Windows. REQUIRES ADMIN.
REM Run AFTER `DROP EXTENSION vchord;` in psql.

setlocal
set "PG_LIB=C:\Program Files\PostgreSQL\17\lib"
set "PG_SHARE=C:\Program Files\PostgreSQL\17\share\extension"

echo == Uninstalling vchord ==
del /F /Q "%PG_LIB%\vchord.dll" 2>nul
del /F /Q "%PG_SHARE%\vchord--0.0.0.sql" 2>nul
del /F /Q "%PG_SHARE%\vchord.control" 2>nul
echo Done. Remember to remove vchord from shared_preload_libraries and restart PostgreSQL.
endlocal
