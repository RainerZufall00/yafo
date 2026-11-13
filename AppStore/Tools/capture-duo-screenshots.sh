#!/bin/zsh
# Nimmt die Rohaufnahmen fürs iPhone Duo auf, je Display ein Lauf – mit denselben Demo-Daten wie capture-screenshots.sh.
# Aufruf im Repo-Wurzelverzeichnis: AppStore/Tools/capture-duo-screenshots.sh aussen|innen <Simulator-UDID> [Motive]
# Motive schränken den Lauf ein, z. B. "month family". Zugeklappt nötig: Der Simulator öffnet sich nach gut einer Minute
# von selbst wieder, fünf Motive in zwei Sprachen schafft er deshalb nicht immer am Stück – dann mit Motiven fortsetzen.
# Danach: swift AppStore/Tools/compose-screenshots.swift AppStore/Screenshots/raw AppStore/Screenshots duo
#
# Das Duo braucht einen laufenden Simulator mit der eigenen Runtime (iOS-27-2-iPhone19-4, die normale schließt es aus).
# Falten lässt sich nicht per Skript steuern: Vorher im Device Hub zu- bzw. aufklappen und hochkant halten, sonst bleibt
# das Bild schwarz oder quer. Die Sprache gilt nur für die App: Ein Neustart des Simulators würde das Falten zurücksetzen.
# Vorlage: dasselbe Skript in Auslese.

set -e
KIND=$1
UDID=$2
ONLY_SHOTS=(${=3})
[[ $KIND == (aussen|innen) && -n $UDID ]] || { echo "Aufruf: $0 aussen|innen <Simulator-UDID> [Motive]"; exit 1 }
cd "$(dirname "$0")/../.."
RAW=$PWD/AppStore/Screenshots/raw
BUILD=.build/screenshots
BUNDLE=de.yafo.app
if [[ $KIND == aussen ]]; then SCREEN=primary PREFIX=duo-outer WIDTH=1398
else SCREEN=primary-1 PREFIX=duo-inner WIDTH=2007; fi

echo "Baue …"
xcodebuild -project yafo.xcodeproj -scheme yafo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath $BUILD ARCHS=arm64 build -quiet
xcrun simctl uninstall $UDID $BUNDLE 2>/dev/null || true
xcrun simctl install $UDID $BUILD/Build/Products/Debug-iphonesimulator/yafo.app

shot() { # Motiv, hell/dunkel, Wartezeit, Startargumente … – Sprache aus $LANG_CODE
  [[ -z $ONLY_SHOTS || ${ONLY_SHOTS[(ie)$1]} -le ${#ONLY_SHOTS} ]] || return 0
  xcrun simctl ui $UDID appearance $2
  xcrun simctl terminate $UDID $BUNDLE >/dev/null 2>&1 || true
  local args=(${@:4})
  for key value in -interfaceStyle tabs -calendarMode month -launchTab calendar; do
    (( ${args[(Ie)$key]} )) || args+=($key $value)
  done
  # Direkt nach dem Neustart des Simulators scheitert der Start manchmal – dann kurz warten und noch einmal.
  local try
  for try in 1 2 3; do
    xcrun simctl launch $UDID $BUNDLE -screenshotDemo -AppleLanguages "($LANG_CODE)" -AppleLocale $LOCALE $args \
      >/dev/null 2>&1 && break
    (( try == 3 )) && { echo "Start fehlgeschlagen: $1"; exit 1 }
    sleep 5
  done
  sleep $3
  mkdir -p $RAW/$LANG_CODE
  local file=$RAW/$LANG_CODE/$PREFIX-$1.png
  rm -f $file
  xcrun simctl io $UDID screenshot --display=$SCREEN $file >/dev/null 2>&1
  # Falsch gehalten oder gefaltet: quer oder leer (bis gut 100 KB) – dann lieber gleich abbrechen als leere Bilder sammeln.
  local width=$(sips -g pixelWidth $file | tail -1 | awk '{print $2}')
  local bytes=$(stat -f %z $file)
  if [[ $width != $WIDTH || $bytes -lt 200000 ]]; then
    echo "Abbruch: $PREFIX-$1 ist $width px breit und $bytes Bytes groß. Duo im Device Hub falten und hochkant halten."
    exit 1
  fi
  echo $file
}

# Nur die Uhrzeit: Weitere Angaben lehnt der Duo-Simulator mit einer irreführenden Meldung zum Datum ab.
xcrun simctl status_bar $UDID override --time "09:41"

for LANG_CODE LOCALE in de de_DE en en_US; do
  if [[ $KIND == aussen ]]; then
    shot month    light 6
    shot shopping light 6 -launchTab shopping
    shot todos    light 6 -launchTab todos
    shot event    light 7 -demoScreen event
    shot family   light 6 -demoScreen family
  else
    shot month      light 6
    shot screenshot light 7 -demoScreen screenshot
    shot dark       dark  6 -interfaceStyle swipe
    shot shopping   light 6 -launchTab shopping
    shot event      light 7 -demoScreen event
  fi
done

xcrun simctl status_bar $UDID clear
xcrun simctl ui $UDID appearance light
