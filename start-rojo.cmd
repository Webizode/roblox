@echo off
rem Startet den Rojo-Server fuer Wobble Scoops. Per Doppelklick oder aus jedem beliebigen Ordner aufrufbar.
rem Rokit findet "rojo" nur ueber die rokit.toml im Projektordner (oder einem Ordner darueber).
rem Deshalb wechselt dieses Skript zuerst in den Ordner, in dem es selbst liegt.
setlocal

rem pushd statt cd, damit es auch auf Netzlaufwerken klappt
pushd "%~dp0" || goto norepo
if not exist "rokit.toml" goto norepo

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

rem Das Rojo-Plugin fuer Roblox Studio einmalig installieren. Ein Fehler hier haelt den Server nicht auf.
if not exist "%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm" (
    rojo plugin install
    echo Falls Roblox Studio schon offen ist: einmal neu starten, damit der Rojo-Button erscheint.
)

echo.
echo Rojo-Server startet. Dieses Fenster offen lassen.
echo In Roblox Studio: Plugins ^> Rojo ^> Connect. Beenden mit Strg+C.
echo.
rojo serve default.project.json
pause
popd
exit /b 0

:norepo
echo rokit.toml wurde in "%~dp0" nicht gefunden.
echo Dieses Skript muss im geklonten Projektordner liegen, nicht in einer ZIP-Datei oder einer einzelnen Kopie.
pause
exit /b 1
