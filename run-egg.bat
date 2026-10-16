@echo off
cd /d "%~dp0"
rem 2026-10-16: the game from the whole ending (was the egg alone, 2026-10-14): the objects thrown off, eight snakes
rem gathered round the egg, they coil, the camera comes down, his walk to his spot, the raise, the blast, his fall,
rem the egg (it opens about 36 s in); the site unlock's sounds still play as it opens (port/unlock_snd.lua), to tune
rem them with TAB like the rest. LICH_START=EGG is still there for the egg alone.
set LICH_START=ENDING
"%~dp0..\Anchor\engine\engine\build\anchor.exe" .
