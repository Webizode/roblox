# Wobble Scoops

Roblox-Spiel: Eiskugeln fangen, einen wackelnden Turm mit dem Daumen balancieren und ihn zum eigenen Eiswagen tragen, bevor er kippt. Volles Konzept in [`docs/concept.md`](docs/concept.md), der Kill-Test für Woche 1 in [`docs/killtest.md`](docs/killtest.md).

**Stand:** Woche 1, Feel-Prototyp. Big Swirl schießt Kugeln, Fangen, Wackelturm mit automatischer Grundstabilisierung und Rettung (F / Steady), Springen und Dash, Servieren am Wagen, Coins, Kill-Test-Log. Rempeln, Greg, Golden Scoops, Speichern und Shop kommen ab Woche 2.

## Setup auf Windows (einmalig, ca. 1 Abend)

1. **Roblox Studio** installieren und einloggen: <https://create.roblox.com>
2. **Claude Code** installieren (Desktop-App oder CLI).
3. **Studio-MCP verbinden:** In Studio *Assistant* öffnen → `…` → *Manage MCP Servers* → *Enable Studio as MCP server* einschalten → unter *Quick connect* Claude Code aktivieren → Studio und Claude neu starten. Der grüne Punkt in *Manage MCP Servers* zeigt die Verbindung.
   Für Claude Code ist das schon im Repo eingerichtet: `.mcp.json` enthält die Studio-Konfiguration. Startest du Claude Code im Repo-Ordner, fragt es einmal, ob es den Server `Roblox_Studio` nutzen darf, dann zustimmen.
   Fallback per CLI (der Befehl, den Studio für Claude Code anzeigt, mit `--scope user`, damit er in jedem Ordner gilt):
   `claude mcp add --scope user --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"`
4. **Git** installieren und das Repo nach `C:\Users\<Name>\roblox` klonen (normale PowerShell, nicht die ISE, nicht als Administrator). Ein anderer Ordner geht auch, dann die Pfade unten anpassen; OneDrive-Ordner meiden:
   ```powershell
   cd $HOME
   git clone -b claude/wobble-scoops-week1 https://github.com/Webizode/roblox.git roblox
   ```
5. **Rokit** (Toolchain-Manager) in PowerShell installieren:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
6. Im selben Fenster weiter, **im Repo-Ordner**:
   ```powershell
   $env:Path = "$HOME\.rokit\bin;$env:Path"   # Rokit sofort nutzbar, ohne neu anzumelden
   cd $HOME\roblox
   rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
   rokit install          # Rojo, StyLua, Selene, Lune in den Versionen aus rokit.toml
   rojo plugin install    # Rojo-Plugin für Studio
   ```

## Spielen und testen

**Rojo starten:** im Repo-Ordner `start-rojo.cmd` doppelklicken. Das Skript wechselt selbst in den richtigen Ordner, zeigt die Rokit- und Rojo-Version, installiert fehlende Tools und das passende Studio-Plugin, verhindert einen zweiten Server und startet `rojo serve default.project.json`. Oder in einer normalen PowerShell (nicht in der ISE):

```powershell
cd $HOME\roblox
rojo serve default.project.json
```

Das Fenster offen lassen. In Studio den Place öffnen (beim ersten Mal eine neue *Baseplate*) → Plugins → Rojo → *Connect*, die angezeigten Änderungen prüfen, *Accept*. Dann **Play (F5)**: Der Server baut beim Start automatisch einen Graybox-Pier, wenn im Place noch keiner existiert.

**Live-Sync:** Jede gespeicherte Datei unter `src/` ist sofort in Studio. Einstellungen, Grenzen bei laufendem Playtest (nach Codeänderungen Stop + F5) und Fehlerbehebung: [`docs/live-sync.md`](docs/live-sync.md). Änderungen aus Cloud-Sessions holst du mit `git pull --ff-only` im Repo-Ordner, Rojo übernimmt sie ohne Neustart.

