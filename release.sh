#!/bin/bash
# Cuts a release: builds, packages a drag-to-Applications DMG, signs it for Sparkle, and
# regenerates the update feed.
#
#   ./release.sh                 build + DMG (self-signed)
#   ./release.sh --notarize      also notarize with Apple (needs a Developer ID — see below)
#
# Notarizing requires the paid Apple Developer Program and these environment variables:
#   CODESIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE      a keychain profile made with:
#                       xcrun notarytool store-credentials NOTARY_PROFILE \
#                         --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# Without it the DMG still works, but recipients have to approve an "unidentified developer"
# warning on first launch: System Settings › Privacy & Security › Open Anyway on macOS 15+,
# or right-click → Open on macOS 14. Apple removed the right-click route in Sequoia.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClipIt"
VERSION="$(cat VERSION)"
NOTARIZE=0
[ "${1:-}" = "--notarize" ] && NOTARIZE=1

STAGE=".build/stage"
APP="$STAGE/$APP_NAME.app"
DIST="dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "==> Testing"
swift test 2>&1 | tail -3

echo "==> Building $APP_NAME $VERSION"
NO_INSTALL=1 ./build.sh >/dev/null
mkdir -p "$DIST"

if [ "$NOTARIZE" = "1" ]; then
    if [ -z "${CODESIGN_IDENTITY:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
        echo "!! --notarize needs CODESIGN_IDENTITY and NOTARY_PROFILE set. See the header."
        exit 1
    fi
fi

# --- DMG -------------------------------------------------------------------
# A staging folder with the app and a symlink to /Applications, so the window shows the
# familiar drag-across gesture and a non-technical user knows what to do without instructions.
echo "==> Packaging $DMG"
DMG_ROOT="$(mktemp -d)"
trap 'rm -rf "$DMG_ROOT"' EXIT
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -ov -format UDZO \
    "$DMG" >/dev/null

# --- Notarization ----------------------------------------------------------
if [ "$NOTARIZE" = "1" ]; then
    echo "==> Signing DMG"
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"

    echo "==> Submitting to Apple (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
else
    echo "==> Not notarized: first launch needs Privacy & Security › Open Anyway (macOS 15+)"
    echo "    or right-click → Open (macOS 14)."
fi

# --- Sparkle feed ----------------------------------------------------------
# generate_appcast reads every archive in the folder, signs each with the private EdDSA key
# from the keychain, and writes the feed the app polls.
GENERATE_APPCAST="$(find .build/artifacts/sparkle -type f -name generate_appcast | head -1)"
if [ -n "$GENERATE_APPCAST" ]; then
    echo "==> Updating appcast.xml"
    "$GENERATE_APPCAST" \
        --download-url-prefix "https://github.com/quillerpl/clipit/releases/download/v$VERSION/" \
        "$DIST" >/dev/null
    [ -f "$DIST/appcast.xml" ] && mv "$DIST/appcast.xml" appcast.xml
    echo "    appcast.xml written — commit it so the update feed goes live."
else
    echo "!! Sparkle tools missing; skipping appcast. Run 'swift package resolve' first."
fi

echo
echo "==> Ready: $DMG"
echo "    Next:  gh release create v$VERSION \"$DMG\" --title \"$APP_NAME $VERSION\" --notes-file CHANGELOG.md"
echo "           git add appcast.xml && git commit -m \"Release $VERSION\" && git push"
