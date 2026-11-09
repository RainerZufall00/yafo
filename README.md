# yafo – yet another family organizer

Familien-Organizer für iPhone und iPad: geteilte und eigene Kalender, Einkaufsliste, Todos und Erinnerungen.
Alle Daten liegen in iCloud (CloudKit), ein eigener Server ist nicht nötig.

Architektur und Feature-Umfang: [docs/yafo – Architektur & Features.pdf](docs/)

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | SwiftUI-App (iOS/iPadOS 27, Mac als iPad-App), Ressourcen, Entitlements |
| `Widgets/` | Widget-Extension; liest nur einen Schnappschuss, den die App in die App Group schreibt |
| `Share/` | Share Extension „Screenshot zu Termin“ |
| `Shared/` | Code für App und Share Extension: Bildanalyse (Foundation Models, Vision) und Vorschau |
| `YafoKit/` | Swift Package mit Datenmodell, Persistenz (Core Data + CloudKit), Sharing und Logik, inkl. Tests |
| `docs/` | Architektur-Dokument |
| `Tools/ItemIcons/` | Generator für die Artikel-Icons der Einkaufsliste (`python3 Tools/ItemIcons/build.py`, braucht `shapely`) |

- **Datenmodell** im Code (`YafoKit/Sources/YafoKit/Model/YafoModel.swift`) statt `.xcdatamodeld`.
  Regeln fürs CloudKit-Schema: alle Beziehungen optional, keine Unique Constraints,
  nach dem ersten Produktiv-Deployment nur noch erweitern.
- **Drei Stores** (`PersistenceController`): privat (eigene Daten und Familien, deren Owner man ist),
  geteilt (Familien, in die man eingeladen wurde) und lokal (Abo-Cache).
- **Familien** sind je ein `CKShare`; neue Objekte landen per `assign` im Store ihrer Familie (`Repository`).
- **Erweiterungen schreiben nie in Core Data.** Widgets und Share Extension lesen den Schnappschuss
  (`WidgetSnapshot`) und legen Aufträge (Abhaken, Termine aus Screenshots) im Postfach der App Group ab
  (`AppGroupInbox`). Die App arbeitet es beim Start und bei jeder Rückkehr in den Vordergrund ab und synchronisiert.

## Loslegen

1. `yafo.xcodeproj` in Xcode 27 öffnen.
2. `Config/Local.xcconfig.example` nach `Config/Local.xcconfig` kopieren und die eigene Team-ID eintragen
   (die Datei wird nicht eingecheckt). Bundle-ID `de.yafo.app`, iCloud-Container `iCloud.de.yafo.app`
   und App Group `group.de.yafo.app` registriert Xcode beim ersten Start mit automatischer Signierung.
3. Ohne Team oder iCloud-Account läuft die App rein lokal. Die Widgets brauchen die App Group und damit
   einen signierten Build, auch im Simulator.

Startargumente fürs Entwickeln (im Scheme unter *Run › Arguments*, dort schon angelegt und abgeschaltet):

| Argument | Wirkung |
| --- | --- |
| `-yafoLocalOnly` | Kein CloudKit, nur lokale Stores |
| `-yafoInMemory` | Leere Stores in einem temporären Ordner |
| `-yafoDemoData` | Beispielfamilie mit Terminen, Serien, Listen und Todos (nur Debug) |
| `-com.apple.CoreData.CloudKitDebug 1` | Ausführliches CloudKit-Sync-Log |

Tests des Packages:

```bash
cd YafoKit && swift test
```

## Stand

Roadmap aus dem Architektur-Dokument:

- [x] **1. Fundament:** Datenmodell, Core Data mit CloudKit (privat + geteilt), Familien anlegen und einladen,
      Beitreten mit eigenem Profil oder verknüpftem Kinderprofil, Kinderprofile, mehrere Familien
- [ ] Prototyp Owner-Übertragung (V1.1)
- [x] **2. Kalender:** Monatsansicht zum Blättern, Jahresansicht, Termine mit Teilnehmern, Farbsystem,
      Personenfilter, Serien (RRULE, Ausnahmen, nur dieser / folgende / alle), Kommentare,
      Geburtstage mit mitzählendem Alter
- [x] **3. Listen:** Einkaufsliste als Kacheln mit Piktogrammen, sortiert nach Abteilungen in Laufreihenfolge
      (mitgelieferter Artikelkatalog DE/EN), „Zuletzt gekauft“ und Vorschläge; Todos mit Fälligkeit,
      Zuständigen und Serien, die beim Abhaken weiterrollen; je Familie und „Nur ich“
- [x] **4. Erinnerungen und Widgets:** lokale Benachrichtigungen (die nächsten 64, an Teilnehmer bzw.
      Zuständige, Zeit pro Person änderbar oder stumm), Widget „Nächste Termine“ (klein, mittel, groß)
      und „Nächster Termin“ für den Sperrbildschirm; Widgets „Einkaufsliste“ und „Todos“ je Familie oder
      „Nur ich“, direkt im Widget abhakbar (wirksam in iCloud, sobald die App das nächste Mal geöffnet wird)
- [x] 5. Abos und Import (Feiertage, Ferien, ICS, EventKit)
  - Gesetzliche Feiertage je Kalender (16 Bundesländer, AT, CH), offline berechnet
  - Schulferien (DE, AT, CH) aus der OpenHolidays API (ODbL), als Fläche im Kalender, wöchentlich neu geladen
  - Eigene ICS-/webcal-Adressen je Kalender, lokal zwischengespeichert, beim Öffnen aktualisiert
  - Gerätekalender grau einblenden (nur auf dem Gerät)
  - Einmal-Import aus Gerätekalendern, ICS-Adresse (Google) und .ics-Datei, mit Vorschau
  - Offen: eigener Spiegel der Ferien-Daten per GitHub Action, Background-Refresh, Vorauswahl im Onboarding
- [x] 6. Export und Backup
  - Je Familie, „Nur ich“ oder alles: Kalender als ICS (Serien mit Ausnahmen, Teilnehmer und Kommentare
    in der Beschreibung), Termine, Einkauf und Todos als CSV (UTF-8 mit BOM für Excel)
  - Kopie in einen Gerätekalender per EventKit; erneutes Kopieren ersetzt die früheren Kopien
  - JSON-Backup zum Teilen und Wiederherstellen (nur fehlende Einträge, verlorene Familien neu mit
    einem selbst als Owner), wöchentlich automatisch in den yafo-Ordner in iCloud Drive, die letzten fünf
  - Offen: Gerätekalender-Kopie automatisch aktuell halten
- [x] 7. Screenshot zu Termin
  - Share Extension (Bild aus jeder App teilen) und in der App: Plus-Knopf lange drücken › „Aus Screenshot“
  - On-Device-Modell (Foundation Models) bekommt das Bild direkt, Ausgabe per `@Generable`; kann es das nicht,
    Texterkennung mit Vision und dann das Modell; ohne Apple Intelligence `NSDataDetector`
  - Vorschau mit allen erkannten Terminen zum Bearbeiten und Abwählen, Ziel-Kalender (merkt sich den letzten)
  - Kein Private Cloud Compute, das Bild verlässt das Gerät nicht
  - Offen: auf echtem Gerät mit Apple Intelligence testen
- [ ] 8. TestFlight, App Store

## Lizenz

[MIT](LICENSE)
