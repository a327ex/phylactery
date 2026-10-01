@echo off
:: The engine exactly as build.bat builds it, linked to build\anchor-port.exe instead of
:: build\anchor.exe: another session's agent instance holding anchor.exe (LNK1104) never
:: blocks the port's builds. Drive it with: set ANCHOR_ENGINE_BIN=...\build\anchor-port.exe
setlocal
cd /d "%~dp0..\..\Anchor\engine\engine"
if exist "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1
) else (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1
)
if not exist build\port_obj mkdir build\port_obj
cl.exe /nologo /O2 /W3 ^
    /I"include" /I"include/SDL2" /I"include/lua" /I"include/glad" /I"include/KHR" /I"include/stb" /I"include/box2d" /I"include/box3d" /I"include/freetype" ^
    src/anchor.c include/glad/gl.c ^
    /Fe"build/anchor-port.exe" /Fo"build/port_obj/" ^
    /link /LIBPATH:"lib" ^
    lua.lib box2d.lib box3d.lib freetype.lib SDL2-static.lib SDL2main.lib ^
    avformat.lib avcodec.lib avutil.lib swscale.lib swresample.lib avfilter.lib ^
    opengl32.lib kernel32.lib user32.lib gdi32.lib winmm.lib imm32.lib ^
    ole32.lib oleaut32.lib version.lib uuid.lib advapi32.lib setupapi.lib shell32.lib winhttp.lib ^
    /SUBSYSTEM:CONSOLE > build\port_build.log 2>&1
if %ERRORLEVEL% neq 0 (
    findstr /C:" error " /C:"fatal error" build\port_build.log
    echo Build failed!
    exit /b 1
)
echo Build successful: build\anchor-port.exe
