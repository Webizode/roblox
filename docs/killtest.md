# Kill-Test Woche 1

Eine Frage entscheidet, ob wir Wobble Scoops weiterbauen: **Fühlt sich das Balancieren gut an, und sind Stürze die eigene Schuld?** Wenn nicht, ist das Spiel tot, egal was danach kommt. Dann eine Tuning-Runde, und wenn es danach immer noch nicht trägt: Pivot zu Plan B (Firefly Hollow, siehe `concept.md`).

## Vorbereitung

- Place mit `rojo serve` + Studio, ein Testlauf allein: Fangen, Wackeln, Servieren, einmal Rettung (F) und Dash (Shift).
- In Studio die Latenz auf 0,2 s stellen und einmal selbst spielen. In der Ausgabe dürfen dabei kaum `[Catch] rejected`-Zeilen auftauchen. Vor dem Test mit Spielern `debugCatch` in `Config/Features.luau` ausschalten.
- Für Handys: Place veröffentlichen (File → Publish to Roblox), privat lassen und den Testern Zugriff geben. Mindestens ein schwaches Android dabei.
- 5 Tester, davon mindestens 2 zwischen 10 und 15 (Geschwister, Kinder von Freunden, **nur mit Einverständnis der Eltern**).

## Ablauf pro Tester (ca. 12 Minuten)

1. Nichts erklären außer: „Fang Kugeln und bring sie zu deinem Wagen.“
2. **9 Minuten spielen.** Es gibt nur noch eine Steuerung: WASD, automatische Grundstabilisierung, Rettung mit F bzw. *Steady*, Dash mit Shift bzw. *Dash*. Nichts davon erklären; beobachten, ob der Hinweis „Press F to steady it“ verstanden wird.
3. **Nach jedem Sturz** fragen: „War das deine Schuld oder Pech?“ Strichliste unten.
4. Nach 9 Minuten: „Du kannst aufhören oder weiterspielen.“ Notieren, ob freiwillig weitergespielt wird.
5. Danach 3 Fragen:
   - „Erzähl einem Freund in einem Satz, worum es geht.“ (Erfolg: Verben wie *balancieren, retten, fangen* statt nur Nomen)
   - „Würdest du morgen wieder spielen?“
   - „Was hat dich am meisten genervt?“

## Strichliste

| Tester | Alter | Gerät | Stürze „meine Schuld“ | Stürze „Pech“ | spielt weiter? | Satz |
|---|---|---|---|---|---|---|
| 1 | | PC | | | | |
| 2 | | Handy | | | | |

## Daten aus dem Spiel

Die Server-Ausgabe zeigt alle 2 Minuten und beim Beenden:

```
[KillTest] summary
  controls auto: 14 serves, median height 11.0 (after minute 5: 13.0), 6 topples at median 16.0
```

Seit der automatischen Grundstabilisierung gibt es nur noch eine Steuerung (`auto`). Per Studio-MCP abrufbar: `ServerStorage.KillTestLog.Value` (JSON mit allen Serves, Stürzen und Sessions).

## Bestanden, wenn

- **≥ 8 von 10 Stürzen** fühlen sich selbstverschuldet an,
- **≥ 3 von 5 Testern** spielen nach der Zeit freiwillig weiter,
- die **mediane Serve-Höhe nach 5 Minuten liegt zwischen 8 und 15 Kugeln** (Push-your-Luck funktioniert: nicht zu leicht, nicht zu schwer).

Stabilisator und Rettung stellst du in `assist` und `rescue` in `src/shared/Config/Tower.luau` ein.

## Wenn es nicht besteht: eine Tuning-Runde

Alle Werte liegen in `src/shared/Config/Tower.luau`. Nach jeder Änderung `lune run scripts/check`, die Tests sichern ab, dass ein Spieler mit 0,3 s Reaktionszeit weiter 20 Kugeln halten kann.

| Symptom | Stellschraube |
|---|---|
| Stürze fühlen sich zufällig an | `driftPerScoop` runter, `groanDuration` hoch (mehr Zeit zum Retten) |
| zu leicht, Türme werden riesig | `baseStiffness` runter oder `driftStartScoops` runter |
| zu schwer, Median unter 8 | `assist.floor` bzw. `assist.zeroAt` hoch (Stabilisator bei hohen Türmen stärker), `rescue.authority` hoch |
| zu leicht, Türme werden riesig | `assist.zeroAt` runter, `assist.floor` runter |
| Rettung zu stark/zu schwach | `rescue.authority`, `rescue.duration`, `rescue.cooldown` |
| Anlaufen wirft den Turm um | `accelSmoothing` hoch oder `accelGain` der Variante runter |
| Pad fühlt sich träge an | `padPerInstability` hoch (hohe Türme) bzw. `padBase` hoch (kleine Türme), `baseDamping` runter |
| Kleine Türme kippen beim Gegensteuern | `padBase` runter, `keyRampTime` hoch (Tasten weicher) |
| Laufen (Variante A) zu schwer/zu leicht | bei A `accelPerInstability` bzw. `driftScale` anpassen |
| Turm „klebt“, kein Wackeln | `baseDamping` runter, `landingKick` hoch |
