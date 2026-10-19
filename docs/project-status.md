# Projektstatus Wobble Scoops

Stand: 18.10.2026, Branch `claude/wobble-scoops-week1` bei `69aaffb`. Geprüft wurde der Quellcode in einer Cloud-Session. Dein lokaler Ordner `C:\Users\beszt\roblox` kann davon abweichen (`git pull`).

## Was wirklich geprüft ist

| Bereich | Status |
|---|---|
| Lune-Checks (StyLua, Selene, 64 Unit-Tests, Rojo-Build, Place-Check) | grün bei `69aaffb`, in der Cloud |
| Rojo-Server und Datei-Sync | `rojo serve` 7.7.1 in der Cloud getestet, Änderungen kommen nach 0,05 s an. Echtes Studio-Plugin unter Windows: **nicht getestet** |
| Studio-MCP | **nie verbunden.** Cloud-Sessions erreichen deinen PC nicht |
| Playtest in Studio, Handy, Mehrspieler | **nie ausgeführt.** Gameplay-Feel, HUD-Layout und Steuerung sind nur per Code und Simulation geprüft |

## Vorhandene Systeme

| System | Stand | Dateien |
|---|---|---|
| Launcher (Big Swirl) | schießt automatisch in angekündigte Landekreise, 3 Tutorial-Schüsse auf den Spieler | `src/server/Services/LauncherService.luau`, `src/shared/Config/Launcher.luau`, `src/client/Controllers/ShotRenderer.luau` |
| Fangen | automatisch; Kontakt mit der ganzen Turmsäule, Server prüft Zeitpunkt, Position und Neigung. Die Fangsäule steht direkt über der Figur (`catchUp`/`catchForward`), nicht am sichtbaren Turm auf dem Rücken: Mit der Säule auf dem Rücken fielen 8 Fang-Tests durch (Kugeln landen vor einem Turm hinter dem Spieler) | `src/shared/CatchRules.luau`, `src/shared/ShotMath.luau` |
| Stapeln und Turmphysik | invertiertes Pendel (60 Hz, Client), Ächzen 0,5 s, dann Kippen; beim Kippen bleiben 30 % (mind. 2) | `src/shared/TowerModel.luau`, `src/shared/TowerShape.luau`, `src/client/Controllers/TowerController.luau`, `src/client/TowerVisual.luau`, `src/shared/Config/Tower.luau` |
| Kampfmodus | R / Y / *Combat* schaltet um; nur darin Fadenkreuz, Wurf-Button, gefangene Maus (jeden Frame nach der Kamera erzwungen) und eigene Schulterkamera (`CombatCamera`: Maus/rechter Stick drehen direkt, Figur links vom Fadenkreuz; Handy: Roblox-Kamera über die Schulter verschoben). Nach dem ersten Studio-Test: Standard-Kamera drehte nicht mit der gefangenen Maus und zielte auf den Kopf, daher die eigene Kamera; Shift-Lock (Strg) solange gesperrt, Mauszustand beim Verlassen wiederhergestellt. Server: `SetCombatMode` (Typ, Rate-Limit fürs Einschalten), Attribut `CombatMode`, Laden/Werfen nur im Modus, aus nach Respawn und Knockdown. Kugel in der Hand für alle sichtbar (`HeldBalls`, Ploppen, Frost beim Nachladen). Wurf kostet nur Munition, nie einen Scoop. **Schulterkamera nicht in Studio geprüft** | `CombatController.luau`, `AimHud.luau`, `HeldBalls.luau`, `CombatService.luau`, `Config/Combat.luau` (`combatModeInterval`, `held`) |
| Eisball-Wurf (Combat-Schritt 1) | im Kampfmodus: linke Maustaste / Throw / R2 halten lädt, loslassen wirft; Ball aus der rechten Hand durch den Punkt unter dem Fadenkreuz (Bogen per Ballistik, außer Reichweite gerade mit Lift). Ladeleiste unter dem Fadenkreuz (auf und ab, 0,45 s je Richtung, 0,08 s Server-Toleranz), Ladung bestimmt Tempo 55–90 und Trefferfaktor 0,6–1; der Server misst die Haltedauer selbst (`ChargeIceBall`) und begrenzt den Ladewert darauf (`Combat.validateCharge`). 3 Würfe pro Ladung, 7 s Nachladen, Server simuliert Flug, prüft Treffer (Kapsel um den Spieler, Welt per Raycast), Trefferstärke nach Volltreffer und Geschwindigkeit, Knockdown erst ab zwei kräftigen Treffern kurz hintereinander. Kein Block, kein Konter, keine Sorten-Unterschiede. **Nur in Lune getestet** | `src/shared/Combat.luau`, `Config/Combat.luau`, `src/server/Services/CombatService.luau`, `src/client/Controllers/CombatController.luau`, `src/client/Controllers/AimHud.luau`, `TowerModel.hitKick`, `Hud.luau` |
| Waffel-Rucksack und Turm | Eiswaffel auf dem Rücken jeder Figur, der Scoop-Turm stapelt sich sichtbar darin (`holdUp` -0,1, `holdForward` -1,75, eigener Turm-Kegel ausgeblendet); eigener Turm wird halb durchsichtig, wenn er die Bildmitte verdeckt; **keine** Munitionsanzeige; folgt dem Oberkörper, beim Knockdown ausgeblendet, beim Heranzoomen blendet die eigene aus. Geometrie per Skript gegen R15-Standardmaße gerechnet. **Nicht in Studio gesehen** | `src/client/Controllers/Backpacks.luau`, `src/shared/Config/Backpack.luau`, `TowerVisual.makePart` |
| Bewegungsoptik | prozedurale Neigung (Laufen, Kurven), Stumble bei Treffern, Knockdown-Pose mit Eingabesperre statt PlatformStand, Landestaub und Kamera-Wackler, Dash-Spur und FOV-Kick; Platzhalter für eigene Animation-IDs (noch keine Assets). **Nicht in Studio geprüft, Neigungsrichtungen ungesehen** | `src/client/Controllers/MovementController.luau`, `src/shared/Config/Movement.luau` |
| Sprint | Shift halten (Handy: *Sprint*-Button, Gamepad: L3, beide an/aus), Tempo × 1,3 vom Server gesetzt (`sprintMultiplier`), auch mit Turm; stärkere Neigung und etwas weiteres Sichtfeld. Shift-Lock auf Strg verlegt (über `MouseLockController.BoundKeys`). **Nicht in Studio geprüft, ob die Shift-Lock-Umlegung greift** | `Economy.walkSpeed`, `TowerService.luau` (`onSprint`), `TowerController.luau`, `MovementController.luau`, `Config/Movement.luau` |
| Springen und Dash | Springen (Leertaste) mit `jumpPower` 40; Dash mit Q oder Touch-Button: 0,125 s mit 80 Studs/s (10 Studs, Beschleunigung bis 6000 Studs/s², Ende auf den nächstgelegenen Frame statt immer einen Frame zu spät), am Ende harter Stopp aufs eigene Lauf-/Sprinttempo (außer während eines Knockbacks), Cooldown 4 s auf dem Server geprüft, Turm-Kick plus 0,6 s geschwächte Korrektur. **Nur in Lune getestet, nicht in Studio** | `src/server/Services/CartService.luau`, `TowerService.luau` (`onDash`), `TowerController.luau`, `TowerModel.dashKick`, `Config/Tower.luau` (`dash`) |
| Balancieren | automatische Grundstabilisierung (`TowerModel.assist`), Rettung mit F / Steady (1,5 s, 6 s Abklingzeit, Server prüft); I/J/K/L, Pad und Handysensor entfernt. **Nur in Lune getestet** | `src/shared/TowerModel.luau`, `Config/Tower.luau` (`assist`, `rescue`), `TowerController.luau`, `TowerService.luau` (`onRescue`), `Hud.luau` |
| Turmwert, Multiplikator, Sichern | Wert = Summe × (1 + 0,04 × Kugeln)², Steady-Bonus bis +25 %, Wagen-Multiplikator; Sichern = Servieren am eigenen Wagen | `src/shared/Economy.luau`, `src/shared/Config/Economy.luau`, `src/server/Services/TowerService.luau`, `src/server/Services/CartService.luau` |
| Coins | nur für die Sitzung (leaderstats), kein Speichern | `TowerService.luau` |
| Mehrspieler | Server ist die Wahrheit, Neigung fremder Türme repliziert, ein Wagen pro Spieler | `src/client/Controllers/RemoteTowers.luau`, `TowerService.luau` |
| HUD | Coins, Turm-Karte, ein Hinweis, Balance-Anzeige, Meldungen, Wagen-Markierung | `src/client/Controllers/Hud.luau`, `src/client/Ui.luau` |
| Map | Graybox-Pier, falls `Workspace.Pier` fehlt (die Map ist nicht in Rojo gemappt) | `src/server/Services/GrayboxService.luau` |
| Kill-Test-Log | Serves und Stürze pro Steuerung | `src/server/Services/KillTestLog.luau` |

