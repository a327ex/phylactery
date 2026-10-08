@echo off
cd /d "%~dp0"
rem round 66: the game on the fixed seeds it had before round 65 (every run the same), to compare
set LICH_SEED=fixed
"%~dp0..\Anchor\engine\engine\build\anchor.exe" .
