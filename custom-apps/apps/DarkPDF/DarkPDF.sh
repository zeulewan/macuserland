#!/bin/bash
set -u

PROFILE_ROOT="$HOME/Library/Application Support/Firefox/Profiles"
TITLE="Dark PDF"

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"$TITLE\""; }

find_chrome_dir() {
    if [ -n "${FIREFOX_PROFILE_DIR:-}" ]; then
        printf '%s/chrome\n' "$FIREFOX_PROFILE_DIR"
        return 0
    fi

    for dir in "$PROFILE_ROOT"/*/chrome; do
        [ -d "$dir" ] || continue
        if [ -f "$dir/usercontent.css" ] || [ -f "$dir/usercontent_off.css" ] || \
           [ -f "$dir/userContent.css" ] || [ -f "$dir/userContent_off.css" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done

    for profile in "$PROFILE_ROOT"/*.default-release* "$PROFILE_ROOT"/*.default* "$PROFILE_ROOT"/*; do
        [ -d "$profile" ] || continue
        printf '%s/chrome\n' "$profile"
        return 0
    done

    return 1
}

if ! CHROME_DIR="$(find_chrome_dir)"; then
    notify "Firefox profile not found"
    exit 1
fi

CSS="$CHROME_DIR/usercontent.css"
CSS_OFF="$CHROME_DIR/usercontent_off.css"

if [ -f "$CSS" ]; then
    /bin/mv "$CSS" "$CSS_OFF"
    MSG="OFF"
elif [ -f "$CSS_OFF" ]; then
    /bin/mv "$CSS_OFF" "$CSS"
    MSG="ON"
else
    /bin/mkdir -p "$CHROME_DIR"
    /bin/cat > "$CSS" << 'CSS'
#viewerContainer > #viewer > .page > .canvasWrapper > canvas {
    filter: grayscale(100%) invert(100%);
}
CSS
    MSG="ON"
fi

notify "$MSG"
