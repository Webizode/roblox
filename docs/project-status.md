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
| Fangen | automatisch; Kontakt mit der ganzen Turmsäule, Server prüft Zeitpunkt, Position und Neigung | `src/shared/CatchRules.luau`, `src/shared/ShotMath.luau` |
| Stapeln und Turmphysik | invertiertes Pendel (60 Hz, Client), Ächzen 0,5 s, dann Kippen; beim Kippen bleiben 30 % (mind. 2) | `src/shared/TowerModel.luau`, `src/shared/TowerShape.luau`, `src/client/Controllers/TowerController.luau`, `src/client/TowerVisual.luau`, `src/shared/Config/Tower.luau` |
| Eisball-Wurf (Combat-Schritt 1) | linke Maustaste / Throw / R2 halten lädt, loslassen wirft; Ball aus der rechten Hand durch den Punkt unter dem Fadenkreuz (Bogen per Ballistik, außer Reichweite gerade mit Lift). Ladeleiste unter dem Fadenkreuz (auf und ab, 0,9 s je Richtung), Ladung bestimmt Tempo 55–90 und Trefferfaktor 0,6–1; der Server misst die Haltedauer selbst (`ChargeIceBall`) und begrenzt den Ladewert darauf (`Combat.validateCharge`). 3 Würfe pro Ladung, 7 s Nachladen, Server simuliert Flug, prüft Treffer (Kapsel um den Spieler, Welt per Raycast), Trefferstärke nach Volltreffer und Geschwindigkeit, Knockdown erst ab zwei kräftigen Treffern kurz hintereinander. Kein Block, kein Konter, keine Sorten-Unterschiede. **Nur in Lune getestet** | `src/shared/Combat.luau`, `Config/Combat.luau`, `src/server/Services/CombatService.luau`, `src/client/Controllers/CombatController.luau`, `src/client/Controllers/AimHud.luau`, `TowerModel.hitKick`, `Hud.luau` |
| Waffel-Rucksack | leere Eiswaffel auf dem Rücken jeder Figur (gehört zum Sammel-/Turm-System, Rolle noch offen, **keine** Munitionsanzeige); folgt dem Oberkörper, beim Knockdown ausgeblendet, beim Heranzoomen blendet die eigene aus. Geometrie per Skript gegen R15-Standardmaße gerechnet. **Nicht in Studio gesehen** | `src/client/Controllers/Backpacks.luau`, `src/shared/Config/Backpack.luau`, `TowerVisual.makePart` |
| Bewegungsoptik | prozedurale Neigung (Laufen, Kurven), Stumble bei Treffern, Knockdown-Pose mit Eingabesperre statt PlatformStand, Landestaub und Kamera-Wackler, Dash-Spur und FOV-Kick; Platzhalter für eigene Animation-IDs (noch keine Assets). **Nicht in Studio geprüft, Neigungsrichtungen ungesehen** | `src/client/Controllers/MovementController.luau`, `src/shared/Config/Movement.luau` |
| Sprint | Shift halten (Handy: *Sprint*-Button, Gamepad: L3, beide an/aus), Tempo × 1,3 vom Server gesetzt (`sprintMultiplier`), auch mit Turm; stärkere Neigung und etwas weiteres Sichtfeld. Shift-Lock auf Strg verlegt (über `MouseLockController.BoundKeys`). **Nicht in Studio geprüft, ob die Shift-Lock-Umlegung greift** | `Economy.walkSpeed`, `TowerService.luau` (`onSprint`), `TowerController.luau`, `MovementController.luau`, `Config/Movement.luau` |
| Springen und Dash | Springen (Leertaste) mit `jumpPower` 40; Dash mit Q oder Touch-Button, Cooldown 4 s auf dem Server geprüft, Turm-Kick plus 0,6 s geschwächte Korrektur. **Nur in Lune getestet, nicht in Studio** | `src/server/Services/CartService.luau`, `TowerService.luau` (`onDash`), `TowerController.luau`, `TowerModel.dashKick`, `Config/Tower.luau` (`dash`) |
| Balancieren | automatische Grundstabilisierung (`TowerModel.assist`), Rettung mit F / Steady (1,5 s, 6 s Abklingzeit, Server prüft); I/J/K/L, Pad und Handysensor entfernt. **Nur in Lune getestet** | `src/shared/TowerModel.luau`, `Config/Tower.luau` (`assist`, `rescue`), `TowerController.luau`, `TowerService.luau` (`onRescue`), `Hud.luau` |
| Turmwert, Multiplikator, Sichern | Wert = Summe × (1 + 0,04 × Kugeln)², Steady-Bonus bis +25 %, Wagen-Multiplikator; Sichern = Servieren am eigenen Wagen | `src/shared/Economy.luau`, `src/shared/Config/Economy.luau`, `src/server/Services/TowerService.luau`, `src/server/Services/CartService.luau` |
| Coins | nur für die Sitzung (leaderstats), kein Speichern | `TowerService.luau` |
| Mehrspieler | Server ist die Wahrheit, Neigung fremder Türme repliziert, ein Wagen pro Spieler | `src/client/Controllers/RemoteTowers.luau`, `TowerService.luau` |
| HUD | Coins, Turm-Karte, ein Hinweis, Balance-Anzeige, Meldungen, Wagen-Markierung | `src/client/Controllers/Hud.luau`, `src/client/Ui.luau` |
| Map | Graybox-Pier, falls `Workspace.Pier` fehlt (die Map ist nicht in Rojo gemappt) | `src/server/Services/GrayboxService.luau` |
| Kill-Test-Log | Serves und Stürze pro Steuerung | `src/server/Services/KillTestLog.luau` |

## Bestätigte Bugs und Risiken (aus dem Code)

1. **Steady-Bonus ohne Mindesthöhe auf dem Server:** Der Client zählt Steady erst ab 10 Kugeln, der Server begrenzt nur über die Tragezeit (`TowerService.luau`, `steadyCap`). Ein manipulierter Client bekommt den Bonus auch bei kleinen Türmen. Kleiner Exploit.
2. **`debugCatch = true`** in `src/shared/Config/Features.luau`: Vor Tests mit fremden Spielern ausschalten.
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
3. Mit 12+ Kugeln laufen: Warnpuls an der Wasserwaage, F rettet, F in der Abklingzeit tut nichts.
4. Zum Wagen tragen: Wird serviert, steigen die Coins, kippt der Turm sauber?
5. Sprint mit Shift (schneller, Sichtfeld weiter), Dash mit Q, Sprung mit Leertaste, Shift-Lock mit Strg (muss in den Roblox-Einstellungen an sein).
6. Werfen: Linke Maustaste halten, die Leiste unter dem Fadenkreuz läuft auf und ab, der Maximalpunkt leuchtet oben. Loslassen am Minimum und am Maximum: Fliegt der Ball aus der rechten Hand, trifft er den Punkt unter dem Fadenkreuz (Wand in 20 bis 40 Studs), fliegt der volle Wurf sichtbar schneller und weiter? Während des Ladens getroffen werden (Knockdown): Leiste verschwindet, nach dem Aufstehen lädt sie bei gehaltener Taste neu. Leer werfen, Taste halten: Nach 7 s startet die Leiste von selbst.
7. Test → *Clients and Servers* mit 2 Spielern: Fremde Türme wackeln, Fänge zählen nur am eigenen Turm.
8. Optional: Handy über privat veröffentlichten Place, Neigerichtung prüfen, Throw-Button halten und loslassen.
