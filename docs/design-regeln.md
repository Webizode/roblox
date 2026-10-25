# Wobble Scoops: Design-Regeln (verbindlich)

Stand: 25.10.2026. Dieses Dokument legt die Richtung fest. Bei Widersprüchen gilt es vor `docs/concept.md` und vor älteren Zusammenfassungen aus ChatGPT.

## 1. Was Wobble Scoops ist

Ein PvP-Spiel auf einem offenen Pier. Du fängst lebendige Eiskugeln, stapelst sie als wackelnden Turm auf deinem Rücken und wirfst sie auf andere. Dein Turm ist dein Einsatz: Alles, was du trägst, kann dir weggeschossen werden. Sicher ist es erst, wenn du es an deinem Wagen servierst.

**In einem Satz:** Stapel hoch, wirf gut, bring deine Beute nach Hause, bevor dich jemand abschießt.

## 2. Richtung

- **PvP ist der Kern** im Moment-zu-Moment-Spiel.
- **Sammeln ist der Grund wiederzukommen** (Sorten, Sammelbuch, Fortschritt), nicht der Hauptinhalt.
- **Offener Server, kein Matchmaking.** Alle auf einem Pier, jederzeit einsteigen.
- **Kurze Events** alle paar Minuten (ca. 3 Minuten), z. B. „Scoop Rush“ oder „höchster Turm gewinnt“. Sie geben Arena-Gefühl ohne leere Lobbys.

## 3. Kernloop

Kugeln fangen → Turm wächst → du wirst zum Ziel → sicher servieren **oder** andere abschießen und ihre verschütteten Kugeln klauen.

- 30 Sekunden: fangen, werfen, ausweichen, Turm retten
- 5 Minuten: servieren, ein Event mitspielen, jemanden mit großem Turm jagen
- Tage: neue Sorten fürs Sammelbuch, Upgrades, Lieblings-Scoop

## 4. Die Regeln

1. **Der Turm ist dein Einsatz.** Was du trägst, ist ungesichert. Gesichert wird nur durch Servieren am eigenen Wagen.
2. **Wer hoch stapelt, wird gejagt.** Große Türme leuchten (Golden Glow), sind von weitem sichtbar und bringen beim Abschießen am meisten. Der Führende wird automatisch zum Ziel.
3. **Treffen fühlt sich stark an, getroffen werden fühlt sich fair an.** Klarer Treffer-Sound und Effekt, Server entscheidet, kein Dauer-Stun. Wer kippt, muss denken: „Hätte ich ausweichen oder retten können.“
4. **Verlieren tut weh, aber nie komplett.** 30 % (mindestens 2 Kugeln) bleiben. 3 Sekunden Vorrang auf die eigenen verschütteten Kugeln. Türme unter 5 Kugeln und der Bereich am Wagen sind geschützt.
5. **Sorten sind anders, nicht stärker.** Jede Sorte hat eine Fähigkeit als Sidegrade. Kein Pay-to-Win, auch nicht später.
6. **Smooth vor Features.** Eingabe reagiert sofort, Wurf und Bewegung werden auf dem Client vorhergesagt, der Server prüft. Lieber wenige Mechaniken, die sich perfekt anfühlen.
7. **Die Scoops leben.** Jede Kugel hat Gesicht, Persönlichkeit und reagiert auf das, was dir passiert (Abschnitt 5).
8. **Bestehendes wird erweitert, nicht ersetzt.** Turmphysik, Fangen, Wurf, Dash und Server-Autorität bleiben die Grundlage.
9. **Gefahr kommt von Spielern, nicht von der Physik allein.** Ein Turm kippt nicht einfach so, sondern weil jemand etwas getan hat: du selbst oder ein Gegner.
   - Stillstehen: bis mindestens 40 Kugeln kippt der Turm nie von selbst.
   - Normales Gehen geradeaus: bis ca. 25 Kugeln stabil, darüber nur mit gelegentlichem Steady.
   - Sprint, Dash, scharfe Kurven und Treffer sind die echten Gefahren und wirken mit der Höhe stärker. (Der Sprung als Turm-Gefahr kommt später.)
   - Abgesichert durch Tests in `tests/TowerModel.spec.luau` („The danger comes from players …“), Stellschrauben in `src/shared/Config/Tower.luau`.