- **Mehrspieler:** Test → *Clients and Servers* → 2–3 Spieler → Start.
- **Handy:** Test → *Device* (Emulator) und echtes Handy über eine privat veröffentlichte Version (File → Publish to Roblox).
- **Latenz:** Studio-Einstellungen → Network → *Incoming Replication Lag* auf 0,2 s, so fühlt sich ein typisches Handy an.
- **Steuerung:**
  - **PC:** WASD laufen, Maus Kamera, Leertaste springen, **Shift halten sprinten** (1,3-faches Tempo, auch mit Turm, der dann schneller ins Wanken kommt), **Q Dash** (4 s Abklingzeit), **Strg Shift-Lock** (statt Shift, falls in den Roblox-Einstellungen aktiviert), **F Rettung**, **linke Maustaste halten = Wurf aufladen, loslassen = werfen**. Gamepad: L3 Sprint an/aus, R2 halten/loslassen.
  - **Handy:** Joystick, Sprung-Button, Buttons *Sprint* (an/aus), *Dash*, *Steady* (Rettung) und *Throw* (halten zum Aufladen, loslassen wirft).
  - **Eisball-Wurf** (einzige Angriffsaktion): Der Ball startet aus der rechten Hand und fliegt auf einem Bogen durch den Punkt unter dem Fadenkreuz (Bildmitte). Wurftaste halten lädt die Leiste unter dem Fadenkreuz: Sie läuft in 0,9 s von schwach (mint) zu stark (rot), danach wieder herunter und so weiter, solange du hältst; am rechten Ende leuchtet der Maximalpunkt. Loslassen wirft mit dem aktuellen Stand: mehr Ladung = schneller (55 bis 90 Studs/s, also auch weiter) und stärker im Treffer und Rückstoß (Faktor 0,6 bis 1). Ein kurzer Tipp wirft schwach. Ziele außer Reichweite verfehlt der Ball, er fällt vorher herunter. Der Server misst die Haltedauer selbst und nimmt nur einen Ladewert an, der dazu passt (0,1 s Toleranz für Netzwerk-Schwankungen). 3 Würfe pro Ladung, jeder Wurf kostet einen (auch daneben); sind alle 3 weg, füllt sich die Ladung nach 7 s wieder komplett. Ein Treffer stößt den Spieler kontrolliert zurück und schubst seinen Turm in Flugrichtung (Volltreffer stärker als Streifschüsse). Ein einzelner Treffer wirft nie um; erst zwei kräftige, gut aufgeladene Treffer kurz hintereinander lösen einen Knockdown aus (ungeladene Würfe schaffen das auch dreifach nicht) (1,5 s am Boden, in der Zeit keine weiteren Treffer). Munition, Flug, Treffer und Knockdown entscheidet der Server.
  - **Waffel-Rucksack** (`Backpacks`, Werte in `Config/Backpack.luau`): Jede Figur trägt eine Eiswaffel auf dem Rücken, in der die geladenen Eisbälle liegen (3 als kleine Pyramide). Ein Wurf lässt den obersten Ball herausploppen; ist die Ladung leer, wachsen während des Nachladens durchsichtige Frost-Bälle in der Waffel, danach ploppen alle 3 nacheinander wieder rein. So sieht jeder auf einen Blick, wer noch Munition hat. Nur Optik, die Munition zählt der Server.
  - **Balance:** Ein eingebauter Stabilisator gleicht kleine Schwankungen von selbst aus. Er reagiert etwas verzögert, gibt bei starker Neigung auf und wird mit der Turmhöhe schwächer. Bis etwa 10 Kugeln musst du nichts tun, darüber machen Laufen, Richtungswechsel und Dash den Turm gefährlich. Im Stand fällt kein Turm bis 20 Kugeln von selbst.
  - **Rettung (F / Steady):** 1,5 s volle Gegenkraft gegen die tatsächliche Neigung, danach 6 s Abklingzeit. Ein Druck ist eine Rettung, Halten verlängert nichts. Zu spät (Turm ächzt schon nahe am Kippwinkel, vor allem mit Schwung) kann sie scheitern.
  - I/J/K/L haben keine Funktion mehr; I/O zoomen wieder die Kamera wie im Roblox-Standard.
