# Sortenfarben der Map

Seit 06.11.2026 hat jeder der 12 Sektoren eine eigene Sortenfarbe, vom Nutzer freigegeben. Die Map war vorher fast nur Pink und Creme. Es ist nur umgefärbt, kein Modell ist neu oder verändert. Skript: `studio_map_flavors.luau` (Studio-Befehlsleiste, Edit-Modus).

## Ein Sektor

Sektor k gehört zu Plot_k. Er umfasst:

- `Plot_k`
- `Schody.Rampa_k`
- `Dekoracje.Wejscia.Wejscie_k`
- `Mosty.Most_k`
- die Randstücke links und rechts der Rampe (`RandSaeule_ka`, `RandWand_ka`, `RandSaeule_(k-1)b`, `RandWand_(k-1)b`)
- die Teile aus `Wyspa.Pas` und alle Deckungen aus `Covery`, die höchstens ±15° von der Rampe entfernt liegen

Die Rampe liegt bei 75° − 30°·(k−1). So erkennt man von der Arena aus am Bogen und an der Rampe, wohin es zum eigenen Plot geht.

## Sorten (Hauptton, Akzent)

| Plot | Sorte | Haupt | Akzent |
|---|---|---|---|
| 01 | Mint | #7FE0B8 | #2E9E78 |
| 02 | Mango | #FF6F12 | #C2410C |
| 03 | Blaubeere | #6F7BEA | #3A3F9E |
| 04 | Zitrone | #FFE15A | #E0A21C |
| 05 | Lavendel | #BB9CF0 | #7A55C4 |
| 06 | Erdbeere | #FF7480 | #C93A4E |
| 07 | Pistazie | #B4D46A | #6F9132 |
| 08 | Bubblegum (das bisherige Pink) | #F06AAE | #A8327A |
| 09 | Karamell | #E8B877 | #9C5A22 |
| 10 | Himmelblau | #75D6F2 | #2C8FC9 |
| 11 | Schoko | #9A6244 | #5A3320 |
| 12 | Kirsche | #D7304E | #7E1631 |

Nebeneinanderliegende Plots wechseln zwischen warm und kühl. Mango war im ersten Vorschlag #FF8A2B. Der Nutzer wollte es orangener, damit es sich klarer von Zitrone abhebt.

Die Deckungen gehen reihum durch alle 12 Sorten. Sie sind nach Winkel und Abstand sortiert, jede fünfte Sorte kommt als nächste dran. Auch ein Teillauf ergibt so dieselben Farben wie der ganze Lauf.

## Was welche Farbe bekommt

Die Regel richtet sich nach dem Farbnamen am Ende des Mesh-Namens, also nach dem Kit-Export `<Modell>_<Farbe>`:

| Teil | Pink | andere |
|---|---|---|
| Plot (Wagen, Werkstatt, Truhe, Zaunkappen, Schild) | Haupt, Wegmitte `PathRound_Pink` Akzent | Cherry → Akzent, Schildnieten Gold → Akzent, Wegsteine `Stone` → Haupt 35 % zu Creme, Zaun- und Schildpfosten Waffle → Schoko #6E4029, Inselsockel `Wyspa_*` → Karamell #A8683F |
| Rampe | ganze Rampe Haupt | |
| Eingangsbogen | Haupt | Gold und Cherry → Akzent, Waffle-Säulen → Schoko |
| Arena-Rand vor der Rampe | Haupt | SkyBlue → Akzent, Waffle → Schoko |
| Brücke `Pomost` | ganze Brücke Akzent | |
| Deckung | Haupt der Deckungssorte | SkyBlue und Cherry → Akzent; Waffle, Creme, Gold bleiben |
| Streifenkante `Wyspa.Pas` (Rampenwände, Außenkante) | Karamell #A8683F, ergibt einen Ring | |

Gemeinsame Flächen (`NEUTRALS`):

| Fläche | Farbe |
|---|---|
| Hub-Ring (`Wyspa.Ring`) | Vanille-Creme #F6DFB2 |
| Streifen mit der Ziegelwand zur Arena (`Wyspa.Brzeg_01` bis `_12`) | Vanille #F6DFB2 oder Karamell #D9A066 (`WALL`) |
| Bodensaum (`Plac.Arena_Rand`) | Vanille #E8C690 oder Karamell #A8683F (`WALL`) |

Die Ziegelwand ist nicht `Plac.Arena_Rand`. Das ist nur der flache Saum am Arenaboden. Die Wand ist die Innenseite der `Brzeg`-Meshes, deren Oberseite die Lauffläche des Streifens ist.

Ring, Streifen und Kante tragen das Pflaster `WS_Pavers`. Ihre Teilefarbe tönt das Bild, darum sind die Töne etwas kräftiger gewählt, als sie wirken.

Unverändert bleiben:

- Big Swirl
- Emblem
- Arenaboden
- Grenzlinien in `Strefa`
- Gold- und SkyBlue-Teile der Stationen
- Glas der Truhe

## Ausführen

1. Oben im Skript `SECTORS` setzen: `"all"` oder eine Liste wie `{ 1, 2 }`. Dazu `NEUTRALS` (true/false) und `WALL` (`"Vanille"` oder `"Karamell"`).
2. Den ganzen Inhalt in die Befehlsleiste kopieren und Enter drücken. Die Ausgabe nennt die Zahl der gefärbten Teile. Ein voller Lauf färbt 1.771 Teile.
3. Den Place speichern.

Das Skript lässt sich gefahrlos mehrmals laufen lassen, auch mit geänderten Farben. Jedes Teil merkt sich beim ersten Färben seine alte Farbe im Attribut `FlavorOrigColor`. Mit `RESTORE = true` gehen die gewählten Sektoren und Flächen auf diese Farbe zurück. Ein Lauf ist ein Rückgängig-Schritt (Strg+Z).

## Vorschau

Im Vault unter `Wobble Scoops/Map Farben Vorschau`:

- erster Sektor vorher und nachher: `Sektor1_*`
- alle 12 Sektoren von oben, aus Spielerhöhe in der Arena (Wand in Vanille und in Karamell) und von der Brücke zu Plot 01: `Alle_*`

## Offen

- **Wandfarbe:** Vanille oder Karamell entscheidet der Nutzer. Im Place steht Vanille, das ist auch die Vorgabe im Skript.
- **Inselsockel brauchen Struktur:** Waffel oder ein Schoko-Glasurrand mit Tropfen. Heute sind es glatte Karamell-Flächen. Noch nichts gebaut.
- **Neue Plot-Kit-Teile:** Kommen sie per `assets/PlotKit/studio_plotkit_place.luau` neu auf die Plots, haben sie wieder die Kit-Farben. Danach dieses Skript noch einmal laufen lassen.
