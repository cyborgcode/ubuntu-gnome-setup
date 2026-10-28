#!/usr/bin/env bash
# Sets up a fresh Ubuntu GNOME with everything this repo describes.
#   ./install.sh                  runs every step, in order
#   ./install.sh gaze settings    runs only the steps named
# Run it as your normal user, from a terminal in your GNOME session. It asks for your password when apt needs it.
# Every step is safe to run again: it updates whatever is already there.
set -uo pipefail

REPO=$(cd -- "$(dirname -- "$0")" && pwd -P)
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
ALL_STEPS=(packages extensions gnome-extensions gaze filee fluxcast gdrive-sync puffdrop caffeine-lid-sync settings)

# ---- helpers ----------------------------------------------------------------------------------------------------

clone_or_pull() { # url dir
    if [ -d "$2/.git" ]; then
        git -C "$2" pull --ff-only
    else
        git clone "$1" "$2"
    fi
}

# Downloads the first asset of a repository's latest GitHub release whose name matches a regex into $TMP, and prints
# the downloaded file's path.
download_release_asset() { # owner/repo regex
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
        python3 -c 'import json, re, sys; print(next((a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if re.fullmatch(sys.argv[1], a["name"])), ""))' "$2") ||
        return 1
    if [ -z "$url" ]; then
        echo "The latest release of $1 has no file matching $2" >&2
        return 1
    fi
    curl -fsSL -o "$TMP/${url##*/}" "$url" && echo "$TMP/${url##*/}"
}

# ---- steps ------------------------------------------------------------------------------------------------------

# What the other steps need.
step_packages() {
    sudo apt-get update && sudo apt-get install -y git curl unzip python3 patch
}

