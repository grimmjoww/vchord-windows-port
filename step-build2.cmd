@echo off
cd /d G:\projects\vchord-windows-port\vchord
set "PG_CONFIG=C:\Program Files\PostgreSQL\17\bin\pg_config.exe"
call "G:\projects\vchord-windows-port\with-vc-env.cmd" cargo run -p xtask --release -- build