10. **Läuft auf allen Geräten gleich gut.** Handy, Tablet, PC und Konsole sind gleichwertig. Jede Aktion hat Touch-, Gamepad- und Tastatur/Maus-Steuerung. Große Touch-Buttons, lesbare UI auf kleinen Bildschirmen, Leistung auf schwachen Android-Handys geprüft. Zielen mit Daumen und Stick bekommt später eine leichte Zielhilfe. Kamera-Effekte dezent und abschaltbar.

## 5. Lebendige Scoops: Emotionssystem

Der Attack-Scoop in deiner Hand ist dein Partner (nicht die Turm-Kugeln). Sie reagiert auf das Spielgeschehen, und andere Spieler sehen das.

### Emotionen und Auslöser

| Emotion | Auslöser | Wirkung |
|---|---|---|
| Freude / Jubel | du triffst jemanden, Knockdown, großer Turm serviert | nur Optik, kurzer Jubel, andere sehen es |
| Wut | du wirst 2× kurz hintereinander getroffen oder verlierst Kugeln | einzige spielerische Wirkung: nächster Wurf ist ein „Wut-Wurf“ mit etwas mehr Turm-Stoß (Comeback, kein Schaden-Bonus) |
| Angst | dein Turm ächzt oder steht kurz vor dem Kippen | Warnsignal für den Spieler, das Gesicht ist Teil der Anzeige |
| Überraschung | im Flug, kurz vor dem Aufprall | nur Optik |
| Splat | Aufprall | kurzes Zerquetschen, dann Effekt |
| Langeweile / Idle | länger nichts passiert | blinzeln, umschauen, wippen |

### Technische Regeln

- **Ein gemeinsames Emotionssystem** für alle Sorten: Ereignis → Emotion, Dauer, Priorität. Alles in einer Config.
- **Gesichter sind austauschbar** (getrennte Texturen/Decals für Augen und Mund), nicht ins Modell eingebacken. 5 bis 6 Ausdrücke reichen.
- **Bewegung prozedural im Code:** Squash and Stretch, Wippen, Zittern bei Angst. Keine eigene Animation pro Sorte nötig.
- **Pro Sorte nur:** Farbe, kleines Merkmal (Accessoire, Form), Persönlichkeit (welche Emotion stärker ausfällt), Sound.
- **Lesbar aus Distanz:** übertriebene Ausdrücke, die man auf ca. 20 Studs und im Flug erkennt.
- **Nur Attack-Scoops** (in der Hand, werden geworfen) haben Gesicht und Emotionen. Turm-Kugeln sind schlichte Beute.

## 6. Sorten-Startset (4 Stück)

| Sorte | Fähigkeit | Persönlichkeit |
|---|---|---|
| Vanille | Allrounder, gerader Flug | freundlich, ausgeglichen |
| Erdbeere | springt einmal ab | verspielt, frech |
| Minze | verlangsamt kurz beim Treffer | cool, gelassen |
| Chili | mehr Stoß auf den Turm, weniger Reichweite | hitzköpfig, wird schnell wütend |

Weitere Sorten erst, wenn diese vier im Playtest funktionieren.

## 7. Monetarisierung (Rahmen)

- Kosmetik: Gesichts-Pakete, Ausdrücke, Jubel-Effekte, Waffel-Skins
- Komfort ohne Kampfvorteil
- Niemals: stärkere Würfe, mehr Leben, Schutz gegen Treffer kaufen

## 8. Was wir bewusst nicht machen

- Kein Matchmaking und keine Lobby
- Keine Nahkampf-Combos (einzige Angriffsaktion bleibt Werfen)
- Keine Sorten, die einfach stärker sind
- Keine neuen Systeme, bevor der Kill-Test besteht

## 9. Reihenfolge

1. Kill-Test (siehe unten)
2. Verschüttete Kugeln anderer aufsammeln (Beute)
3. Golden Glow für große Türme
4. Emotionssystem mit Vanille
5. Die drei weiteren Sorten
6. Events
7. Speichern, Sammelbuch, Upgrades
8. Polish, UI, Monetarisierung

## 10. Kill-Test (neu)

Mit mindestens 2 bis 3 Spielern gleichzeitig. Bestanden, wenn:

- Abschießen eines großen Turms sich gut anfühlt (Tester sagen es von selbst oder lachen)
- mindestens 8 von 10 Stürzen sich selbstverschuldet oder fair anfühlen
- mindestens 3 von 5 Testern nach der Zeit freiwillig weiterspielen
- Tester das Spiel in einem Satz mit Verben wie „abschießen, stapeln, retten“ beschreiben