# This repo's own extensions, which live nowhere else: Tray icons and Quick Settings Scroll.
step_extensions() {
    local dir uuid
    mkdir -p "$EXT_DIR" || return 1
    for dir in "$REPO"/extensions/*/; do
        uuid=$(basename "$dir")
        rm -rf "${EXT_DIR:?}/$uuid" && cp -r "$dir" "$EXT_DIR/$uuid" || return 1
    done
    # Tray icons' saved state (icons hidden, and which apps are exceptions), unless this machine already has one.
    local state="$HOME/.config/filee-tray-toggle/state.json"
    [ -e "$state" ] || install -D -m 600 "$REPO/config/filee-tray-toggle/state.json" "$state"
}

# Caffeine and Clipboard Indicator, from extensions.gnome.org, in the version made for this GNOME Shell.
step_gnome_extensions() {
    local major uuid url
    major=$(gnome-shell --version | grep -oE '[0-9]+' | head -n 1) || return 1
    for uuid in caffeine@patapon.info clipboard-indicator@tudmotu.com; do
        url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$major" |
            python3 -c 'import json, sys; print(json.load(sys.stdin)["download_url"])') &&
            curl -fsSL -o "$TMP/$uuid.zip" "https://extensions.gnome.org$url" &&
            gnome-extensions install --force "$TMP/$uuid.zip" || return 1
    done
}

# Gaze face unlock, from Gundu Labs' apt repository. Its signing key is in apt/.
step_gaze() {
    local keyring=/usr/share/keyrings/gundulabs-archive-keyring.gpg
    sudo install -D -m 644 "$REPO/apt/gundulabs-archive-keyring.gpg" "$keyring" &&
        echo "deb [arch=amd64 signed-by=$keyring] https://packages.gundulabs.com/deb $CODENAME main" |
        sudo tee /etc/apt/sources.list.d/gundulabs.list >/dev/null &&
        sudo apt-get update &&
        sudo apt-get install -y gaze gaze-gui gaze-gnome-extension
}

# Filee, from its latest GitHub release after checking the download's checksum. Its own installer also adds Filee's
# GNOME extension (the donut at the cursor). Filee then starts at login, in the background.
step_filee() {
    local tarball sums upgrade=()
    tarball=$(download_release_asset KnifeLemon/Filee 'Filee-.*-linux-x64\.tar\.gz') &&
        sums=$(download_release_asset KnifeLemon/Filee 'Filee-.*-linux-x64-SHA256SUMS\.txt') &&
        (cd "$TMP" && sha256sum --check --ignore-missing "$sums") &&
        mkdir -p "$TMP/filee" &&
        tar -xzf "$tarball" -C "$TMP/filee" --strip-components=1 || return 1
    [ -d "$HOME/.local/share/filee/application" ] && upgrade=(--upgrade)
    "$TMP/filee/install.sh" "${upgrade[@]}" || return 1
    mkdir -p "$HOME/.config/autostart" && cat >"$HOME/.config/autostart/filee.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Filee
Exec="$HOME/.local/share/filee/application/Filee" --background
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
}

# FluxCast (casting to a TV over Wi-Fi Display) from its latest GitHub release, the FluxCast Quick Settings extension,
# and that extension's patch that makes FluxCast remember the screen-share choice instead of asking on every cast.
# Run this step again after an upgrade of FluxCast, which undoes the patch.
step_fluxcast() {
    local deb patch
    deb=$(download_release_asset IlyaP358/fluxcast "fluxcast_.*\.${CODENAME}_amd64\.deb") &&
        sudo apt-get install -y "$deb" &&
        clone_or_pull https://github.com/cyborgcode/fluxcast-gnome-extension.git "$HOME/fluxcast-gnome-extension" &&
        "$HOME/fluxcast-gnome-extension/install.sh" || return 1
    patch="$HOME/fluxcast-gnome-extension/patches/fluxcast-remember-screen-share.patch"
    if sudo patch -p1 -R --dry-run -s -f -d /opt/fluxcast <"$patch" >/dev/null 2>&1; then
        return 0 # already applied
    fi
    sudo patch -p1 -s -f -d /opt/fluxcast <"$patch"
}

# gdrive-sync, with its own installer (which signs you in to Google Drive), then this machine's edited copy of its
# extension: its folder lists don't scroll on their own, because Quick Settings Scroll scrolls the whole panel.
step_gdrive_sync() {
    clone_or_pull https://github.com/cyborgcode/gdrive-sync.git "$HOME/gdrive-sync" &&
        (cd "$HOME/gdrive-sync" && bash src/install.sh) &&
        cp -r "$REPO/overrides/gdrive-sync@local/." "$EXT_DIR/gdrive-sync@local/"
}

# Puffdrop (AirDrop with iPhones and Macs), with its own setup: the panel, the receiver service and the radio driver.
step_puffdrop() {
    clone_or_pull https://github.com/cyborgcode/puffdrop.git "$HOME/puffdrop" &&
        (cd "$HOME/puffdrop" && bin/puffdrop setup && bin/puffdrop install-driver)
}

# Keeps the machine fully awake, lid closed included, while Caffeine is on.
step_caffeine_lid_sync() {
    install -D -m 755 "$REPO/caffeine-lid-sync/caffeine-lid-sync.sh" "$HOME/.local/bin/caffeine-lid-sync.sh" &&
        install -D -m 644 "$REPO/caffeine-lid-sync/caffeine-lid-sync.service" \
            "$HOME/.config/systemd/user/caffeine-lid-sync.service" &&
        systemctl --user daemon-reload &&
        systemctl --user enable caffeine-lid-sync.service &&
        systemctl --user restart caffeine-lid-sync.service
}

# GNOME settings from settings.ini, including which extensions are on, and the wallpaper. Last, so the extension list
# here wins over whatever the installers above turned on.
step_settings() {
    local wallpaper="$HOME/.config/background"
    dconf load / <"$REPO/settings.ini" &&
        install -D -m 644 "$REPO/wallpaper.jpg" "$wallpaper" &&
        gsettings set org.gnome.desktop.background picture-uri "file://$wallpaper" &&
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$wallpaper"
}

# ---- main -------------------------------------------------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo. It asks for your password when it needs to." >&2
    exit 1
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    echo "Run this from a terminal inside your GNOME session." >&2
    exit 1
fi

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=("${ALL_STEPS[@]}")
for step in "${steps[@]}"; do
    if [[ " ${ALL_STEPS[*]} " != *" $step "* ]]; then
        echo "Unknown step '$step'. The steps are: ${ALL_STEPS[*]}" >&2
        exit 1
    fi
done

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

failed=()
for step in "${steps[@]}"; do
    printf '\n==> %s\n' "$step"
    "step_${step//-/_}" || failed+=("$step")
done

echo
if [ ${#failed[@]} -gt 0 ]; then
    echo "These steps failed: ${failed[*]}"
    echo "Fix what the output above says, then run them again with: $0 ${failed[*]}"
else
    echo "All steps finished."
fi
cat <<'EOF'

Left to do by hand:
  - Log out and back in. GNOME Shell on Wayland loads new extensions only at login.
  - Open Gaze and enroll your face, for face unlock.
EOF
[ ${#failed[@]} -eq 0 ]
