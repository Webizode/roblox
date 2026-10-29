# Ideen-Pool Wobble Scoops

Stand: 29.10.2026. Ein Sammelplatz für später: **Nichts davon ist beschlossen.** Verbindlich bleiben `docs/design-regeln.md` und die Entscheidungen in `docs/projektstand.md`. Was gebaut wird, steht dort; was nur gedacht ist, steht hier.

- **Geplant:** steht in der Reihenfolge in `docs/projektstand.md` (Abschnitt 8) oder ist schon vorbereitet; es fehlt nur der Zeitpunkt.
- **Idee:** noch nicht entschieden, ob es überhaupt kommt.
- **Offen:** eine Frage oder ein bekanntes Problem, das noch eine Entscheidung braucht.

Grundregeln für alles hier: Sorten und Gegenstände sind anders, nicht stärker (Design-Regel 5). Kein Pay-to-Win, keine Paid Random Items, Gems nie Pflicht (Monetarisierung in `docs/concept.md`). Größere Systeme erst nach bestandenem Kill-Test.

---

## Geplant

- **Kill-Test** mit 2 bis 3 Spielern gleichzeitig (Kriterien in `docs/projektstand.md`, Abschnitt 8). Vorher keine größeren Systeme.
- **Golden Glow** für große Türme: Ein Turm leuchtet golden, sobald er die Golden Scoop trägt oder deutlich mehr wert ist als die anderen (Konzept: Golden Glow).
- **Golden Scoops:** etwa 1 von 40 Kugeln, Wert ×5. Vorbereitet sind die goldene Spur mit Glitzer, die Farbe fürs Namensschild und der Wert ×5 (`Config/Economy goldenMultiplier`). Der Launcher schickt goldene Kugeln erst mit `Features.goldenScoops`.
- **Emotionssystem** der Attack-Scoops, zuerst mit Vanille (`docs/projektstand.md`, Abschnitt 4).
- **Sorten-Fähigkeiten** als Sidegrades (Design-Regel 5).
- **Eigene seltenere Sorten** (uncommon bis legendary): Der Nutzer liefert die Entwürfe, dann bauen und hinzufügen mit eigener Form, eigenen Werten, Physik und Rezepten. Im Spiel sind seit dem 29.10.2026 nur die 11 Common-Sorten; Familien, Seltenheiten und ihre Farben sind vorbereitet.
- **Events** alle paar Minuten, z. B. „Scoop Rush“ oder „höchster Turm gewinnt“ (Design-Regeln).
- **Sammelbuch** (Flavor-Buch) mit neuem Konzept; die alten Entwürfe sind verworfen. Es muss unbekannte Sorten-IDs in alten Spielständen überspringen.
- **Upgrade-Kauf (Shop)** mit neuem Konzept, nach der Big Swirl; die alten Entwürfe sind verworfen.
- **Neues Hauptmenü und Einstellungsmenü** nach der Datei des Designers: Design übernehmen, Script sauberer und flüssiger, alle Funktionen des alten Menüs. Bis dahin wird am Menü nichts umgebaut.
- **Flug-Optik der Turm-Kugeln:** Drehen beim Steigen, Kippen wie ein Federball, Aufrichten beim Fang, Spur nach VFX-Qualität. Gebaut und getestet, aber aus (`Features.towerScoopFlight`).
- **Weitere Feature-Schalter aus der Roadmap:** Rempeln (`Features.bump`, Woche 2), Greg die Möwe (`greg`, Woche 3), Secret Stacks (`secretStacks`, Woche 3), Churn (`churn`, Woche 5).
- **Polish, UI, Monetarisierung**, nur Kosmetik.

## Idee

- **Crafting:**
  - Turm-Kugeln lassen sich in Materialien umwandeln, statt sie zu servieren.
  - Aus Materialien craftet man Attack-Scoops mit Fähigkeiten, in Stufen bis **Godly** (z. B. ein Craft aus 5 Godly Scoops plus Coins).
  - Gecraftete Kugeln sind **anders und auffälliger, nicht stärker**.
  - Gems sind dafür nie Pflicht.
  - Frühestens nach bestandenem Kill-Test.
- **Bosse** als Quelle für Crafting-Materialien.
- **Quests** als Quelle für Crafting-Materialien.
- **Cone Rank**, der nur nach oben geht und über dem Kopf steht (Konzept).
- **Block und Dodge** im Kampf.
- **„Der Turm schreit beim Kippen“:** Turm-Kugeln bekommen nur in diesem Moment ein kurzes Panik-Gesicht oder einen anderen Panik-Effekt. Widerspricht derzeit „Turm-Kugeln ohne Gesicht“ und braucht eine eigene Entscheidung (Art Bible).

## Offen

- **Feuerrate der Big Swirl** an die Spielerzahl koppeln. Heute 1,5 s Grundtakt, mit mehr Spielern geteilt durch die Wurzel der Spielerzahl, höchstens alle 0,45 s. Mit der größeren Map neu entscheiden; die sechs Arme schaffen eine Kugel alle 0,5 s.
- **Kippen kleiner Türme:** Seit dem Treffer-Tuning vom 25.10.2026 kippen drei schnelle volle Treffer auch den kleinsten Turm. Gewollt oder nicht?
- **Wurfkugel und Turm-Kugel Vanilla:** Soll die Wurfkugel (`#FFE7C0`) an das Creme der Turm-Kugel (`#F9DCA8`) angeglichen werden? (Art Bible)
- **Offene Punkte im Code:**
  - `debugCatch`, `debugThrow` und `debugDash` sind noch an.
  - Kleiner Exploit beim Steady-Bonus.
  - Einstellungen, die vor dem Laden des Spielstands geändert werden, gehen verloren.
  - Die Wurf-Sounds `swoosh.wav` und `rbxassetid://911864050` werden bei jedem Wurf als „not approved“ abgelehnt.
