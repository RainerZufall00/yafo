# App-Store-Release von yafo

Alles für den Eintrag in App Store Connect. Die Texte liegen im Layout von `fastlane deliver` und lassen sich so auch
automatisch hochladen. Von Hand kopieren geht genauso gut. Vorlage war der Release-Ordner von Auslese.

```
AppStore/
  metadata/
    de-DE/                Hauptsprache: Name, Untertitel, Beschreibung, Keywords, Werbetext, Neuerungen, URLs
    en-US/                Englisch
    review_information/   Hinweise für das App-Review (notes.txt; Kontaktdaten noch eintragen)
    copyright.txt, primary_category.txt, secondary_category.txt
  Screenshots/
    de-DE/, en-US/        je Sprache:
      iPhone-6.9/         7 Bilder, 1320 × 2868
      iPhone-6.3/         7 Bilder, 1206 × 2622 – für das Feld „6,1″/6,3″“ in App Store Connect
      iPad-13/            7 Bilder, 2064 × 2752 – Hochformat, Monat und Tagesliste nebeneinander
      iPhone-Duo-aussen/  5 Bilder, 1398 × 2034 – zugeklappt
      iPhone-Duo-innen/   5 Bilder, 2007 × 2853 – aufgeklappt
      Promo/              Querformat 1920 × 1080 für Website, Social Media, Presse
      Creative/           „Creative Assets“ (App Store Connect, Bereich „Asset-Bibliothek“):
                          header-3840x1646.png – Kopfzeile der Produktseite (21:9)
                          search-3840x2560.png – Suchergebnisse (3:2)
    raw/de, raw/en        Rohaufnahmen (nicht im Repo)
  Tools/
    capture-screenshots.sh     Rohaufnahmen im Simulator mit Demo-Daten (iPhone 18 Pro Max, iPad Pro 13″)
    capture-duo-screenshots.sh dasselbe fürs iPhone Duo, je Display ein Lauf (Falten von Hand im Device Hub)
    compose-screenshots.swift  Überschrift, Rahmen, Hintergrund in den Farben des App-Icons
    make-website.py            baut Website/site aus Datenschutz.md, Privacy.md und contact.json
    publish-website.sh         veröffentlicht Website/site auf GitHub Pages (Branch gh-pages)
  Datenschutz.md          Datenschutzerklärung (Deutsch) – Quelle für die Website
  Privacy.md              dieselbe auf Englisch
  Website/                Öffentliche Seiten für Support und Datenschutz (contact.json = Kontaktdaten, site/ = Ergebnis)
```

## Screenshots neu erzeugen

```bash
AppStore/Tools/capture-screenshots.sh                 # oder nur ein Gerät: … iphone bzw. … ipad, dazu Motive: … ipad "month dark"
AppStore/Tools/capture-duo-screenshots.sh innen <UDID> # Duo aufgeklappt; zugeklappt: … aussen <UDID>
swift AppStore/Tools/compose-screenshots.swift AppStore/Screenshots/raw AppStore/Screenshots
```

Jede Ansicht wird auf Deutsch und Englisch aufgenommen (`-AppleLanguages`). Die App startet dabei mit
`-screenshotDemo` (nur in Debug-Builds, siehe `App/Sources/Support/ScreenshotDemo.swift`): leere Stores im Speicher,
die erfundene Familie Sommer aus `DemoData.swift` (Anna, Ben, Mia, Leo), keine Nachfrage nach Mitteilungen, kein iCloud.
`-demoScreen` öffnet Ansichten, die sonst nur per Tippen erreichbar sind (`day`, `event`, `family`, `screenshot`).
Die Termine liegen rund um den Tag der Aufnahme, die Statusleiste zeigt 9:41.

Motive (je Gerät, außen/innen beim Duo je fünf davon):

| Motiv | Ansicht | Überschrift |
| --- | --- | --- |
| `month` | Monat (iPad mit Tagesliste) | Ein Kalender. Die ganze Familie. |
| `event` | Ausflug mit Teilnehmern und Kommentaren | Absprechen, wo es passiert. |
| `shopping` | Einkaufsliste nach Abteilungen | Einkaufen in Laufreihenfolge. |
| `todos` | Todos mit Zuständigen | Wer macht was? |
| `screenshot` | „Termin aus Screenshot“ mit Elternbrief | Aus Screenshot wird Termin. |
| `dark` | Wisch-Modus dunkel (iPhone Woche, iPad Monat) | Tabs oder Wischen. |
| `family` | Familie mit Mitgliedern und Kalendern | Kein Konto. Keine Werbung. |

Überschriften ändern: `german` und `english` in `compose-screenshots.swift`.

**„Termin aus Screenshot“:** Im Simulator gibt es kein Apple-Intelligence-Modell. Damit die Aufnahme zeigt, was die
Erkennung auf einem Gerät mit Apple Intelligence liefert, gibt `ScreenshotDemo.letterReading` für den gezeichneten
Elternbrief das Ergebnis fest vor (nur mit `-demoScreen screenshot`). Ohne Apple Intelligence erkennt yafo weniger
genau – das steht so auch in der Beschreibung.

