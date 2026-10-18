@echo off
rem Startet den Rojo-Server fuer Wobble Scoops. Per Doppelklick oder aus jedem beliebigen Ordner aufrufbar.
rem Rokit findet "rojo" nur ueber die rokit.toml im Projektordner (oder einem Ordner darueber).
rem Deshalb wechselt dieses Skript zuerst in den Ordner, in dem es selbst liegt.
rem Es aendert keine Projektdateien und nichts in Studio: Was Rojo in Studio schreibt, zeigt das Plugin
rem beim Verbinden zur Bestaetigung an (siehe docs\live-sync.md).
setlocal
title Rojo - Wobble Scoops

rem pushd statt cd, damit es auch auf Netzlaufwerken klappt
pushd "%~dp0" || goto norepo
if not exist "rokit.toml" goto norepo
if not exist "default.project.json" goto norepo

rem Rokit traegt sich bei der Installation nur in die Registry ein. Per Doppelklick gestartete Fenster
rem sehen das erst nach dem naechsten Anmelden, deshalb den Rokit-Ordner hier selbst voranstellen.
set "ROKIT_BIN=%USERPROFILE%\.rokit\bin"
if defined ROKIT_ROOT set "ROKIT_BIN=%ROKIT_ROOT%\bin"
if exist "%ROKIT_BIN%\rokit.exe" set "PATH=%ROKIT_BIN%;%PATH%"

where rokit >nul 2>nul
if errorlevel 1 (
    echo Rokit wurde nicht gefunden.
    echo Einmalig in PowerShell installieren:
    echo   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 ^| Invoke-Expression
    echo Danach dieses Skript erneut starten.
    pause
    exit /b 1
)

rem Die vier Tools aus rokit.toml als vertrauenswuerdig markieren, damit "rokit install" nicht nachfragt.
rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
rem Installiert nur, was fehlt. Bereits installierte Tools werden uebersprungen.
rokit install
if errorlevel 1 (
    echo.
    echo "rokit install" ist fehlgeschlagen, siehe Meldung oben.
    pause
    exit /b 1
)

set "ROJO_VERSION="
for /f "tokens=2" %%v in ('rojo --version') do set "ROJO_VERSION=%%v"
if not defined ROJO_VERSION (
    echo Rojo laesst sich nicht starten, siehe Meldung oben.
    pause
    exit /b 1
)
echo.
rokit --version
echo Rojo %ROJO_VERSION% (Version aus rokit.toml)

rem Laeuft schon ein Rojo-Server, meist in einem zweiten Fenster? Dann keinen weiteren starten.
rem PowerShell statt netstat, weil netstat den Status je nach Windows-Sprache anders schreibt.
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 34872 -State Listen -ErrorAction SilentlyContinue) { exit 3 }" >nul 2>nul
if errorlevel 3 if not errorlevel 4 (
    echo.
    echo Auf Port 34872 laeuft schon ein Rojo-Server, vermutlich in einem anderen Fenster.
    echo Dieses andere Fenster weiter benutzen oder dort mit Strg+C beenden und dieses Skript neu starten.
    echo Kein solches Fenster offen? Im Task-Manager rojo.exe beenden und dieses Skript neu starten.
    pause
    exit /b 1
)

rem Das Studio-Plugin muss zur Rojo-Version passen. Es wird nur installiert, wenn es fehlt oder die Version
rem aus rokit.toml sich geaendert hat; ein laufendes Studio bleibt sonst unberuehrt.
set "PLUGIN_FILE=%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm"
set "PLUGIN_MARK=.rojo-plugin-version"
set "PLUGIN_INSTALLED="
if exist "%PLUGIN_FILE%" if exist "%PLUGIN_MARK%" set /p PLUGIN_INSTALLED=<"%PLUGIN_MARK%"
if not "%PLUGIN_INSTALLED%"=="%ROJO_VERSION%" (
    rojo plugin install
    if errorlevel 1 (
        echo Das Rojo-Plugin liess sich nicht installieren, siehe Meldung oben. Der Server startet trotzdem.
    ) else (
        >"%PLUGIN_MARK%" echo %ROJO_VERSION%
        echo Rojo-Plugin %ROJO_VERSION% installiert. Falls Roblox Studio schon offen ist: einmal neu starten.
    )
)

echo.
echo Rojo-Server startet. Dieses Fenster offen lassen, solange du entwickelst.
echo In Roblox Studio: Plugins ^> Rojo ^> Connect. Beim ersten Verbinden die Aenderungen pruefen, dann Accept.
echo Aenderungen aus einer Cloud-Session holst du mit "git pull" in diesem Ordner, Rojo uebernimmt sie sofort.
echo Beenden mit Strg+C.
echo.
rojo serve default.project.json
pause
popd
exit /b 0

:norepo
echo rokit.toml oder default.project.json wurde in "%~dp0" nicht gefunden.
echo Dieses Skript muss im geklonten Projektordner liegen, nicht in einer ZIP-Datei oder einer einzelnen Kopie.
pause
exit /b 1