- **Bewegungsgefühl** (`MovementController`, Werte in `Config/Movement.luau`): Figuren lehnen sich beim Laufen nach vorn und in Kurven, taumeln bei Treffern weg vom Ball und legen sich beim Knockdown hin (Eingabe gesperrt, der Turm bleibt stehen). Landungen nach längerem Flug geben Staub und einen kleinen Kamera-Wackler, der Dash eine gelbe Spur und einen kurzen Sichtfeld-Kick. Eigene Animationen (Idle, Walk, Run, Jump, Fall) lassen sich dort per ID eintragen; leer bleibt der Roblox-Standard. Beim Sprinten lehnt sich die Figur stärker vor und das Sichtfeld wird etwas weiter. Tempo, Sprungkraft und Dash-Weite ändert nichts davon (das Sprint-Tempo setzt der Server, `sprintMultiplier` in `Config/Economy.luau`).
- **HUD:** Coins und Eisball-Ladung (3 Kugeln, beim Nachladen ein Countdown) links, Turm-Karte (Kugeln, Wert, Steady-Bonus) unten Mitte mit höchstens einem Hinweis darüber, Balance-Anzeige mit Wasserwaage rechts (am PC unten rechts, am Handy über dem Sprung-Button), solange du einen Turm trägst. Der Punkt zeigt die Neigungsrichtung aus Kamerasicht (oben = von dir weg). Ab 60 % Neigung pulsiert der Rand rot und darüber steht „Press F to steady it“ bzw. „Tap Steady“; während einer Rettung leuchtet er mint, in der Abklingzeit ist er blass. Es gibt keine Wurf- oder Fang-Buttons: Die Big Swirl schießt von selbst, gefangen und serviert wird automatisch.
- **Fangen:** Eine Kugel zählt, sobald sie den Turm irgendwo berührt, nicht nur die Spitze. Servieren passiert automatisch, wenn du mit dem Turm von draußen auf die gelbe Matte am eigenen Wagen läufst.
- **Kill-Test-Daten:** Die Ausgabe zeigt alle 2 Minuten `[KillTest] summary`, die Rohdaten liegen als JSON in `ServerStorage.KillTestLog`.
- **Fang-Diagnose:** Solange `debugCatch` in `src/shared/Config/Features.luau` an ist, schreibt der Server jeden abgelehnten Fang mit Grund in die Ausgabe (`[Catch] rejected …`).

## Probleme beim Start

| Meldung | Ursache | Lösung |
|---|---|---|
| `Failed to find tool 'rojo' in any project manifest file` | Rokit sucht `rokit.toml` nur im aktuellen Ordner und den Ordnern darüber. Das Fenster steht nicht im Repo-Ordner (neue PowerShell startet in `C:\Users\<Name>`, als Admin in `C:\WINDOWS\system32`). | `cd $HOME\roblox`, dann erneut. Oder `start-rojo.cmd` doppelklicken. |
| `Installed and created links for 0 tools` | `rokit install` lief außerhalb des Repo-Ordners. | Im Repo-Ordner wiederholen. |
| `The following tool has not been marked as trusted` | Die Vertrauens-Abfrage von `rokit install` funktioniert nicht in der PowerShell ISE. | `rokit trust …` aus Setup-Schritt 6 ausführen, dann `rokit install`. |
| `rokit` wird nicht erkannt | Rokit trägt sich bei der Installation nur in die Registry ein. Neue Fenster sehen das erst nach dem nächsten Anmelden. | Im Fenster `$env:Path = "$HOME\.rokit\bin;$env:Path"` ausführen, oder `start-rojo.cmd` doppelklicken (das macht es selbst). Fehlt Rokit ganz: Setup-Schritt 5. |
| `rokit` geht, aber `rojo` wird nicht erkannt | Die Tools wurden noch nicht im Repo-Ordner installiert. | Im Repo-Ordner `rokit install`, oder `start-rojo.cmd` doppelklicken. |
| `Could not start the Rojo server on 127.0.0.1:34872` | Ein anderer Rojo-Server läuft schon (anderes Fenster, oder ein Start aus der ISE ohne sichtbares Fenster). | Das andere Fenster schließen oder im Task-Manager `rojo.exe` beenden. |

**Nicht** `rokit add`, `rokit init` oder `rokit add --global` ausführen, auch wenn Rokit das in einer Meldung vorschlägt: Rojo steht schon in der `rokit.toml` des Repos. Außerhalb des Repos bricht `rokit add` nur ab, und `rokit init` würde dort eine zweite `rokit.toml` anlegen, die das Projekt durcheinanderbringt.

Prüfen, ob du im richtigen Ordner bist: `Test-Path .\rokit.toml` muss `True` ausgeben.

## Checks (vor jedem Push)

```powershell
lune run scripts/check
```

Führt StyLua, Selene, die Lune-Tests, einen Rojo-Build und die Prüfung des gebauten Place aus.

## Struktur

| Pfad | Wird in Roblox zu | Inhalt |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | reine Logik (TowerModel, TowerShape, Economy, Recipes, ShotMath), Remotes, `Config/*` |
| `src/server` | `ServerScriptService.Server` | Services: Graybox, Cart, Tower, Launcher, KillTestLog |
| `src/client` | `StarterPlayerScripts.Client` | TowerVisual, Sfx, Ui (gemeinsamer UI-Stil), Controllers: Hud, TowerController, ShotRenderer, RemoteTowers |
| `tests` | (nur Lune) | Unit-Tests der reinen Logik, Syntax-Check aller Dateien, Place-Check |
| `docs` | | Konzept, Kill-Test, Live-Sync mit Studio |