**iPhone Duo:** braucht einen laufenden Duo-Simulator mit der Runtime `iOS-27-2-iPhone19-4`. Falten geht nur von Hand
im Device Hub; das Skript bricht ab, wenn das Display nicht passt. Zugeklappt öffnet sich der Simulator nach gut einer
Minute von selbst wieder – dann mit Motiven fortsetzen, z. B. `… aussen <UDID> "event family"`.

## Vor dem Einreichen

### Muss noch erledigt werden
- [x] **Datenschutz- und Support-URL:** liegen auf GitHub Pages im Branch `gh-pages` des öffentlichen Repos
      `RainerZufall00/yafo` (nur die Seiten, eigene Historie). Ändern: Texte bzw. `Tools/make-website.py`, dann
      `AppStore/Tools/publish-website.sh`.
  - Datenschutz: https://rainerzufall00.github.io/yafo/datenschutz/ · https://rainerzufall00.github.io/yafo/privacy/
  - Support: https://rainerzufall00.github.io/yafo/support/ · https://rainerzufall00.github.io/yafo/support/en/
  - Kontakt läuft vorerst über die Issues des Repos.
- [ ] Optional **Verantwortlicher und E-Mail auf der Website:** Bewusst weggelassen wie bei den anderen Apps; dort steht
      „der Entwickler von yafo (GitHub: RainerZufall00)“. Nachtragen ginge über `name`, `address`, `email` in
      `Website/contact.json` und neu veröffentlichen.
- [ ] **Copyright**: In `copyright.txt` steht vorläufig „2026 Matthias“ – vollständigen Namen eintragen.
- [ ] **Review-Kontakt**: Name, E-Mail, Telefon in App Store Connect bzw. `review_information/`.
- [ ] **Name prüfen**: Ist „yafo – Familien-Organizer“ im App Store frei? Beim Anlegen sagt App Store Connect Bescheid.
- [ ] **CloudKit nach Production deployen** (siehe Haupt-README, Abschnitt TestFlight) – nach jeder Modelländerung.
- [ ] **Version**: `MARKETING_VERSION` steht auf 0.1. Für den ersten Store-Release auf 1.0 setzen, Build hochzählen,
      archivieren und hochladen.
- [ ] **Neuerungen**: Bei der ersten Version zeigt App Store Connect das Feld nicht; `release_notes.txt` ist für 1.0.1 ff.

### App Store Connect – Angaben

| Feld | Wert |
| --- | --- |
| Hauptsprache | Deutsch, dazu Englisch (USA) als zweite Sprache |
| Name | yafo – Familien-Organizer (25/30) · yafo – Family Organizer (23/30) |
| Untertitel | Kalender, Einkauf & Todos (25/30) · Calendar, shopping & to-dos (27/30) |
| Kategorie | Produktivität, zweite Kategorie Lifestyle |
| Preis | Kostenlos, keine In-App-Käufe |
| Verfügbarkeit | Weltweit – App und Store-Eintrag auf Deutsch und Englisch. Feiertage und Schulferien nur für DE/AT/CH. |
| Bundle-ID | de.yafo.app |
| Exportkontrolle | Keine eigene Verschlüsselung – `ITSAppUsesNonExemptEncryption = NO` ist gesetzt |
| Plattformen | iPhone, iPad; Mac (Apple Silicon) als iPad-App nach Wunsch freigeben |

### App-Datenschutz („Nutzungsdaten“)

**„Daten werden nicht erfasst“.** Begründung: Der Entwickler empfängt keinerlei Daten. Alles liegt auf dem Gerät und
in der privaten bzw. geteilten iCloud-Datenbank der Nutzer, die der Entwickler nicht lesen kann – nach Apples
Definition gilt das nicht als „erfasst“. Schulferien (OpenHolidays API) und Kalender-Abos ruft das Gerät direkt ab,
ohne Bezug zur Person. `PrivacyInfo.xcprivacy` passt dazu (kein Tracking, keine erfassten Datentypen).

### Altersfreigabe

Die Fragen selbst beantworten. Hinweise:
- Keine Werbung, kein Glücksspiel, keine Inhalte Dritter außer abonnierten Kalendern.
- **Nutzergenerierte Inhalte/Kommunikation:** Kommentare an Terminen sehen nur Mitglieder derselben Familie, die
  sich gegenseitig eingeladen haben – kein öffentlicher Austausch, keine Fremden. Ehrlich beantworten.
- Kein uneingeschränkter Webzugriff (Links öffnen Karten bzw. Safari nur aus Termin-Orten und Notizen).

### Creative Assets (Kopfzeile und Suchergebnisse)

In App Store Connect unter der Asset-Bibliothek pro Sprache hochladen: `header-3840x1646.png` als Kopfzeile der
Produktseite, `search-3840x2560.png` für die Suchergebnisse. Apple beschneidet die Bilder stark und legt Icon, Name und
Laden-Knopf darüber; das Wichtige steht deshalb mittig. Vor dem Einreichen mit der Vorschau prüfen (auch im Dark Mode).

### Review-Hinweise

Stehen auf Englisch in `review_information/notes.txt`: kein Login nötig, Ablauf zum Testen auf einem Gerät,
Berechtigungen, externe Dienste (CloudKit, OpenHolidays, ICS-Abos, MapKit, Erkennung auf dem Gerät).
