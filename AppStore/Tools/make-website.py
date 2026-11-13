#!/usr/bin/env python3
"""Baut die öffentlichen Seiten für den App Store: Datenschutz (de/en) und Support (de/en).

Quelle der Datenschutztexte sind AppStore/Datenschutz.md und AppStore/Privacy.md. Kontaktdaten kommen aus
AppStore/Website/contact.json (nicht im Repo, falls privat) bzw. bleiben als Platzhalter stehen.

Aufruf im Repo-Wurzelverzeichnis: python3 AppStore/Tools/make-website.py
Ergebnis: AppStore/Website/site/ – so wie es auf GitHub Pages o. Ä. veröffentlicht wird.
"""
import html
import json
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
SITE = os.path.join(ROOT, "Website", "site")

contact_path = os.path.join(ROOT, "Website", "contact.json")
contact = json.load(open(contact_path)) if os.path.exists(contact_path) else {}
EMAIL = contact.get("email", "")
NAME = contact.get("name", "")
ADDRESS = contact.get("address", "")
# Ohne E-Mail-Adresse läuft der Kontakt über die Issues des öffentlichen Repos.
ISSUES = contact.get("issues", "")
GITHUB = contact.get("github", "")


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    text = re.sub(r"(https://[^\s<]+[^\s<.,;:)])", r'<a href="\1">\1</a>', text)
    return text


def markdown(source):
    """Genug Markdown für die Datenschutztexte: Überschriften, Absätze, Listen, fett, Code."""
    out, items, para = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in source.splitlines():
        if line.startswith("# "):
            flush(); out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            flush(); out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("- "):
            if para:
                out.append("<p>" + inline(" ".join(para)) + "</p>"); para.clear()
            items.append(line[2:])
        elif not line.strip():
            flush()
        else:
            para.append(line.strip())
    flush()
    return "\n".join(out)


def fill(text, lang):
    """Setzt die Kontaktdaten in die Platzhalter der Markdown-Texte ein."""
    responsible = ", ".join(x for x in [NAME, ADDRESS] if x)
    reach = EMAIL or ISSUES
    if lang == "de":
        if reach: text = text.replace("**[E-Mail-Adresse eintragen]**", reach)
        if responsible: text = text.replace("**[Name und ladungsfähige Anschrift eintragen]**", responsible)
        elif GITHUB: text = text.replace("**[Name und ladungsfähige Anschrift eintragen]**", f"der Entwickler von yafo (GitHub: {GITHUB})")
    else:
        if reach: text = text.replace("**[enter email address]**", reach)
        if responsible: text = text.replace("**[enter name and postal address]**", responsible)
        elif GITHUB: text = text.replace("**[enter name and postal address]**", f"the developer of yafo (GitHub: {GITHUB})")
    return text


STYLE = """
:root { --bg: #f3faf5; --ink: #0c2e1e; --muted: #56705f; --line: #d4e7da; --accent: #1d7a4f; --gold: #b38a00; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0b1f15; --ink: #eaf6ee; --muted: #9db8a7; --line: #23402f; --accent: #5fd39c; --gold: #ffd84d; color-scheme: dark; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; padding: 0 20px; }
main { max-width: 42rem; margin: 0 auto; padding-block: 48px 72px; }
header { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-bottom: 32px; }
.brand { font: 700 1.25rem ui-rounded, -apple-system, "SF Pro Rounded", sans-serif; color: var(--accent); text-decoration: none; }
nav { display: flex; gap: 14px; flex-wrap: wrap; font-size: .95rem; }
nav a, a { color: var(--accent); }
h1 { font: 700 2.2rem/1.15 ui-rounded, -apple-system, "SF Pro Rounded", sans-serif; margin: 0 0 12px; text-wrap: balance; }
h2 { font: 700 1.3rem/1.3 ui-rounded, -apple-system, "SF Pro Rounded", sans-serif; margin: 36px 0 8px; }
ul { padding-left: 1.2em; }
li { margin: 4px 0; }
code { font-family: ui-monospace, Menlo, monospace; font-size: .9em; }
.lead { color: var(--muted); font-size: 1.1rem; }
.mail { font-size: 1.15rem; font-weight: 600; }
.todo { background: #fff3c4; color: #0c2e1e; padding: 1px 6px; border-radius: 4px; }
footer { margin-top: 56px; padding-top: 16px; border-top: 1px solid var(--line); color: var(--muted); font-size: .9rem; display: flex; gap: 16px; flex-wrap: wrap; }
"""


