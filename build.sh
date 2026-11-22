#!/bin/bash
# Usage / 用法:
#   ./build.sh                   build build/Quotlet.app (this Mac's architecture)
#   ./build.sh install           build, copy to /Applications and launch
#   ./build.sh release           build Apple Silicon (arm64) + Intel (x86_64) releases:
#                                dist/Quotlet-<version>-arm64.{zip,dmg} and -x86_64.{zip,dmg}
#   ./build.sh release arm64     build only Apple Silicon release
#   ./build.sh release x86_64    build only Intel release
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

# Signing identity: prefer Developer ID Application when available so Keychain ACL stays stable across rebuilds.
IDENTITY="-"
FOUND=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
[[ -n "$FOUND" ]] && IDENTITY="$FOUND"

build_app() {   # build_app <dest_app_path> [arch]
    local dest="$1"
    local arch="${2:-}"
    local args=(-c release)
    if [[ -n "$arch" ]]; then
        args+=(--arch "$arch")
    fi

    swift build "${args[@]}"
    local bin_dir
    bin_dir=$(swift build "${args[@]}" --show-bin-path)
    local bin="$bin_dir/$APP_NAME"

    if [[ -n "$arch" ]]; then
        local built_archs
        built_archs=$(lipo -archs "$bin")
        if [[ "$built_archs" != "$arch" ]]; then
            echo "Expected architecture '$arch' in $bin, got '$built_archs'" >&2
            return 1
        fi
    fi

    rm -rf "$dest"
    mkdir -p "$dest/Contents/MacOS" "$dest/Contents/Resources"
    cp "$bin" "$dest/Contents/MacOS/"
    cp Resources/Info.plist "$dest/Contents/"
    cp Sources/Quotlet/ProviderAssets/*.png "$dest/Contents/Resources/"
    [[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$dest/Contents/Resources/"

    if [[ "$IDENTITY" == "-" ]]; then
        codesign --force --sign - "$dest" >/dev/null
        echo "Built $dest ($VERSION${arch:+, $arch}, ad-hoc signed)"
    else
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$dest"
        codesign --verify --strict "$dest"
        echo "Built $dest ($VERSION${arch:+, $arch}, signed by $IDENTITY)"
    fi
}

notarize() {   # notarize <file>   (retries: the upload sometimes times out on slow networks)
    local log_file
    log_file=$(mktemp /tmp/quotlet-notary.XXXXXX.log)
    for attempt in 1 2 3; do
        echo "Notarizing $1 (attempt $attempt, usually takes a few minutes) ..."
        if xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m 2>&1 | tee "$log_file" \
            && grep -q "status: Accepted" "$log_file"; then
            rm -f "$log_file"
            return 0
        fi
        sleep 10
    done
    rm -f "$log_file"
    echo "Notarization failed for $1" >&2
    return 1
}

package_arch_release() {   # package_arch_release <arch>
    local arch="$1"
    local arch_dir="build/release-$arch"
    local arch_app="$arch_dir/$APP_NAME.app"
    local zip="dist/$APP_NAME-$VERSION-$arch.zip"
    local dmg="dist/$APP_NAME-$VERSION-$arch.dmg"

    mkdir -p dist "$arch_dir"
    build_app "$arch_app" "$arch"
    rm -f "$zip" "$dmg"

    if [[ "$IDENTITY" != "-" ]]; then
        # Notarize the app (submitted as a zip), then staple the ticket into the bundle.
        ditto -c -k --keepParent "$arch_app" "$zip"
        notarize "$zip"
        xcrun stapler staple "$arch_app"
        rm -f "$zip"
    fi
    ditto -c -k --keepParent "$arch_app" "$zip"

    # DMG: Quotlet.app + a shortcut to /Applications, so users drag to install.
    local stage
    stage=$(mktemp -d)
    cp -R "$arch_app" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
    rm -rf "$stage"
    if [[ "$IDENTITY" != "-" ]]; then
        codesign --force --timestamp --sign "$IDENTITY" "$dmg"
        notarize "$dmg"
        xcrun stapler staple "$dmg"
        spctl --assess --type open --context context:primary-signature -v "$dmg" || true
    fi
}

case "${1:-}" in
    "")
        build_app "$APP"
        ;;
    install)
        build_app "$APP"
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
        rm -rf "/Applications/$APP_NAME.app"
        cp -R "$APP" /Applications/
        open "/Applications/$APP_NAME.app"
        echo "Installed and launched /Applications/$APP_NAME.app"
        ;;
    release)
        ARCHS=()
        if [[ -n "${2:-}" ]]; then
            case "$2" in
                arm64|x86_64) ARCHS=("$2") ;;
                *) echo "Unsupported arch: $2 (expected arm64 or x86_64)" >&2; exit 1 ;;
            esac
        else
            ARCHS=(arm64 x86_64)
        fi

        FILES=()
        for arch in "${ARCHS[@]}"; do
            package_arch_release "$arch"
            FILES+=("dist/$APP_NAME-$VERSION-$arch.zip" "dist/$APP_NAME-$VERSION-$arch.dmg")
        done

        shasum -a 256 "${FILES[@]}"
        echo "Release files: ${FILES[*]}"
        ;;
    *)
        echo "Usage: $0 [install | release [arm64|x86_64]]" >&2
        exit 1
        ;;
esac
