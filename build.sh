#!/bin/bash
# Builds Magwell.app and installs it to /Applications.
#
#   ./build.sh              release build, install, run
#   CONFIG=debug ./build.sh debug build
#   NO_INSTALL=1 ./build.sh leave the bundle in .build/stage only
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Magwell"
BUNDLE_ID="com.jacks.magwell"
VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
CONFIG="${CONFIG:-release}"

# Where releases are published. Sparkle reads this feed to find updates.
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/quillerpl/magwell/main/appcast.xml}"
# Public half of the EdDSA key pair; the private half lives in the keychain (generate_keys).
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-PI+HEDqNaEWl3wkbavV4GzbFxoqsvRpidn+49dE2Bzk=}"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Staged under .build, never left as a second .app beside the source. Two bundles sharing one
# bundle identifier make both LaunchServices and TCC pick the wrong one.
STAGE=".build/stage"
APP="$STAGE/$APP_NAME.app"
mkdir -p "$STAGE"

# Release builds are universal so the DMG runs on Intel Macs too — an arm64-only binary just
# fails to open there, with no useful explanation for the person you sent it to.
ARCH_FLAGS=()
if [ "$CONFIG" = "release" ] && [ "${UNIVERSAL:-1}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling $APP_NAME $VERSION ($CONFIG${ARCH_FLAGS+, universal})"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_PATH="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# --- Sparkle ---------------------------------------------------------------
SPARKLE_FRAMEWORK="$(find .build/artifacts/sparkle -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    echo "==> Embedding Sparkle"
    cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
else
    echo "==> Sparkle not found — build will run without auto-update"
fi

# --- Icon ------------------------------------------------------------------
# Drawn by the app itself (IconRenderer) so it regenerates cleanly at every size. Run the
# *bundled* copy: the loose binary's @rpath points at Contents/Frameworks, which only exists
# once the bundle is assembled and Sparkle is in place.
echo "==> Rendering icon"
ICONSET="$STAGE/$APP_NAME.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/$APP_NAME" --make-icon "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>          <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
    <key>NSHumanReadableCopyright</key>  <string>MIT licensed. No data leaves your Mac.</string>
    <key>SUFeedURL</key>                 <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>             <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>   <true/>
</dict>
</plist>
PLIST

# --- Signing ---------------------------------------------------------------
# A stable code identity is what makes the Accessibility grant survive a rebuild; an ad-hoc
# signature gets a new hash every time, so macOS silently forgets the permission.
# Note: `find-identity -p codesigning` lists only TRUSTED identities and will not show a
# self-signed cert, so look the certificate up directly — codesign accepts it either way.
# The hardened runtime turns on library validation, which demands that every loaded framework
# share the host's Team ID. A self-signed certificate has no Team ID, so an embedded Sparkle
# would fail to load at launch. Notarization requires the hardened runtime, and a real
# Developer ID gives both halves the same team — so enable it only on that path.
SIGN_OPTIONS=()   # bash 3.2 needs the ${x[@]+...} idiom to expand an empty array under `set -u`

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODESIGN_IDENTITY"                      # e.g. "Developer ID Application: ..."
    SIGN_OPTIONS=(--options runtime)
    echo "==> Signing with '$IDENTITY' (hardened runtime, notarizable)"
elif security find-certificate -c "Magwell Dev" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    IDENTITY="Magwell Dev"
    echo "==> Signing with '$IDENTITY' (Accessibility grant persists across rebuilds)"
else
    IDENTITY="-"
    echo "==> Signing ad-hoc — run ./make-signing-cert.sh to stop Accessibility resetting"
fi

# Inside-out: nested code must be sealed before the bundle that contains it. Sparkle ships
# pre-signed with its own Team ID, and dyld refuses to load a framework whose team differs
# from the host process — so every nested piece has to be re-signed with our identity, not
# just the outer framework. Errors are fatal here: a half-signed framework fails at launch.
SPARKLE_VERSION_DIR="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "$SPARKLE_VERSION_DIR" ]; then
    echo "==> Re-signing Sparkle"
    for nested in \
        "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" \
        "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc" \
        "$SPARKLE_VERSION_DIR/Updater.app" \
        "$SPARKLE_VERSION_DIR/Autoupdate"
    do
        [ -e "$nested" ] && codesign --force ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} --timestamp=none \
            --sign "$IDENTITY" "$nested" >/dev/null
    done
    # Sign the versioned bundle, not the symlinked top level.
    codesign --force ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} --timestamp=none --sign "$IDENTITY" \
        "$SPARKLE_VERSION_DIR" >/dev/null
fi
codesign --force ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} --timestamp=none --sign "$IDENTITY" "$APP" >/dev/null

# --- Install ---------------------------------------------------------------
# This project lives on an external volume mounted `noowners`, where TCC grants are unreliable,
# so the app always runs from /Applications on the internal disk.
if [ "${NO_INSTALL:-0}" != "1" ]; then
    DEST="/Applications/$APP_NAME.app"
    RUNNING=0
    if pgrep -f "$DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        RUNNING=1
        pkill -f "$DEST/Contents/MacOS/$APP_NAME" || true
        sleep 1
    fi
    rm -rf "$DEST"
    cp -R "$APP" /Applications/

    # cp does not tell LaunchServices anything. Without this the app is greyed out and
    # unselectable in the System Settings → Accessibility file picker.
    "$LSREGISTER" -f "$DEST" 2>/dev/null || true
    echo "==> Installed and registered $DEST"

    if [ "$IDENTITY" = "-" ]; then
        # Ad-hoc signatures get a fresh hash every build and TCC keys the grant to that hash,
        # so the old grant silently stops applying. Clear it so macOS re-asks honestly rather
        # than showing a switch that is on but inert.
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
        echo "    (ad-hoc build: Accessibility grant reset — re-enable Magwell in"
        echo "     System Settings › Privacy & Security › Accessibility.)"
    fi
    [ "$RUNNING" = "1" ] && open "$DEST"
fi

echo "==> Done"