def page(lang, title, body, other):
    nav = {
        "de": '<a href="../support/">Support</a><a href="../datenschutz/">Datenschutz</a>',
        "en": '<a href="../support/en/">Support</a><a href="../privacy/">Privacy</a>',
    }[lang]
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} – yafo</title>
<link rel="stylesheet" href="{'../' * other[1]}style.css">
</head>
<body>
<main>
<header><a class="brand" href="{'../' * other[1]}">yafo</a><nav>{nav}<a href="{other[0]}" hreflang="{'en' if lang == 'de' else 'de'}">{'English' if lang == 'de' else 'Deutsch'}</a></nav></header>
{body}
<footer><span>yafo – Familien-Organizer für iPhone und iPad</span><span>Schulferien: OpenHolidays API (ODbL)</span></footer>
</main>
</body>
</html>
"""


def contact_line(lang):
    if EMAIL:
        return f'<p class="mail"><a href="mailto:{html.escape(EMAIL)}">{html.escape(EMAIL)}</a></p>'
    if ISSUES:
        label = "Frage oder Fehler melden (GitHub)" if lang == "de" else "Ask a question or report a bug (GitHub)"
        return f'<p class="mail"><a href="{html.escape(ISSUES)}">{label}</a></p>'
    return '<p class="mail"><span class="todo">' + ("E-Mail-Adresse eintragen" if lang == "de" else "enter email address") + "</span></p>"


SUPPORT = {
    "de": ("Support", """<h1>Hilfe zu yafo</h1>
<p class="lead">Fragen, Fehler oder Wünsche? Schreib mir einfach – ich antworte so schnell ich kann.</p>
{contact}
<h2>Häufige Fragen</h2>
<h3>Wie lade ich meine Familie ein?</h3>
<p>Tippe oben rechts auf das Familien-Symbol und wähle „Mit QR-Code einladen“ oder „Mitglieder einladen“. Jeder QR-Code gilt für genau eine Person. Die andere Person scannt ihn mit yafo („+“ › „Mit QR-Code beitreten“) oder mit der Kamera und legt danach ihr eigenes Profil an.</p>
<h3>Braucht mein Kind ein eigenes Gerät?</h3>
<p>Nein. Lege unter Familie ein Kinderprofil an – das Kind kann dann an Terminen teilnehmen und Todos bekommen. Bekommt es später ein eigenes iPhone, lädst du es als Kind ein; es übernimmt sein Profil beim Beitritt.</p>
<h3>Warum sehen die anderen meine Änderungen nicht?</h3>
<p>yafo synchronisiert über iCloud. Prüfe, ob alle Geräte in iCloud angemeldet sind und iCloud Drive eingeschaltet ist. Änderungen aus Widgets übernimmt yafo, sobald die App das nächste Mal geöffnet wird.</p>
<h3>Wie übernehme ich meinen Google-Kalender?</h3>
<p>Unter Familie › „Termine importieren“: Gerätekalender, eine ICS-Adresse (in Google unter „Privatadresse im iCal-Format“) oder eine .ics-Datei. Eine ICS-Adresse kannst du auch in den Einstellungen eines Kalenders dauerhaft abonnieren; yafo aktualisiert sie beim Öffnen.</p>
<h3>Wie funktioniert „Termin aus Screenshot“?</h3>
<p>Teile ein Bild an yafo oder halte im Kalender „+“ gedrückt und wähle „Termin aus Screenshot“. yafo erkennt Datum, Uhrzeit, Ort und Wiederholung auf dem Gerät und zeigt eine Vorschau zum Anpassen. Mit Apple Intelligence ist die Erkennung genauer.</p>
<h3>Wie sichere ich meine Daten?</h3>
<p>yafo legt jede Woche automatisch ein Backup in deinem iCloud Drive ab (Ordner „yafo“). Unter Familie › „Export &amp; Backup“ kannst du jederzeit ein Backup teilen oder wiederherstellen sowie Termine als ICS und Listen als CSV exportieren.</p>
<h3>Werden meine Daten irgendwo anders gespeichert?</h3>
<p>Nein. yafo hat keinen eigenen Server und kein Konto. Mehr dazu in der <a href="../datenschutz/">Datenschutzerklärung</a>.</p>"""),
    "en": ("Support", """<h1>yafo Help</h1>
