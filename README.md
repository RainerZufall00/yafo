# yafo – yet another family organizer

Familien-Organizer für iPhone und iPad: geteilte und eigene Kalender, Einkaufsliste, Todos und Erinnerungen.
Alle Daten liegen in iCloud (CloudKit), ein eigener Server ist nicht nötig.

Architektur und Feature-Umfang: [docs/yafo – Architektur & Features.pdf](docs/)

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | SwiftUI-App (iOS/iPadOS 27, Mac als iPad-App), Ressourcen, Entitlements |
| `Widgets/` | Widget-Extension; liest nur einen Schnappschuss, den die App in die App Group schreibt |
| `ShareExtension/` | „Termin aus Screenshot“ im Teilen-Menü; nutzt `App/Sources/Screenshot/` mit und schreibt ohne eigene iCloud-Synchronisation in die Stores der App Group, die App übernimmt die Änderungen beim Aktivwerden |
| `YafoKit/` | Swift Package mit Datenmodell, Persistenz (Core Data + CloudKit), Sharing und Logik, inkl. Tests |
| `docs/` | Architektur-Dokument |
| `AppStore/` | Store-Eintrag: Texte (fastlane-Layout), Screenshots samt Skripten, Datenschutz und Support-Website – siehe `AppStore/README.md` |
| `Tools/ItemIcons/` | Generator für die Artikel-Icons der Einkaufsliste (`python3 Tools/ItemIcons/build.py`, braucht `shapely`) |
| `Tools/AppIcon/` | Generator fürs App-Icon „Familie vor dem Y“ in hell, dunkel und getönt (`swift Tools/AppIcon/build.swift`, `--preview datei.html` für eine Vorschau); `concepts/` enthält die Entwürfe |

- **Datenmodell** im Code (`YafoKit/Sources/YafoKit/Model/YafoModel.swift`) statt `.xcdatamodeld`.
  Regeln fürs CloudKit-Schema: alle Beziehungen optional, keine Unique Constraints,
  nach dem ersten Produktiv-Deployment nur noch erweitern.
- **Drei Stores** (`PersistenceController`): privat (eigene Daten und Familien, deren Owner man ist),
  geteilt (Familien, in die man eingeladen wurde) und lokal (Abo-Cache).
- **Familien** sind je ein `CKShare`; neue Objekte landen per `assign` im Store ihrer Familie (`Repository`).
- **Widgets schreiben nie in Core Data.** Sie lesen den Schnappschuss (`WidgetSnapshot`) und legen Aufträge
  (Abhaken) im Postfach der App Group ab (`AppGroupInbox`). Die App arbeitet es beim Start und bei jeder Rückkehr
  in den Vordergrund ab und synchronisiert. Die Share Extension schreibt ohne iCloud direkt in die Stores der App
  Group, die App übernimmt das beim Aktivwerden.

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
| `-yafoOnboarding` | Onboarding bei jedem Start zeigen, auch wenn es schon eine Familie gibt |
| `-screenshotDemo` | App-Store-Screenshots: Demo-Daten im Speicher, ohne iCloud und Mitteilungs-Dialog; `-demoScreen day\|event\|family\|screenshot` öffnet die Ansicht (nur Debug, siehe `AppStore/README.md`) |
| `-com.apple.CoreData.CloudKitDebug 1` | Ausführliches CloudKit-Sync-Log |

Tests des Packages:

```bash
cd YafoKit && swift test
```

## TestFlight

Version und Build-Nummer stehen in `Config/Base.xcconfig` und gelten für App und Extensions.
Export-Compliance (`ITSAppUsesNonExemptEncryption = NO`) und Privacy Manifests sind gesetzt.

