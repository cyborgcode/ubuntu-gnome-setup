#!/usr/bin/env bash
# Removes features install.sh added, and puts their settings back to Ubuntu's defaults. It always asks which ones first:
#   ./uninstall.sh                nothing checked
#   ./uninstall.sh gaze dock      only the features named checked
# Run it as your normal user, from a terminal in your GNOME session. It asks for your password when apt needs it.
# Your own project checkouts (~/gdrive-sync, ~/puffdrop and the others) and the data apps keep are left in place.
set -uo pipefail
. "$(dirname -- "$0")/lib.sh"

check_session
pick_features "Uninstall" "Pick what to remove." OFF "$@"

# Last installed, first removed: Caffeine's lid service goes before Caffeine.
steps=()
for ((i = ${#PICKED[@]} - 1; i >= 0; i--)); do
    steps+=("${PICKED[i]}")
done
run_features uninstall "${steps[@]}"

echo
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Fix what the output above says, then run '$0 ${FAILED[*]}' to try again."
fi
echo "Log out and back in to finish: GNOME Shell keeps a removed extension running until then."
[ ${#FAILED[@]} -eq 0 ]
