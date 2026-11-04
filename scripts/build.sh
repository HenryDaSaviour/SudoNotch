#!/bin/bash
# Builds SudoNotch.app.
#   ./scripts/build.sh              build only (verifies the signature)
#   ./scripts/build.sh --install    build, copy to /Applications (or ~/Applications) and launch
#   ./scripts/build.sh --dmg        build a universal app and package dist/SudoNotch.dmg
#
# The bundle is assembled in a temp dir so no Finder metadata ends up inside it and breaks the code signature.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT="$PWD"


ARCHS=()
[[ "${1:-}" == "--dmg" ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} 2>&1 | grep -v "x86_64 architecture is deprecated" || true
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/SudoNotch"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

WORK="$(mktemp -d /tmp/sudonotch-build.XXXXXX)"
APP="$WORK/SudoNotch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SudoNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built + signed SudoNotch.app ($(lipo -archs "$APP/Contents/MacOS/SudoNotch"))"

COPY=(ditto --norsrc --noextattr --noqtn)

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications"
  [[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  pkill -x SudoNotch 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST/SudoNotch.app"
  "${COPY[@]}" "$APP" "$DEST/SudoNotch.app"
  codesign --verify --deep --strict "$DEST/SudoNotch.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/SudoNotch.app" || true
  open "$DEST/SudoNotch.app"
  echo "Installed and launched $DEST/SudoNotch.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  STAGE="$WORK/dmg"
  mkdir -p "$STAGE" "$PROJECT/dist"
  "${COPY[@]}" "$APP" "$STAGE/SudoNotch.app"
  ln -s /Applications "$STAGE/Applications"
  cp scripts/INSTALL.txt "$STAGE/READ ME FIRST.txt"
  rm -f "$WORK/SudoNotch.dmg" "$PROJECT/dist/SudoNotch.dmg"
  hdiutil create -quiet -volname "SudoNotch" -srcfolder "$STAGE" -ov -format UDZO "$WORK/SudoNotch.dmg"
  [[ -n "${SIGN_ID:-}" ]] && codesign --force --timestamp --sign "$SIGN_ID" "$WORK/SudoNotch.dmg"
  cp "$WORK/SudoNotch.dmg" "$PROJECT/dist/SudoNotch.dmg"
  echo "Created $PROJECT/dist/SudoNotch.dmg ($(du -h "$PROJECT/dist/SudoNotch.dmg" | cut -f1))"
fi
rm -rf "$WORK"
