#!/bin/sh
# Xcode Cloud: runs right after cloning. Config/Local.xcconfig (the team ID) is
# ignored by Git, so it's created here; Xcode Cloud sets CI_TEAM_ID itself.
set -e

cat > "$CI_PRIMARY_REPOSITORY_PATH/Config/Local.xcconfig" <<XCCONFIG
DEVELOPMENT_TEAM = ${CI_TEAM_ID}
XCCONFIG
