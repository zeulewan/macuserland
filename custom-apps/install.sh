#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAMES=(DarkPDF StreamMode Sidecar Synology)
INSTALL_DOCK=0
INSTALL_PRIVILEGED=0

usage() {
    cat <<'EOF'
Usage: custom-apps/install.sh [--dock] [--privileged]

Installs the local Dock apps into ~/Applications:
  DarkPDF, StreamMode, Sidecar, Synology

Options:
  --dock        Add the apps to the Dock after installing them.
  --privileged  Install StreamMode LaunchDaemons and sudoers rule.
  -h, --help    Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dock)
            INSTALL_DOCK=1
            ;;
        --privileged)
            INSTALL_PRIVILEGED=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This installer only supports macOS." >&2
    exit 1
fi

if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    echo "Run this as the target login user, not with sudo. The script will ask for sudo only when needed." >&2
    exit 1
fi

find_macos_sdk() {
    local sdk
    for sdk in \
        /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
        /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk; do
        if [ -d "$sdk" ]; then
            printf '%s\n' "$sdk"
            return 0
        fi
    done

    /bin/ls -1d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk \
        /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | /usr/bin/tail -n 1
}

SDK_PATH="$(find_macos_sdk || true)"
if [ -z "$SDK_PATH" ]; then
    echo "macOS SDK not found. Install Xcode or Xcode Command Line Tools." >&2
    exit 1
fi

export SDKROOT="$SDK_PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

CLANG="$(/usr/bin/xcrun --find clang 2>/dev/null || true)"
if [ -z "$CLANG" ]; then
    echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
    exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

install_sidecar_launcher() {
    local swiftc
    swiftc="$(/usr/bin/xcrun --find swiftc 2>/dev/null || true)"
    if [ -z "$swiftc" ]; then
        echo "Skipping SidecarLauncher: swiftc not found. Install Xcode Command Line Tools." >&2
        return 0
    fi

    /bin/mkdir -p "$HOME/bin"
    "$swiftc" "$ROOT/apps/Sidecar/SidecarLauncher.swift" \
        -sdk "$SDK_PATH" \
        -target "arm64-apple-macosx$MACOSX_DEPLOYMENT_TARGET" \
        -o "$HOME/bin/SidecarLauncher" \
        -framework Foundation \
        -framework CoreGraphics \
        -O
    /bin/chmod 755 "$HOME/bin/SidecarLauncher"
}

install_app() {
    local name="$1"
    local src="$ROOT/apps/$name"
    local app="$HOME/Applications/$name.app"
    local contents="$app/Contents"

    /bin/mkdir -p "$contents/MacOS" "$contents/Resources"
    /bin/rm -rf "$contents/_CodeSignature"

    /usr/bin/install -m 644 "$src/Info.plist" "$contents/Info.plist"
    /usr/bin/install -m 755 "$src/$name.sh" "$contents/Resources/$name.sh"

    local icon
    for icon in "$src"/*.icns; do
        [ -e "$icon" ] || continue
        /usr/bin/install -m 644 "$icon" "$contents/Resources/$(basename "$icon")"
    done

    "$CLANG" -arch arm64 -isysroot "$SDK_PATH" -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
        -Os "$ROOT/native-script-app-launcher.c" -o "$contents/MacOS/$name"
    /bin/chmod 755 "$contents/MacOS/$name"

    /usr/bin/codesign --force --sign - "$app" >/dev/null
    "$LSREGISTER" -f "$app"
    /usr/bin/touch "$app"

    "$contents/MacOS/$name" --native-launcher-self-test >/dev/null
}

install_privileged_streammode() {
    /usr/bin/sudo /usr/bin/install -o root -g wheel -m 644 \
        "$ROOT/launchdaemons/com.local.awdl.disable.plist" \
        /Library/LaunchDaemons/com.local.awdl.disable.plist
    /usr/bin/sudo /usr/bin/install -o root -g wheel -m 644 \
        "$ROOT/launchdaemons/com.local.llw.disable.plist" \
        /Library/LaunchDaemons/com.local.llw.disable.plist

    local tmp
    tmp="$(/usr/bin/mktemp)"
    /usr/bin/sed "s/__USER__/$USER/g" "$ROOT/sudoers-streammode.in" > "$tmp"
    /usr/bin/sudo /usr/bin/visudo -cf "$tmp" >/dev/null
    /usr/bin/sudo /usr/bin/install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/streammode
    /bin/rm -f "$tmp"
}

dock_url_for_app() {
    /usr/bin/python3 - "$1" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri() + "/")
PY
}

dock_has_app() {
    local app="$1"
    local url
    url="$(dock_url_for_app "$app")"
    /usr/bin/defaults read com.apple.dock persistent-apps 2>/dev/null | /usr/bin/grep -Fq "$url"
}

add_app_to_dock() {
    local app="$1"
    local label="$2"
    local url
    url="$(dock_url_for_app "$app")"

    if dock_has_app "$app"; then
        return 0
    fi

    /usr/bin/defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$url</string><key>_CFURLStringType</key><integer>15</integer></dict><key>file-label</key><string>$label</string></dict><key>tile-type</key><string>file-tile</string></dict>"
}

/bin/mkdir -p "$HOME/Applications"
install_sidecar_launcher

for name in "${APP_NAMES[@]}"; do
    install_app "$name"
    echo "Installed $name.app"
done

if [ "$INSTALL_PRIVILEGED" -eq 1 ]; then
    install_privileged_streammode
    echo "Installed StreamMode privileged files"
fi

if [ "$INSTALL_DOCK" -eq 1 ]; then
    for name in "${APP_NAMES[@]}"; do
        add_app_to_dock "$HOME/Applications/$name.app" "$name"
    done
    /usr/bin/killall Dock 2>/dev/null || true
    echo "Added apps to Dock"
fi

echo "Done."
