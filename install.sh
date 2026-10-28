#!/usr/bin/env bash
# Sets up Ubuntu GNOME with the features this repo describes. It always asks which ones to install first:
#   ./install.sh                  every feature checked
#   ./install.sh gaze dock        only the features named checked
# Run it as your normal user, from a terminal in your GNOME session. It asks for your password when apt needs it.
# Every feature is safe to install again: it updates whatever is already there.
set -uo pipefail
. "$(dirname -- "$0")/lib.sh"

check_session
pick_features "Install" "Pick what to install." ON "$@"

steps=("${PICKED[@]}")
for feature in "${PICKED[@]}"; do
    if has "$feature" "${NEEDS_TOOLS[@]}"; then
        steps=(packages "${PICKED[@]}")
        break
    fi
done
run_features install "${steps[@]}"

echo
if [ ${#FAILED[@]} -gt 0 ]; then
    retry=()
    for feature in "${FAILED[@]}"; do
        [ "$feature" = packages ] || retry+=("$feature")
    done
    echo "Fix what the output above says, then run '$0 ${retry[*]}' to try again."
fi
echo "Left to do by hand:"
echo "  - Log out and back in. GNOME Shell on Wayland loads new extensions only at login."
if has gaze "${PICKED[@]}"; then
    echo "  - Open Gaze and enroll your face, for face unlock."
fi
[ ${#FAILED[@]} -eq 0 ]
