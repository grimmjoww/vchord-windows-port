@echo off
REM Wrapper: activate VS2022 x64 env + Postgres 17 dev tools + portable LLVM, then run the command passed as args.
REM Usage from bash:  cmd //c "G:\projects\vchord-windows-port\with-vc-env.cmd <your command>"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "PATH=G:\projects\vchord-windows-port\llvm\bin;C:\Program Files\PostgreSQL\17\bin;%PATH%"
set "INCLUDE=C:\Program Files\PostgreSQL\17\include;C:\Program Files\PostgreSQL\17\include\server;%INCLUDE%"
set "LIB=C:\Program Files\PostgreSQL\17\lib;%LIB%"
set "LIBCLANG_PATH=G:\projects\vchord-windows-port\llvm\bin"
%*
