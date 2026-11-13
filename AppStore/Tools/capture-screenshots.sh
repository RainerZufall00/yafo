#!/bin/zsh
# Nimmt die Rohaufnahmen für den App Store im Simulator auf – mit festen Demo-Daten (siehe
# App/Sources/Support/ScreenshotDemo.swift und DemoData.swift).
# Aufruf im Repo-Wurzelverzeichnis: AppStore/Tools/capture-screenshots.sh [iphone|ipad] [Motive]
# Ohne Angabe beide Geräte und alle Motive; Motive schränken ein, z. B. "month event".
# Danach: swift AppStore/Tools/compose-screenshots.swift AppStore/Screenshots/raw AppStore/Screenshots
#
# Jede Ansicht wird auf Deutsch und Englisch aufgenommen (raw/de, raw/en) – dafür wechselt auch die Systemsprache der
# Simulatoren, damit Statusleiste, Wochenbeginn und Uhrzeitformat zur App passen.
# Legt eigene Simulatoren an („yafo Shots iPhone/iPad“), damit laufende Simulatoren unberührt bleiben.
# Die Termine liegen rund um den Tag der Aufnahme; die Statusleiste zeigt immer 9:41.
# Auch im Hochformat stehen auf dem iPad Monat und Tagesliste nebeneinander.

set -e
ONLY=$1
ONLY_SHOTS=(${=2})
cd "$(dirname "$0")/../.."
RAW=$PWD/AppStore/Screenshots/raw
BUILD=.build/screenshots
BUNDLE=de.yafo.app
mkdir -p $RAW

runtime=$(xcrun simctl list runtimes | grep -E '^iOS' | grep -v iPhone19 | tail -1 | sed -E 's/.*\) - (.*)$/\1/')

device() { # Name, Gerätetyp
  local id=$(xcrun simctl list devices | grep "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [[ -z $id ]] && id=$(xcrun simctl create "$1" "$2" "$runtime")
  xcrun simctl boot $id 2>/dev/null || true
  xcrun simctl bootstatus $id >/dev/null
  echo $id
}

echo "Baue …"
xcodebuild -project yafo.xcodeproj -scheme yafo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath $BUILD ARCHS=arm64 build -quiet
APP=$BUILD/Build/Products/Debug-iphonesimulator/yafo.app

DEVICES=()
[[ $ONLY != ipad ]] && IPHONE=$(device "yafo Shots iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max) && DEVICES+=$IPHONE
[[ $ONLY != iphone ]] && IPAD=$(device "yafo Shots iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB) && DEVICES+=$IPAD
# Frisch installieren: Keine alten Einstellungen und kein offener Mitteilungs-Dialog aus einem früheren Lauf.
for id in $DEVICES; do
  xcrun simctl uninstall $id $BUNDLE 2>/dev/null || true
  xcrun simctl install $id $APP
done

language() { # Gerät, Sprache, Locale – braucht einen Neustart des Simulators
  xcrun simctl spawn $1 defaults write -g AppleLanguages -array $2
  xcrun simctl spawn $1 defaults write -g AppleLocale $3
  xcrun simctl shutdown $1 2>/dev/null || true
  xcrun simctl boot $1
  xcrun simctl bootstatus $1 >/dev/null
}

shot() { # Gerät, Dateiname, hell/dunkel, Wartezeit, Startargumente … – Sprache aus $LANG_CODE
  [[ -z $1 ]] && return # Gerät nicht gewählt
  local name=${2#*-}
  [[ -z $ONLY_SHOTS || ${ONLY_SHOTS[(ie)$name]} -le ${#ONLY_SHOTS} ]] || return 0
  xcrun simctl ui $1 appearance $3
  xcrun simctl terminate $1 $BUNDLE >/dev/null 2>&1 || true
  xcrun simctl status_bar $1 override --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  # Voreinstellungen, soweit das Motiv sie nicht selbst setzt (doppelte Argumente wären nicht eindeutig).
  local args=(${@:5})
  for key value in -interfaceStyle tabs -calendarMode month -launchTab calendar; do
    (( ${args[(Ie)$key]} )) || args+=($key $value)
  done
  # Direkt nach dem Neustart des Simulators scheitert der Start manchmal – dann kurz warten und noch einmal.
  local try
  for try in 1 2 3; do
    xcrun simctl launch $1 $BUNDLE -screenshotDemo -AppleLanguages "($LANG_CODE)" -AppleLocale $LOCALE $args \
      >/dev/null 2>&1 && break
    (( try == 3 )) && { echo "Start fehlgeschlagen: $2"; exit 1 }
    sleep 5
  done
  sleep $4
  mkdir -p $RAW/$LANG_CODE
  rm -f $RAW/$LANG_CODE/$2.png
  xcrun simctl io $1 screenshot $RAW/$LANG_CODE/$2.png >/dev/null 2>&1
  echo $RAW/$LANG_CODE/$2.png
}

for LANG_CODE LOCALE in de de_DE en en_US; do
  for id in $DEVICES; do language $id $LANG_CODE $LOCALE; done
  sleep 5
  for dev prefix in "$IPHONE" iphone "$IPAD" ipad; do
    shot "$dev" $prefix-month      light 6
    shot "$dev" $prefix-event      light 7 -demoScreen event
    shot "$dev" $prefix-shopping   light 6 -launchTab shopping
    shot "$dev" $prefix-todos      light 6 -launchTab todos
    shot "$dev" $prefix-screenshot light 7 -demoScreen screenshot
    # Dunkel im Wisch-Modus. iPhone: Woche, iPad: Monat – die Woche wirkt dort neben der Tagesliste leer.
    [[ $prefix == ipad ]] && mode=month || mode=week
    shot "$dev" $prefix-dark       dark  6 -calendarMode $mode -interfaceStyle swipe
    shot "$dev" $prefix-family     light 6 -demoScreen family
  done
done

for id in $DEVICES; do xcrun simctl status_bar $id clear; xcrun simctl ui $id appearance light; done
