#!/bin/bash
# Usage / 用法:
#   ./build.sh            build build/Quotlet.app (this Mac's architecture)
#   ./build.sh install    build, copy to /Applications and launch
#   ./build.sh release    universal (Apple silicon + Intel) build: dist/Quotlet-<version>.zip and .dmg
#
# Signing for release:
#   If a "Developer ID Application" certificate is in your keychain, the release is signed with it
#   (hardened runtime), notarized with the notarytool profile in $NOTARY_PROFILE (default
#   "quotabar-notary") and stapled. Otherwise the app is ad-hoc signed and macOS warns on first launch.
#   One-time setup:  xcrun notarytool store-credentials quotabar-notary --team-id <TEAM_ID>
#   (the profile keeps its pre-rename name "quotabar-notary"; it is only a keychain label)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Quotlet"
APP="build/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
NOTARY_PROFILE="${NOTARY_PROFILE:-quotabar-notary}"

ARGS=(-c release)
if [[ "${1:-}" == "release" ]]; then
    ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${ARGS[@]}"
BIN_DIR=$(swift build "${ARGS[@]}" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Sources/Quotlet/ProviderAssets/*.png "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Signing identity: Developer ID for releases when available, ad-hoc otherwise.
IDENTITY="-"
if [[ "${1:-}" == "release" ]]; then
    FOUND=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
    [[ -n "$FOUND" ]] && IDENTITY="$FOUND"
fi

if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP" >/dev/null
    echo "Built $APP ($VERSION, ad-hoc signed)"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict "$APP"
    echo "Built $APP ($VERSION, signed by $IDENTITY)"
fi

notarize() {   # notarize <file>   (retries: the upload sometimes times out on slow networks)
    for attempt in 1 2 3; do
        echo "Notarizing $1 (attempt $attempt, usually takes a few minutes) ..."
        if xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m 2>&1 | tee /tmp/quotlet-notary.log \
            && grep -q "status: Accepted" /tmp/quotlet-notary.log; then
            return 0
        fi
        sleep 10
    done
    echo "Notarization failed for $1" >&2
    return 1
}

case "${1:-}" in
    install)
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
        rm -rf "/Applications/$APP_NAME.app"
        cp -R "$APP" /Applications/
        open "/Applications/$APP_NAME.app"
        echo "Installed and launched /Applications/$APP_NAME.app"
        ;;
    release)
        mkdir -p dist
        ZIP="dist/$APP_NAME-$VERSION.zip"
        DMG="dist/$APP_NAME-$VERSION.dmg"
        rm -f "$ZIP" "$DMG"

        if [[ "$IDENTITY" != "-" ]]; then
            # Notarize the app (submitted as a zip), then staple the ticket into the bundle.
            ditto -c -k --keepParent "$APP" "$ZIP"
            notarize "$ZIP"
            xcrun stapler staple "$APP"
            rm -f "$ZIP"
        fi
        ditto -c -k --keepParent "$APP" "$ZIP"

        # DMG: Quotlet.app + a shortcut to /Applications, so users drag to install.
        STAGE=$(mktemp -d)
        cp -R "$APP" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
        rm -rf "$STAGE"
        if [[ "$IDENTITY" != "-" ]]; then
            codesign --force --timestamp --sign "$IDENTITY" "$DMG"
            notarize "$DMG"
            xcrun stapler staple "$DMG"
            spctl --assess --type open --context context:primary-signature -v "$DMG" || true
        fi

        shasum -a 256 "$ZIP" "$DMG"
        echo "Release files: $ZIP $DMG"
        ;;
esac