1. Einmalig: App in App Store Connect anlegen (Bundle-ID `de.yafo.app`).
2. Einmalig und nach jeder Modelländerung: CloudKit-Schema nach Production bringen, TestFlight-Builds
   synchronisieren nur dort. Debug-Build mit Startargument `-yafoInitCloudKitSchema` einmal starten
   (iCloud angemeldet, legt alle Typen und Felder in Development an), dann im
   [CloudKit Console](https://icloud.developer.apple.com) unter `iCloud.de.yafo.app` › Schema
   *Deploy Schema Changes…* wählen.
3. `CURRENT_PROJECT_VERSION` erhöhen, in Xcode *Any iOS Device* wählen, *Product › Archive*, im Organizer
   *Distribute App › TestFlight & App Store*.

## Stand

Roadmap aus dem Architektur-Dokument:

- [x] **1. Fundament:** Datenmodell, Core Data mit CloudKit (privat + geteilt), Familien anlegen und einladen,
      Beitreten mit eigenem Profil oder verknüpftem Kinderprofil, Kinderprofile, mehrere Familien
- [ ] Prototyp Owner-Übertragung (V1.1)
- [x] **2. Kalender:** Monatsansicht zum Blättern, Jahresansicht, Termine mit Teilnehmern, Farbsystem,
      Personenfilter, Serien (RRULE, Ausnahmen, nur dieser / folgende / alle), Kommentare,
      Geburtstage mit mitzählendem Alter (eigene Farbe, einstellbar unter Familie › Kalender)
  - Wochenansicht als Kacheln je Tag (Titel, Uhrzeit, Dauer) mit Wochenleiste; Termine umrandet statt gefüllt
  - Lange auf einen Tag drücken legt dort einen Termin an; Termine und Todos per Ziehen auf einen anderen Tag
    verschieben (bei Serien mit Rückfrage)
  - Todos mit Fälligkeit im Kalender (abschaltbar unter Familie › Kalender)
  - Geburtstagsvorschläge: ganztägige Termine wie „Geburtstag Oma (1950)“ werden erkannt (`BirthdayDetector`)
    und lassen sich mit einem Tipp in Geburtstage umwandeln, Kopien aus anderen Jahren fallen dabei weg
- [x] **Onboarding** beim ersten Start: Begrüßung, Bedienung wählen, dann Familie anlegen, beitreten oder
      allein loslegen. Einladen und Beitreten auch per QR-Code (Familie › „Mit QR-Code einladen“ bzw.
      „+“ › „Mit QR-Code beitreten“): je Code ein Einmal-Link für eine Person
      (`CKShare.Participant.oneTimeURLParticipant`), der Share bleibt privat. Dafür braucht die App die
      Entitlement `com.apple.developer.icloud-extended-share-access` mit `InProcessOneTimeLinks`
      (`App/yafo.entitlements`), sonst stürzt CloudKit beim Erzeugen des Codes ab. Der Owner wählt, wen er
      einlädt: einen Erwachsenen (legt sein Profil selbst an) oder ein Kind mit eigenem Gerät – dessen
      Code ist am Kinderprofil vermerkt (`Member.inviteParticipantID`, neues Feld im CloudKit-Schema),
      und das Kind übernimmt sein Profil beim Beitritt ohne Nachfrage
- [x] **Verlassen und löschen** (Familie › „Verlassen oder löschen“): Mitglieder verlassen eine Familie (Profil
      bleibt als „ehemalig“), der Owner löscht sie für alle, und „Alle meine Daten löschen“ räumt den eigenen
      Kalender, private Listen, Einstellungen und eigene Familien ab – jeweils mit Dialog und zweiter Nachfrage,
      bei der der Familienname (bzw. „yafo“) einzutippen ist. Geteilte Familien gehen über
      `purgeObjectsAndRecordsInZone`, alles andere über Core-Data-Löschregeln und den normalen Sync
- [x] **Bedienung wählbar** (Familie › Bedienung, nur auf dem Gerät): „Tabs“ wie bisher oder „Wischen“ –
      ohne Tab-Leiste, Monate blättern nach oben und unten wie im Apple-Kalender, nach rechts wischen für Todos,
      nach links für die Einkaufsliste, unten eine kleine Seitenanzeige. „Familie“ ist in beiden ein Knopf
      oben rechts, kein eigener Tab
- [x] **3. Listen:** Einkaufsliste als Kacheln mit Piktogrammen, sortiert nach Abteilungen in Laufreihenfolge
      (mitgelieferter Artikelkatalog DE/EN), „Zuletzt gekauft“ und Vorschläge; Todos mit Fälligkeit,
      Zuständigen und Serien, die beim Abhaken weiterrollen; je Familie und „Nur ich“
- [x] **4. Erinnerungen und Widgets:** lokale Benachrichtigungen (die nächsten 64, an Teilnehmer bzw.
      Zuständige, Zeit pro Person änderbar oder stumm), Widget „Nächste Termine“ (klein, mittel, groß)
      und „Nächster Termin“ für den Sperrbildschirm; Widgets „Einkaufsliste“ und „Todos“ je Familie oder
      „Nur ich“, direkt im Widget abhakbar (wirksam in iCloud, sobald die App das nächste Mal geöffnet wird)
- [x] 5. Abos und Import (Feiertage, Ferien, ICS, EventKit)
  - Gesetzliche Feiertage je Kalender (16 Bundesländer, AT, CH), offline berechnet
  - Besondere Tage ohne Feiertagsstatus (Advent, Sankt Martin, Halloween, Muttertag …) zur Feiertagsregion,
    offline berechnet, als graue Einträge; abschaltbar unter Familie (`calendarShowsObservances`)
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
  - Bild teilen (Share Extension) oder im Kalender „+“ lange drücken › „Termin aus Screenshot“
  - Erkennung nur auf dem Gerät: Foundation Models mit Bild, sonst Vision-Texterkennung und Text-Modell,
    ohne Apple Intelligence `NSDataDetector` mit Wortarten für den Titel
  - Vorschau mit allen erkannten Terminen zum Anpassen, Ziel-Kalender, Hinweis auf schon vorhandene
  - Serien („jeden Dienstag“, „alle zwei Wochen“, „every Monday“) werden erkannt und sind in der Vorschau
    einstellbar; vollständige Adressen werden gleich in Apple Maps gefunden, für Namen wie „Aula“ gibt es
    Vorschläge zum Antippen
- [ ] 8. TestFlight, App Store
  - TestFlight läuft (Build 6). Store-Eintrag vorbereitet in `AppStore/`: Texte DE/EN, Screenshots für iPhone 6,9″/6,3″,
    iPad 13″ und iPhone Duo innen, Datenschutz- und Support-Seiten für GitHub Pages
  - Datenschutz und Support online: https://rainerzufall00.github.io/yafo/ (Branch `gh-pages`)
  - Offen: Duo-Screenshots zugeklappt, Version 1.0

## Lizenz

[MIT](LICENSE)
