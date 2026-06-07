#!/bin/bash
# HoldTalk uninstaller — removes the app and everything it created.
#
#   curl -fsSL https://raw.githubusercontent.com/DevWizardHQ/HoldTalk/main/scripts/uninstall.sh | bash
#
# Flags:
#   --keep-data     keep models + dictation history (only remove the app)
#   --with-whisper  also uninstall the Homebrew whisper-cpp dependency
#   -y              no confirmation prompt
set -euo pipefail

APP="/Applications/HoldTalk.app"
SUPPORT="$HOME/Library/Application Support/HoldTalk"
LOG="$HOME/Library/Logs/HoldTalk.log"
BUNDLE_ID="com.devwizardhq.holdtalk"

KEEP_DATA=0
WITH_WHISPER=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --keep-data) KEEP_DATA=1 ;;
        --with-whisper) WITH_WHISPER=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

echo "HoldTalk uninstaller"
echo
echo "This will remove:"
echo "  • $APP"
[ "$KEEP_DATA" = 0 ] && echo "  • $SUPPORT  (downloaded models + dictation history)"
echo "  • $LOG"
echo "  • HoldTalk preferences ($BUNDLE_ID)"
[ "$WITH_WHISPER" = 1 ] && echo "  • Homebrew package: whisper-cpp"
echo

if [ "$ASSUME_YES" = 0 ]; then
    # `read` works even when piped from curl, as long as a TTY exists.
    read -r -p "Continue? [y/N] " answer </dev/tty
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

echo
echo "▸ Stopping HoldTalk and its whisper-server processes"
pkill -x HoldTalk 2>/dev/null || true
pkill -f 'whisper-server.*--port 1817[89]' 2>/dev/null || true
sleep 1

if [ -d "$APP" ]; then
    echo "▸ Removing $APP"
    rm -rf "$APP"
else
    echo "▸ $APP not found (skipping)"
fi

# "Launch at login" points at whichever copy of the app last registered it —
# if any other copy survives (Downloads, a dist build, a second volume), the
# app comes back on reboot. Sweep every copy Spotlight knows about.
echo "▸ Removing any other HoldTalk.app copies"
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | while IFS= read -r app_copy; do
    case "$app_copy" in
        *.app)
            echo "  removing $app_copy"
            rm -rf "$app_copy"
            ;;
    esac
done

if [ "$KEEP_DATA" = 0 ] && [ -d "$SUPPORT" ]; then
    echo "▸ Removing models + history ($SUPPORT)"
    rm -rf "$SUPPORT"
fi

if [ -f "$LOG" ]; then
    echo "▸ Removing log file"
    rm -f "$LOG"
fi

echo "▸ Removing preferences"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

# Privacy grants (Microphone / Accessibility) — harmless to leave, but tidy up.
echo "▸ Resetting privacy permissions (best effort)"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true

# whisper-cpp dependency: ask interactively unless a flag already decided.
if command -v brew >/dev/null && brew list whisper-cpp >/dev/null 2>&1; then
    if [ "$WITH_WHISPER" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
        echo
        read -r -p "Also uninstall the whisper-cpp Homebrew package? Other tools may use it. [y/N] " whisper_answer </dev/tty
        case "$whisper_answer" in
            y|Y|yes|YES) WITH_WHISPER=1 ;;
        esac
    fi
    if [ "$WITH_WHISPER" = 1 ]; then
        echo "▸ Uninstalling whisper-cpp (Homebrew)"
        brew uninstall whisper-cpp
    else
        echo "▸ Keeping whisper-cpp (other tools may use it)"
    fi
fi

echo
echo "✓ HoldTalk uninstalled."
