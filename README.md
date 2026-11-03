# yafo – yet another family organizer

Familien-Organizer für iPhone und iPad: geteilte und eigene Kalender, Einkaufsliste, Todos und Erinnerungen.
Alle Daten liegen in iCloud (CloudKit), ein eigener Server ist nicht nötig.

Architektur und Feature-Umfang: [docs/yafo – Architektur & Features.pdf](docs/)

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | SwiftUI-App (iOS/iPadOS 27, Mac als iPad-App), Ressourcen, Entitlements |
| `Widgets/` | Widget-Extension; liest nur einen Schnappschuss, den die App in die App Group schreibt |
| `YafoKit/` | Swift Package mit Datenmodell, Persistenz (Core Data + CloudKit), Sharing und Logik, inkl. Tests |
| `docs/` | Architektur-Dokument |

- **Datenmodell** im Code (`YafoKit/Sources/YafoKit/Model/YafoModel.swift`) statt `.xcdatamodeld`.
  Regeln fürs CloudKit-Schema: alle Beziehungen optional, keine Unique Constraints,
  nach dem ersten Produktiv-Deployment nur noch erweitern.
- **Drei Stores** (`PersistenceController`): privat (eigene Daten und Familien, deren Owner man ist),
  geteilt (Familien, in die man eingeladen wurde) und lokal (Abo-Cache).
- **Familien** sind je ein `CKShare`; neue Objekte landen per `assign` im Store ihrer Familie (`Repository`).

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
      und „Nächster Termin“ für den Sperrbildschirm
- [x] 5. Abos und Import (Feiertage, Ferien, ICS, EventKit)
  - Gesetzliche Feiertage je Kalender (16 Bundesländer, AT, CH), offline berechnet
  - Schulferien (DE, AT, CH) aus der OpenHolidays API (ODbL), als Fläche im Kalender, wöchentlich neu geladen
  - Eigene ICS-/webcal-Adressen je Kalender, lokal zwischengespeichert, beim Öffnen aktualisiert
  - Gerätekalender grau einblenden (nur auf dem Gerät)
  - Einmal-Import aus Gerätekalendern, ICS-Adresse (Google) und .ics-Datei, mit Vorschau
  - Offen: eigener Spiegel der Ferien-Daten per GitHub Action, Background-Refresh, Vorauswahl im Onboarding
- [ ] 6. Export und Backup
- [ ] 7. Screenshot zu Termin
- [ ] 8. TestFlight, App Store

## Lizenz

[MIT](LICENSE)
