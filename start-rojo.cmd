@echo off
rem Startet den Rojo-Server fuer Wobble Scoops. Per Doppelklick oder aus jedem beliebigen Ordner aufrufbar.
rem Rokit findet "rojo" nur ueber die rokit.toml im Projektordner (oder einem Ordner darueber).
rem Deshalb wechselt dieses Skript zuerst in den Ordner, in dem es selbst liegt.
setlocal
cd /d "%~dp0"

where rokit >nul 2>nul
if errorlevel 1 (
    echo Rokit wurde nicht gefunden.
    echo Einmalig in PowerShell installieren:
    echo   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 ^| Invoke-Expression
    echo Danach dieses Fenster schliessen und das Skript erneut starten.
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

echo.
echo Rojo-Server startet. Dieses Fenster offen lassen.
echo In Roblox Studio: Plugins ^> Rojo ^> Connect. Beenden mit Strg+C.
echo.
rojo serve default.project.json
pause
