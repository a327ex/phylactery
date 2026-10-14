@echo off
cd /d "%~dp0"
rem 2026-10-14: the game from its egg (the ending's last beat): the egg opens about 8 s in, and the site unlock's
rem sounds play on the site's schedule (port/unlock_snd.lua), to tune them with TAB like the rest
set LICH_START=EGG
"%~dp0..\Anchor\engine\engine\build\anchor.exe" .
