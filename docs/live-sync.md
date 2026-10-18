# Live-Sync: Claude Code → Rojo → Roblox Studio

Ziel: Du änderst Code mit Claude Code, und die Scripts im offenen Studio-Place sind sofort aktuell, ohne Studio neu zu starten.

```
Dateien in src/  ──►  rojo serve  ──►  Rojo-Plugin in Studio  ──►  Scripts im Place (Edit-Modus)
(Claude Code)         (Fenster von          (localhost:34872)
                       start-rojo.cmd)
```

Stand: Rojo 7.7.1, festgelegt in `rokit.toml`. Alle Aussagen über das Plugin unten sind im Quellcode von Rojo 7.7.1 nachgeprüft.

## Was Rojo in Studio verwaltet

| In Studio | kommt aus | Änderungen, die du in Studio daran machst |
|---|---|---|
| `ReplicatedStorage.Shared` | `src/shared` | werden überschrieben, sobald sich die passende Datei ändert oder Rojo neu verbindet |
| `ServerScriptService.Server` | `src/server` | ebenso |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client` | ebenso |
| alles andere: `Workspace.Pier` (Map), Lighting, weitere Objekte in diesen Services | der Place selbst | Rojo fasst es nicht an |

- Innerhalb der drei Ordner entfernt Rojo alles, was es nicht als Datei gibt. Ein Script, das du in Studio in `Shared` anlegst, ist beim nächsten Verbinden weg, innerhalb derselben Studio-Sitzung sogar ohne Nachfrage. Code deshalb nur über die Dateien ändern.
- Die Map lebt nur im Place. Rojo sichert sie nicht: in Studio mit Strg+S speichern (oder veröffentlichen).

## Einmalig einrichten

1. **`start-rojo.cmd` doppelklicken** (im Projektordner `C:\Users\beszt\roblox`). Das Skript installiert fehlende Tools und das Studio-Plugin in der passenden Version. Ist Studio dabei offen, Studio einmal neu starten.
2. **Nur ein Rojo-Plugin:** In Studio im Reiter *Plugins* darf es nur einen Rojo-Button geben. Hast du zusätzlich Rojo aus dem Creator Store installiert, diese Version unter *Plugins → Manage Plugins* entfernen. Eine abweichende Plugin-Version kann beim Verbinden einen Versionsfehler bringen.
3. **Place speichern:** Den Place mit der Map über *File → Save to File As* zum Beispiel als `C:\Users\beszt\roblox\WobbleScoops-Studio.rbxl` speichern. `.rbxl`-Dateien ignoriert git, sie landen also nicht im Repo. Nicht `build\WobbleScoops.rbxl` öffnen oder dorthin speichern: Das ist die Testdatei, die `lune run scripts/check` bei jedem Lauf neu baut, ohne Map. Team Create brauchst du für dieses Solo-Projekt nicht.
4. **Rojo-Einstellungen** (im Rojo-Fenster in Studio über *Settings*):

   | Einstellung | Empfehlung | Warum |
   |---|---|---|
   | Confirmation Behavior | **Initial** (Standard) | Der erste Sync pro Studio-Sitzung zeigt alle Änderungen zur Bestätigung. Danach läuft alles ohne Nachfrage. |
   | Auto Reconnect | an, sobald der Place veröffentlicht ist (Standard ist aus) | Beim Öffnen des Place verbindet Rojo von selbst, wenn `start-rojo.cmd` läuft und es dasselbe Projekt ist. Die Bestätigung beim ersten Sync bleibt. Wirkt nur bei einem veröffentlichten Place, der aus Roblox geöffnet wird: Für lokale `.rbxl`-Dateien und Vorlagen wie *Baseplate* merkt sich Rojo nichts. |
   | Sync Reminder / Sync Reminder Polling | Notify / an (Standard) | Solange Studio nicht verbunden ist, fragt das Plugin alle 30 s, ob es sich mit dem laufenden Server verbinden soll („Project 'wobble-scoops' is serving at localhost:34872. Would you like to connect?“). Klickst du dort *Dismiss*, fragt es bis zum nächsten Öffnen des Place nicht mehr. |
   | Two-Way Sync | **aus** (Standard) | Als „unstable“ markiert. Damit gäbe es im Bestätigungsdialog zusätzlich „Reject“, das den Stand aus Studio in deine Dateien schreibt und Dateien löschen kann. |
   | Auto Connect Playtest Server | **aus** (Standard) | Als „unstable“ markiert und bringt für dieses Projekt nichts, siehe Grenzen unten. |

## Jeden Tag

1. **`start-rojo.cmd` doppelklicken.** Das Fenster heißt „Rojo - Wobble Scoops“ und bleibt offen, solange du entwickelst. Es zeigt die Rokit- und Rojo-Version an.
2. **Place in Studio öffnen.** Bei einem lokal gespeicherten Place fragt Studio innerhalb von 30 s „Would you like to connect?“: *Connect*. Oder selbst *Plugins → Rojo → Connect*. Die Felder für Adresse und Port leer lassen, dann nimmt Rojo `localhost:34872`. Bei einem veröffentlichten Place mit Auto Reconnect verbindet Rojo von selbst.
3. **Erster Sync: Änderungen prüfen.** Rojo zeigt eine Liste, was es in Studio ändern will.
   - Betroffen sein dürfen nur Objekte unter `ReplicatedStorage.Shared`, `ServerScriptService.Server` und `StarterPlayerScripts.Client`. Ganz oben steht meist noch eine Umbenennung des Spiels selbst in `wobble-scoops`, die ist normal. Dann **Accept**.
   - Taucht etwas anderes auf (z. B. `Workspace` oder `Lighting`), **Abort**. Dann wird nichts geändert.
   - Einen Button **Reject** gibt es nur mit Two-Way Sync, das bleibt aus.
4. **Arbeiten.** Claude Code ändert Dateien, Studio zeigt sie sofort. Das Rojo-Fenster in Studio zeigt dabei `wobble-scoops`, `localhost:34872` und einen *Disconnect*-Button.
5. **Testen.** *Play* (F5). Nach jeder Codeänderung: *Stop* (Umschalt+F5) und wieder F5, siehe Grenzen.

## Änderungen aus Cloud-Sessions

- **Claude Code auf deinem PC** (Desktop-App oder CLI, geöffnet im Ordner `C:\Users\beszt\roblox`) ändert die Dateien direkt. Rojo übernimmt sie sofort.
- **Cloud-Sessions** (claude.ai/code) ändern nichts auf deinem PC, sie pushen auf GitHub. So holst du die Änderungen, während Rojo läuft:
  ```powershell
  cd $HOME\roblox
  git pull --ff-only
  ```
  Rojo übernimmt alle geänderten Dateien von selbst, ohne Neustart. Meldet `git pull` lokale Änderungen, erst mit `git status` nachsehen, nichts blind verwerfen.
- `git pull` holt nur den Branch, auf dem du lokal stehst (`git branch --show-current`). Hat die Cloud-Session auf einen anderen Branch gepusht (steht in der Session oder im Pull Request), erst den Pull Request mergen oder mit `git fetch` und `git switch <branch>` dorthin wechseln. Sonst meldet `git pull` nur „Already up to date“.

## Grenzen während eines laufenden Playtests

- **Rojo synct in den Edit-Modus.** Ein Playtest (F5) läuft auf einer Kopie, die beim Start erstellt wird. Was Rojo während des Tests ändert, landet im Edit-Place, im laufenden Test siehst du es nicht. Nach *Stop* ist es da, der nächste F5 nutzt es.
- **Laufende Scripts laden nicht nach.** Ein Script, das schon läuft, startet bei geändertem Code nicht neu. Ein ModuleScript, das schon mit `require` geladen wurde, bleibt im Cache. LocalScripts aus `StarterPlayerScripts` werden beim Beitreten in den Spieler kopiert, spätere Änderungen erreichen einen Spieler im Test nicht mehr.
- **Auto Connect Playtest Server** ändert daran wenig. Es verbindet nur den Server des Tests mit Rojo, nicht den Client. In diesem Projekt starten alle Services und Controller einmal beim Start über Module, also wirkt eine Codeänderung auch damit erst nach Stop + F5.
- **Tuning-Werte** in `src/shared/Config` sind ebenfalls Module. Gleiche Regel: ändern, Stop, F5.
- **Änderungen an der Map während des Tests** sind nach *Stop* weg (Roblox-Standard, unabhängig von Rojo). Map nur im Edit-Modus bauen.

Faustregel: Code ändern ist live, Testen braucht einen neuen Playtest. Studio selbst musst du nicht schließen.

## Verbindung halten und Fehler

| Situation | Was passiert | Was tun |
|---|---|---|
| Rojo-Fenster geschlossen, Strg+C, Neustart oder Ruhezustand des PCs | Das Rojo-Fenster in Studio zeigt einen Fehler wie „WebSocket connection closed unexpectedly“, die Scripts bleiben auf dem letzten Stand | Fehler mit *Okay* schließen, `start-rojo.cmd` starten. Studio fragt innerhalb von 30 s „Would you like to connect?“ (außer du hast die Erinnerung vorher mit *Dismiss* weggeklickt), oder selbst *Connect* klicken. |
| Studio zeigt „You synced project 'wobble-scoops' to this place … Did you mean to run 'rojo serve' and then connect?“ (nur bei veröffentlichten Places) | Der Place war schon mal verbunden, aber kein Rojo-Server läuft | `start-rojo.cmd` starten, dann *Connect*. |
| `start-rojo.cmd` ein zweites Mal gestartet | Das Skript bricht ab: „Auf Port 34872 läuft schon ein Rojo-Server“ | Das erste Fenster weiter benutzen. Ist keins offen oder serviert es einen anderen Ordner (z. B. eine alte Kopie des Projekts), im Task-Manager `rojo.exe` beenden und das Skript neu starten. |
| Versionsfehler beim Verbinden | Plugin und Server passen nicht zusammen | Datei `.rojo-plugin-version` im Projektordner löschen und `start-rojo.cmd` neu starten, das installiert das passende Plugin. Studio neu starten, Rojo aus dem Creator Store entfernen. |
| Änderung kommt nicht in Studio an | | Zeigt das Rojo-Fenster in Studio `wobble-scoops` und *Disconnect*? Liegt die Datei unter `src/`? Nach einer Cloud-Session `git pull` gemacht, auf dem richtigen Branch? Läuft gerade ein Playtest (dann Stop)? |
| Script direkt in Studio geändert | Wird überschrieben, sobald sich seine Datei ändert oder Rojo neu verbindet | Code nur in den Dateien ändern. |
| `Could not start the Rojo server` | Port belegt | Anderes Rojo-Fenster schließen oder im Task-Manager `rojo.exe` beenden. |

## Was hier getestet wurde

In einer Cloud-Umgebung (Linux, Rojo 7.7.1) wurde `rojo serve default.project.json` auf einer Kopie des Projekts gestartet. Ein Testskript hat die Rolle des Studio-Plugins übernommen: Baum gelesen, Änderungskanal geöffnet und dann Dateien geändert. Ergebnis:

| Änderung | beim Plugin angekommen |
|---|---|
| Script bearbeitet (direkt gespeichert) | nach 0,05 s, geändert: `Source` |
| Script über temporäre Datei + Umbenennen gespeichert | nach 0,05 s |
| neue Datei | nach 0,05 s, ein neues Objekt |
| Datei gelöscht | nach 0,05 s, ein Objekt entfernt |
| 6 Dateien auf einmal (wie bei `git pull`) | alle 6 |
| Datei außerhalb von `src/` (z. B. `docs/`) | nichts, wie erwartet |

Nicht getestet werden konnte das echte Studio-Plugin unter Windows. Das ist der Schritt, den du einmal selbst prüfst.
