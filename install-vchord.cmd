@echo off
REM Install vchord into PostgreSQL 17 on Windows.
REM REQUIRES ADMIN — right-click "Run as administrator".
REM Reverses: uninstall-vchord.cmd

setlocal

set "PG_LIB=C:\Program Files\PostgreSQL\17\lib"
set "PG_SHARE=C:\Program Files\PostgreSQL\17\share\extension"
set "BUILD=G:\projects\vchord-windows-port\vchord\build"

if not exist "%BUILD%\pkglibdir\vchord.dll" (
  echo ERROR: vchord.dll not found at %BUILD%\pkglibdir\vchord.dll
  echo Run the build first via step-build2.cmd
  exit /b 1
)

echo == Installing vchord into PostgreSQL 17 ==
echo   DLL:        %PG_LIB%\vchord.dll
echo   Extension:  %PG_SHARE%\vchord--0.0.0.sql + vchord.control
echo.

copy /Y "%BUILD%\pkglibdir\vchord.dll" "%PG_LIB%\vchord.dll" || (echo Copy DLL failed && exit /b 1)
copy /Y "%BUILD%\sharedir\extension\vchord--0.0.0.sql" "%PG_SHARE%\vchord--0.0.0.sql" || (echo Copy SQL failed && exit /b 1)
copy /Y "%BUILD%\sharedir\extension\vchord.control" "%PG_SHARE%\vchord.control" || (echo Copy control failed && exit /b 1)

echo.
echo == Files installed. ==
echo.
echo Next steps:
echo   1. Add to postgresql.conf:   shared_preload_libraries = 'vchord.so'
echo      ^(yes, .so on Windows too — pgrx convention; the loader is suffix-tolerant^)
echo      Or leave as 'vector,vchord' if combining with pgvector.
echo   2. Restart PostgreSQL service:  net stop postgresql-x64-17 ^&^& net start postgresql-x64-17
echo   3. In psql:  CREATE EXTENSION vchord CASCADE;
echo.
endlocal
