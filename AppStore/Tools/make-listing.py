#!/usr/bin/env python3
"""Baut AppStore/listing.md aus AppStore/metadata: alle Store-Texte zum Kopieren nach App Store Connect,
mit Zeichenzahl und Grenze. Quelle bleiben die .txt-Dateien (fastlane-Layout), listing.md wird nur erzeugt.

    python3 AppStore/Tools/make-listing.py                 # alle Sprachen -> AppStore/listing.md
    python3 AppStore/Tools/make-listing.py en-US           # nur diese Sprache(n), in dieser Reihenfolge
    python3 AppStore/Tools/make-listing.py --out x.md --contact de-DE en-US

--contact nimmt den Review-Kontakt aus review_information/ mit auf (nur für private Kopien, nie committen).
"""
import argparse, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
META = ROOT / "AppStore/metadata"

# (Datei, Grenze, englische Beschriftung, deutsche Beschriftung) in der Reihenfolge von App Store Connect
FIELDS = [
    ("name", 30, "Name", "Name"),
    ("subtitle", 30, "Subtitle", "Untertitel"),
    ("promotional_text", 170, "Promotional Text", "Werbetext"),
    ("description", 4000, "Description", "Beschreibung"),
    ("keywords", 100, "Keywords", "Schlüsselwörter"),
    ("support_url", None, "Support URL", "Support-URL"),
    ("marketing_url", None, "Marketing URL", "Marketing-URL"),
    ("privacy_url", None, "Privacy Policy URL", "Datenschutzrichtlinien-URL"),
    ("release_notes", 4000, "What's New in This Version", "Neuerungen in dieser Version"),
]
LANGUAGES = {"de-DE": "Deutsch (de-DE)", "en-US": "English (U.S.) (en-US)"}
CATEGORIES = {"PRODUCTIVITY": "Productivity / Produktivität", "LIFESTYLE": "Lifestyle",
              "UTILITIES": "Utilities / Dienstprogramme", "DEVELOPER_TOOLS": "Developer Tools / Entwickler-Tools"}


def read(path):
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def block(text):
    return f"```text\n{text}\n```\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("languages", nargs="*")
    parser.add_argument("--out", default=str(ROOT / "AppStore/listing.md"))
    parser.add_argument("--contact", action="store_true")
    args = parser.parse_args()
    languages = args.languages or sorted(p.name for p in META.glob("*-*") if p.is_dir())

    name = read(META / "en-US/name.txt") or read(META / f"{languages[0]}/name.txt")
    out = [f"# App Store listing – {name}\n",
           "Everything to paste into App Store Connect. Generated from `AppStore/metadata` by "
           "`AppStore/Tools/make-listing.py` – edit the .txt files there, then run the script again. "
           "Character counts in brackets (used/limit). Price, App Privacy and age rating: `AppStore/README.md`.\n",
           "## Shared\n",
           f"- **Primary category:** {CATEGORIES.get(read(META / 'primary_category.txt'), read(META / 'primary_category.txt'))}",
           f"- **Secondary category:** {CATEGORIES.get(read(META / 'secondary_category.txt'), read(META / 'secondary_category.txt'))}",
           f"- **Copyright:** {read(META / 'copyright.txt')}",
           f"- **Languages in this file:** {', '.join(languages)}\n"]
    failed = False
    for lang in languages:
        german = lang.startswith("de")
        out.append(f"## {LANGUAGES.get(lang, lang)}\n")
        for file, limit, en, de in FIELDS:
            text = read(META / lang / f"{file}.txt")
            if not text:
                continue
            label = de if german else en
            if limit:
                ok = len(text) <= limit and not (file == "keywords" and ", " in text)
                failed |= not ok
                label += f" ({len(text)}/{limit})" + ("" if ok else " – TOO LONG")
            if file == "release_notes":
                label += (" – erst ab dem zweiten Update" if german else " – only from the second version on")
            out.append(f"### {label}\n")
            out.append(block(text))

    notes = read(META / "review_information/notes.txt")
    if notes or args.contact:
        out.append("## App Review Information\n")
    if args.contact:
        contact = {k: read(META / f"review_information/{k}.txt")
                   for k in ("first_name", "last_name", "phone_number", "email_address")}
        for key, value in contact.items():
            out.append(f"- **{key.replace('_', ' ').capitalize()}:** {value or '(missing)'}")
        out.append("")
    if notes:
        out.append(f"### Notes ({len(notes)}/4000)\n")
        out.append(block(notes))

    pathlib.Path(args.out).write_text("\n".join(out), encoding="utf-8")
    print(f"{args.out}: {', '.join(languages)}" + (" – TEXT TOO LONG" if failed else ""))
    sys.exit(1 if failed else 0)


main()
