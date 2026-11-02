# yafo – yet another family organizer

Familien-Organizer für iPhone und iPad: geteilte und eigene Kalender, Einkaufsliste, Todos und Erinnerungen.
Alle Daten liegen in iCloud (CloudKit), ein eigener Server ist nicht nötig.

Architektur und Feature-Umfang: [docs/yafo – Architektur & Features.pdf](docs/)

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | SwiftUI-App (iOS/iPadOS 27, Mac als iPad-App), Ressourcen, Entitlements |
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
2. Unter *Signing & Capabilities* das eigene Team wählen. Bundle-ID `de.yafo.app`,
   iCloud-Container `iCloud.de.yafo.app` und App Group `group.de.yafo.app` müssen im Developer-Portal registriert sein.
3. Ohne Team oder iCloud-Account läuft die App rein lokal.

Startargumente fürs Entwickeln (im Scheme unter *Run › Arguments*):

| Argument | Wirkung |
| --- | --- |
| `-yafoLocalOnly` | Kein CloudKit, nur lokale Stores |
| `-yafoInMemory` | Leere Stores in einem temporären Ordner |
| `-yafoDemoData` | Beispielfamilie mit Terminen (nur Debug) |

Tests des Packages:

```bash
cd YafoKit && swift test
```

## Stand

Roadmap aus dem Architektur-Dokument:

- [x] **1. Fundament:** Datenmodell, Core Data mit CloudKit (privat + geteilt), Familien anlegen und einladen,
      Beitreten mit eigenem Profil oder verknüpftem Kinderprofil, Kinderprofile, mehrere Familien
- [ ] Prototyp Owner-Übertragung (V1.1)
- [ ] **2. Kalender:** ~~Monatsansicht~~, ~~Termine mit Teilnehmern~~, ~~Farbsystem~~, ~~Personenfilter~~ – offen:
      Jahresansicht, Serien (RRULE, Ausnahmen), Kommentare
- [ ] 3. Einkaufsliste und Todos
- [ ] 4. Erinnerungen und Widgets
- [ ] 5. Abos und Import (Feiertage, Ferien, ICS, EventKit)
- [ ] 6. Export und Backup
- [ ] 7. Screenshot zu Termin
- [ ] 8. TestFlight, App Store
