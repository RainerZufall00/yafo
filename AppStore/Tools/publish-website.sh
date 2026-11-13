#!/bin/zsh
# Veröffentlicht die Seiten aus AppStore/Website/site auf GitHub Pages – im Branch gh-pages des öffentlichen Repos
# RainerZufall00/yafo. Der Branch enthält nur die Seiten, keinen App-Code, und hat eine eigene Historie.
# Aufruf im Repo-Wurzelverzeichnis: AppStore/Tools/publish-website.sh
#
# Commits laufen unter der anonymen noreply-Adresse von GitHub, damit weder Name noch private E-Mail in der öffentlichen
# Historie stehen.
# Adressen: https://rainerzufall00.github.io/yafo/datenschutz/ · /privacy/ · /support/ · /support/en/

set -e
cd "$(dirname "$0")/../.."
OWNER=RainerZufall00
REPO=yafo
BRANCH=gh-pages
AUTHOR="RainerZufall00 <143890973+RainerZufall00@users.noreply.github.com>"

python3 AppStore/Tools/make-website.py >/dev/null

WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT
if git ls-remote --exit-code --heads https://github.com/$OWNER/$REPO.git $BRANCH >/dev/null 2>&1; then
  git clone -q --single-branch --branch $BRANCH https://github.com/$OWNER/$REPO.git $WORK
else
  git -C $WORK init -q -b $BRANCH
  git -C $WORK remote add origin https://github.com/$OWNER/$REPO.git
fi

rsync -a --delete --exclude .git AppStore/Website/site/ $WORK/
touch $WORK/.nojekyll

git -C $WORK add -A
if git -C $WORK diff --cached --quiet; then
  echo "Keine Änderungen."
else
  git -C $WORK -c user.name="${AUTHOR% <*}" -c user.email="${${AUTHOR#*<}%>}" commit -q \
    -m "Seiten aktualisiert" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  git -C $WORK push -q -u origin $BRANCH
  echo "Gepusht."
fi

if ! gh api repos/$OWNER/$REPO/pages >/dev/null 2>&1; then
  gh api -X POST repos/$OWNER/$REPO/pages -f "source[branch]=$BRANCH" -f "source[path]=/" >/dev/null
  echo "GitHub Pages eingeschaltet."
fi
echo "https://rainerzufall00.github.io/$REPO/"