## Bestätigte Bugs und Risiken (aus dem Code)

1. **Steady-Bonus ohne Mindesthöhe auf dem Server:** Der Client zählt Steady erst ab 10 Kugeln, der Server begrenzt nur über die Tragezeit (`TowerService.luau`, `steadyCap`). Ein manipulierter Client bekommt den Bonus auch bei kleinen Türmen. Kleiner Exploit.
2. **`debugCatch = true` und `debugThrow = true`** in `src/shared/Config/Features.luau`: vorübergehende Diagnose-Ausgaben, nach dem Studio-Test und vor Tests mit fremden Spielern ausschalten.
3. **Upgrades ohne Kaufweg:** Kosten und Stufen stehen in `Config/Economy.luau`, die Stufen im Server-State bleiben aber immer 0.

## Fehlende Features (nach deiner Prioritätenliste)

| Phase | Fehlt |
|---|---|
| 1 Stabilisieren | ein echter Playtest in Studio (siehe nächster Schritt) |
| 2 Wert, Multiplikator, Kippen, Sichern | im Code vorhanden; ungetestet |
| 3 Coins, Fortschritt, Upgrades | Speichern (DataStore), Upgrade-Kauf/Shop, Sammelbuch der Sorten |
| 4 Ball Shot | nicht vorhanden (vorgesehenes Rempeln `bump` ist aus und nicht gebaut) |
| 5 Bird Bait | nicht vorhanden (Möwe Greg, Flag `greg` aus, nicht gebaut) |
| 6 Events | nicht vorhanden |
| 7 Polish | Platzhalter-Sounds, keine Effekte außer Pfützen und Ächzen |