<p class="lead">Questions, bugs or ideas? Just get in touch – I’ll get back to you as soon as I can.</p>
{contact}
<h2>Frequently asked questions</h2>
<h3>How do I invite my family?</h3>
<p>Tap the family icon at the top right and choose “Invite with QR Code” or “Invite Members”. Each QR code works for exactly one person. The other person scans it in yafo (“+” › “Join with QR Code”) or with the Camera app and then sets up their own profile.</p>
<h3>Does my child need their own device?</h3>
<p>No. Create a child profile under Family – your child can then take part in events and be assigned to-dos. If they get their own iPhone later, invite them as a child; they take over their profile when joining.</p>
<h3>Why don’t the others see my changes?</h3>
<p>yafo syncs through iCloud. Check that every device is signed in to iCloud and that iCloud Drive is turned on. Changes made in widgets are applied the next time you open the app.</p>
<h3>How do I bring over my Google Calendar?</h3>
<p>Under Family › “Import Events”: device calendars, an ICS address (in Google: “Secret address in iCal format”) or an .ics file. You can also subscribe to an ICS address in a calendar’s settings; yafo refreshes it whenever you open the app.</p>
<h3>How does “Event from Screenshot” work?</h3>
<p>Share a picture to yafo, or long-press “+” in the calendar and choose “Event from Screenshot”. yafo picks out date, time, place and repetition on your device and shows a preview to adjust. With Apple Intelligence, recognition is more accurate.</p>
<h3>How do I back up my data?</h3>
<p>yafo automatically saves a backup to your iCloud Drive every week (folder “yafo”). Under Family › “Export &amp; Backup” you can share or restore a backup at any time and export events as ICS and lists as CSV.</p>
<h3>Is my data stored anywhere else?</h3>
<p>No. yafo has no server of its own and no account. More in the <a href="../../privacy/">privacy policy</a>.</p>"""),
}


def write(path, text):
    full = os.path.join(SITE, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write(text)
    print(os.path.relpath(full))


write("style.css", STYLE)
de = fill(open(os.path.join(ROOT, "Datenschutz.md")).read(), "de")
en = fill(open(os.path.join(ROOT, "Privacy.md")).read(), "en")
write("datenschutz/index.html", page("de", "Datenschutz", markdown(de), ("../privacy/", 1)))
write("privacy/index.html", page("en", "Privacy", markdown(en), ("../datenschutz/", 1)))
title, body = SUPPORT["de"]
write("support/index.html", page("de", title, body.format(contact=contact_line("de")), ("en/", 1)))
title, body = SUPPORT["en"]
# Englische Support-Seite liegt eine Ebene tiefer (support/en/) – Links entsprechend anpassen.
en_page = page("en", title, body.format(contact=contact_line("en")), ("../", 2))
en_page = en_page.replace('href="../support/en/"', 'href="./"').replace('href="../privacy/"', 'href="../../privacy/"')
write("support/en/index.html", en_page)
write("index.html", f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>yafo – Familien-Organizer für iPhone und iPad</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<main>
<header><span class="brand">yafo</span><nav><a href="support/">Support</a><a href="datenschutz/">Datenschutz</a><a href="privacy/">Privacy</a></nav></header>
<h1>Ein Kalender. Die ganze Familie.</h1>
<p class="lead">yafo ist ein kostenloser Familien-Organizer für iPhone und iPad: gemeinsamer Kalender, Einkaufsliste und Todos – geteilt über iCloud, ohne Konto, ohne Werbung, ohne Tracking.</p>
<p lang="en" class="lead">yafo is a free family organizer for iPhone and iPad: a shared calendar, shopping list and to-dos – shared via iCloud, with no account, no ads and no tracking.</p>
<footer><a href="support/">Support</a><a href="support/en/">Support (English)</a><a href="datenschutz/">Datenschutz</a><a href="privacy/">Privacy</a><a href="https://github.com/RainerZufall00/yafo">Quellcode / Source code</a></footer>
</main>
</body>
</html>
""")
