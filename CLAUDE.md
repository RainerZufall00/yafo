# yafo – Hinweise für Claude

Aufbau, Startargumente und Datenmodell-Regeln stehen in der `README.md`. Code-Kommentare und Commit-Nachrichten
sind deutsch, UI-Texte englisch mit deutscher Übersetzung in `App/Resources/Localizable.xcstrings`.

## Einkaufskatalog

`YafoKit/Sources/YafoKit/Domain/ShoppingCatalog.swift` – eine Zeile pro Artikelgruppe:

```swift
a("🍝", "penne", .pantry, "Nudeln|Pasta|Penne", "Pasta|Noodles|Penne"),
//  Emoji (Ersatz), Icon-ID, Abteilung, deutsche Namen, englische Namen
```

- Erster Name = Anzeigename. Ein Name darf nur in einer Gruppe stehen (sonst gewinnt die erste).
- Erkennung: exakter Name, sonst längstes bekanntes Grundwort am Ende („Vollkornnudeln“ → Nudeln) oder ganzes Wort.
  Kurze Namen (3–4 Buchstaben) können ungewollt als Endung greifen, z. B. „Rum“ in „Serum“ – vorher prüfen.
- Typen/Sorten für die Schnellauswahl im Detailblatt: `ShoppingDetails.variantTable`, Schlüssel ist der erste
  deutsche Name der Gruppe.
- Tests: `YafoKit/Tests/YafoKitTests/ListTests.swift` (`ShoppingCatalogTests`, `ShoppingDetailsTests`, `ShoppingIconTests`).

## Artikel-Icons

Einfarbige, gefüllte Glyphen („Stil B“): Details werden als Lücken ausgestanzt, keine Umrisse, keine zweite Farbe.
Die App färbt sie per `foregroundStyle` (weiß auf der Kachel, Abteilungsfarbe bei Vorschlägen, grau wenn abgehakt).

Die Icons werden **nicht von Hand als SVG** gepflegt, sondern von einem Generator erzeugt:

| Datei | Inhalt |
| --- | --- |
| `Tools/ItemIcons/shapes.py` | Bausteine (`circle`, `ellipse`, `rect`, `leaf`, `line`, `bez`, `arc`, `star` …) und Verknüpfungen |
| `Tools/ItemIcons/icons_*.py` | Die Icons, je Abteilung eine Datei; jede Funktion mit `@icon` ist ein Icon, Name = ID (`_` → `-`) |
| `Tools/ItemIcons/build.py` | Schreibt alle Icons nach `App/Resources/Assets.xcassets/Items/item-<id>.imageset` |

```sh
pip install shapely
python3 Tools/ItemIcons/build.py                                   # alle Imagesets neu schreiben
python3 Tools/ItemIcons/build.py --preview /tmp/p.html             # zusätzlich Kontaktbogen (HTML)
python3 Tools/ItemIcons/build.py --preview /tmp/p.html penne,fusilli 2   # nur diese, doppelte Größe
```

Neues Icon:

1. Funktion in der passenden `icons_*.py` anlegen, z. B. `@icon def sweet_potato(): ...` → ID `sweet-potato`.
2. ID in der Katalogzeile eintragen (zweiter Parameter von `a(...)`), für Abteilungen in `ShoppingCategory.icon`.
3. `build.py` laufen lassen und den Kontaktbogen ansehen (z. B. mit Playwright als Screenshot), auf farbiger Kachel
   und auf hellem Grund, auch in klein (20 pt).
4. Wird eine ID nicht mehr gebraucht: Funktion löschen und den Ordner `Assets.xcassets/Items` vor dem Build leeren,
   sonst bleibt das alte Imageset liegen. `ShoppingIconTests` meldet fehlende, aber keine überzähligen Icons.

Zeichenregeln:

- Raster 48 × 48, Inhalt etwa 4…44. Koordinaten wie SVG (y nach unten).
- Teile trennen mit `over(unten, oben, 1.4–1.8)` (oben liegt drauf, mit Lücke), Details ausstanzen mit
  `minus(form, ...)`, Konturlinien mit `gap(form, innenform, 1.6)`. Linien für Ausstanzungen 1.2–1.8 breit,
  Stiele/Griffe 2–3.
- Nichts, was nur in Farbe lesbar wäre; das Icon muss als Silhouette funktionieren.
- Ausgabe sind reine Füllpfade (`fill-rule="evenodd"`), keine Masken, Strokes oder Transformationen – so stellt
  Xcode sie als Template-Bild sicher dar. Imagesets haben `template-rendering-intent: template` und
  `preserves-vector-representation: true`.
- Keine fremden Icon-Sets übernehmen (Icons8/KitchenOwl, Bring u. a. sind lizenzrechtlich ausgeschlossen); alle
  Icons sind selbst gezeichnet und stehen unter der Lizenz des Repos.

In der App zeigt `ItemIcon` (`App/Sources/Lists/ItemIcon.swift`) das Asset `item-<id>` und fällt auf das Emoji
zurück, falls es fehlt.