Das „Gameplay Blueprint v1.0“ liegt nicht im Repo. Design-Referenz ist bisher `docs/concept.md`.

## Nächster Schritt

**Ein manueller Playtest der Kernschleife in Studio (ca. 15 Minuten), Ergebnisse hier eintragen.** Ohne diesen Test ist Phase 1 nicht abschließbar.

1. `git pull --ff-only`, `start-rojo.cmd`, in Studio *Connect* → *Accept*.
2. F5: Kugeln im Landekreis fangen (0, 5, 10 Kugeln). In der Ausgabe auf Fehler und `[Catch] rejected` achten.
3. Turm auf dem Rücken: Kugeln fangen, einmal mit Blick zur Maschine und einmal mit dem Rücken zur Maschine (beides muss klappen, in der Ausgabe keine `[Catch] rejected`). Steht der Turm sichtbar in der Waffel, ohne Lücke und ohne in Kopf oder Rücken zu stecken, auch beim Sprinten (Oberkörper lehnt vor)? Verdeckt der Turm in der normalen Kamera den Kopf, wird er halb durchsichtig; im Kampfmodus (R) mit 10+ Kugeln: bleibt das Fadenkreuz frei? Fremde Türme (2 Spieler) stehen ebenfalls auf dem Rücken. Kippen: Kugeln fallen vom Rücken herunter.
4. Mit 12+ Kugeln laufen: Warnpuls an der Wasserwaage, F rettet, F in der Abklingzeit tut nichts.
5. Zum Wagen tragen: Wird serviert, steigen die Coins, kippt der Turm sauber?
6. Sprint mit Shift (schneller, Sichtfeld weiter), Dash mit Q (kurz und knackig, kein Nachrutschen, kein Ruckeln am Anfang oder Ende; frontal gegen eine Wand und einen Pfosten dashen: muss abprallen bzw. anhalten, nie hindurch; mehrmals gleiche Strecke abmessen; auch aus dem Sprint, im Sprung, von einer Kante herunter, mit 10+ Kugeln und direkt nach einem Treffer probieren; mit Incoming Replication Lag 0,2 s prüfen, ob andere Spieler den Dash ohne Sprung sehen), Sprung mit Leertaste, Shift-Lock mit Strg (muss in den Roblox-Einstellungen an sein).
7. Kampfmodus: R drücken. Die Kamera springt über die rechte Schulter, die Figur steht links vom Fadenkreuz (nicht mehr dahinter). **Maus bewegen dreht die Kamera** flüssig nach links/rechts und oben/unten (oben und unten begrenzt), ohne Rechtsklick. An einer Wand rückt die Kamera heran statt hindurchzusehen. Kugel in der rechten Hand? Strg tut nichts. Laufen mit WASD geht relativ zur Kamera. Sprint (Shift), Dash (Q), Sprung im Kampfmodus. R nochmal: normale Roblox-Kamera schaut in dieselbe Richtung weiter, Maus frei, Linksklick wirft nicht. Mit vorher aktivem Shift-Lock (Strg an, R an, R aus): Shift-Lock danach noch aktiv. Im Kampfmodus Reset/Tod und Respawn: Kampfmodus aus, normale Kamera, Maus frei. **Maus-Fix prüfen:** Nach R aus muss der Cursor sichtbar und frei beweglich sein, sofort und auch 2 Sekunden später; ebenso nach Alt+Tab bzw. Klick in ein anderes Studio-Fenster (beendet den Kampfmodus), nach Knockdown und nach Tod. Shift-Lock (Strg) danach an und wieder aus: Maus wieder frei. Rechte Maustaste halten im normalen Modus dreht die Kamera weiterhin wie gewohnt.
8. Werfen (im Kampfmodus), mit offener Ausgabe (`Features.debugThrow` ist für diesen Test an): Auf eine Wand oder den Boden in 20 bis 40 Studs zielen, Linksklick halten, loslassen. **Sichtbar fliegt ein Eisball mit weißer Spur aus der rechten Hand zum Fadenkreuz.** In der Ausgabe stehen pro Wurf: `[Throw] release` (Client: Ladung, Zielpunkt, Abstand), `[Throw] <Name> throws` (Server: angenommene Ladung, Tempo, Start, Ziel), `#n thrown from` (Client: Ball angekommen), dann `#n hit the world ... : <Teil>` oder `hit <Spieler>` (Server) und `#n ended` (Client). **Wenn wieder kein Ball zu sehen ist: diese Zeilen kopieren.** Fliegt der Ball nur ein Stück und `hit the world` nennt ein unerwartetes Teil, ist das die Ursache. `rejected ...` nennt den Grund einer Ablehnung. Die Leiste läuft auf und ab (0,45 s pro Richtung: lässt sich das Maximum gezielt treffen?), voller Wurf sichtbar schneller und weiter. Nach jedem Wurf ploppt die nächste Kugel in die Hand, nach dem dritten wächst dort eine Frost-Kugel. Knockdown: Kampfmodus geht aus, Kamera und Maus normal. Leer werfen, Taste halten: Nach 7 s startet die Leiste von selbst. Danach `debugThrow` in `src/shared/Config/Features.luau` wieder auf `false`.
9. Test → *Clients and Servers* mit 2 Spielern: Fremde Türme wackeln, Fänge zählen nur am eigenen Turm, die Kugel in der Hand des anderen ist nur in dessen Kampfmodus zu sehen.
10. Optional: Handy über privat veröffentlichten Place, Neigerichtung prüfen, *Combat*-Button, dann *Throw* halten und loslassen.
