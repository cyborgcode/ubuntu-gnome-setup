# Shared by install.sh and uninstall.sh: the features, how each one installs and uninstalls, the menu and the progress
# bar. Not meant to be run on its own.
#
# A feature is install_<name> and uninstall_<name> below, plus settings/<name>.ini when it has GNOME settings: installing
# loads that file into dconf after install_<name>, and uninstalling resets every key in it to Ubuntu's default.
# Features made only of settings need no functions.

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
WALLPAPER="$HOME/.config/background"

# The features, in the order they install, and what the menu says about each.
FEATURES=(tray-icons quick-settings-scroll caffeine caffeine-lid-sync clipboard-indicator gaze filee fluxcast gdrive-sync
    puffdrop appearance wallpaper dock keyboard-touchpad power night-light wellbeing tiling other-settings)
declare -A ABOUT=(
    [tray-icons]='Tray icons: hide tray icons, with exceptions'
    [quick-settings-scroll]='Quick Settings Scroll: scroll it when too tall'
    [caffeine]='Caffeine: keep the screen awake (Super+C)'
    [caffeine-lid-sync]='Caffeine also keeps it awake with the lid closed'
    [clipboard-indicator]='Clipboard Indicator: clipboard history (Alt+W)'
    [gaze]='Gaze face unlock'
    [filee]='Filee file converter, started at login'
    [fluxcast]='FluxCast: cast the screen to a TV'
    [gdrive-sync]='gdrive-sync: Google Drive sync (signs you in)'
    [puffdrop]='Puffdrop: AirDrop with iPhones and Macs'
    [appearance]='Dark theme, 125% text, weekday in the clock'
    [wallpaper]='Golden Gate Bridge wallpaper'
    [dock]='Dock on the left, always shown, with favorites'
    [keyboard-touchpad]='French keyboard, touchpad speed and typing'
    [power]='Suspend on lid close, never sleep on AC power'
    [night-light]='Night Light from sunset to sunrise'
    [wellbeing]='Break reminders and an 8-hour screen limit'
    [tiling]='Tiling Assistant: orange focus hint'
    [other-settings]='No crash reports or startup sound, and more'
)
# Features that download or build something with the tools install_packages adds.
NEEDS_TOOLS=(quick-settings-scroll caffeine clipboard-indicator filee fluxcast gdrive-sync puffdrop)

# ---- helpers ----------------------------------------------------------------------------------------------------

has() { # word list...
    [[ " ${*:2} " == *" $1 "* ]]
}

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

# Turns a GNOME Shell extension on or off by editing the list of enabled extensions. On Wayland, `gnome-extensions
# enable` can't turn on an extension the running shell hasn't loaded yet; this list is read again at the next login.
set_extension_enabled() { # uuid true|false
    local list
    list=$(gsettings get org.gnome.shell enabled-extensions | python3 -c '
import ast, sys
uuids = [u for u in ast.literal_eval(sys.stdin.read().strip().removeprefix("@as ")) if u != sys.argv[1]]
if sys.argv[2] == "true":
    uuids.append(sys.argv[1])
print("[" + ", ".join(repr(u) for u in uuids) + "]")' "$1" "$2") &&
        gsettings set org.gnome.shell enabled-extensions "$list"
}

# Removes an extension installed in the home folder, after turning it off.
remove_extension() { # uuid
    set_extension_enabled "$1" false && rm -rf "${EXT_DIR:?}/$1"
}

# An extension from extensions.gnome.org, in the version made for this GNOME Shell, turned on.
install_from_ego() { # uuid
    local major url
    major=$(gnome-shell --version | grep -oE '[0-9]+' | head -n 1) &&
        url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$1&shell_version=$major" |
            python3 -c 'import json, sys; print(json.load(sys.stdin)["download_url"])') &&
        curl -fsSL -o "$TMP/$1.zip" "https://extensions.gnome.org$url" &&
        gnome-extensions install --force "$TMP/$1.zip" &&
        set_extension_enabled "$1" true
}

# Puts every key in a settings file back to Ubuntu's default.
reset_settings() { # file
    local key
    for key in $(awk '/^\[/ { section = substr($0, 2, length($0) - 2); next }
        /^[a-z]/ { print "/" section "/" substr($0, 1, index($0, "=") - 1) }' "$1"); do
        dconf reset "$key" || return 1
    done
}

# ---- features ---------------------------------------------------------------------------------------------------

# The tools the features in NEEDS_TOOLS use. Not in the menu: install.sh runs it first when one of them is picked.
install_packages() {
    sudo apt-get update && sudo apt-get install -y git curl unzip python3 patch
}

# This repo's own extension, with its saved state (icons hidden, and which apps are exceptions) unless this machine
# already has one.
install_tray_icons() {
    local uuid=filee-tray-toggle@local state="$HOME/.config/filee-tray-toggle/state.json"
    mkdir -p "$EXT_DIR" && rm -rf "${EXT_DIR:?}/$uuid" && cp -r "$REPO/extensions/$uuid" "$EXT_DIR/$uuid" &&
        { [ -e "$state" ] || install -D -m 600 "$REPO/config/filee-tray-toggle/state.json" "$state"; } &&
        set_extension_enabled "$uuid" true
}
uninstall_tray_icons() {
    remove_extension filee-tray-toggle@local && rm -rf "$HOME/.config/filee-tray-toggle"
}

install_quick_settings_scroll() {
    clone_or_pull https://github.com/cyborgcode/quick-settings-scroll.git "$HOME/quick-settings-scroll" &&
        "$HOME/quick-settings-scroll/install.sh"
}
uninstall_quick_settings_scroll() {
    remove_extension quick-settings-scroll@rayen.local
}

install_caffeine() {
    install_from_ego caffeine@patapon.info
}
uninstall_caffeine() {
    remove_extension caffeine@patapon.info
}

# A user service that mirrors Caffeine's on/off state into a logind inhibitor covering the lid switch.
install_caffeine_lid_sync() {
    install -D -m 755 "$REPO/caffeine-lid-sync/caffeine-lid-sync.sh" "$HOME/.local/bin/caffeine-lid-sync.sh" &&
        install -D -m 644 "$REPO/caffeine-lid-sync/caffeine-lid-sync.service" \
            "$HOME/.config/systemd/user/caffeine-lid-sync.service" &&
        systemctl --user daemon-reload &&
        systemctl --user enable caffeine-lid-sync.service &&
        systemctl --user restart caffeine-lid-sync.service
}
uninstall_caffeine_lid_sync() {
    systemctl --user disable --now caffeine-lid-sync.service
    rm -f "$HOME/.local/bin/caffeine-lid-sync.sh" "$HOME/.config/systemd/user/caffeine-lid-sync.service" &&
        systemctl --user daemon-reload
}

install_clipboard_indicator() {
    install_from_ego clipboard-indicator@tudmotu.com
}
uninstall_clipboard_indicator() {
    remove_extension clipboard-indicator@tudmotu.com
}

# From Gundu Labs' apt repository. Its signing key is in apt/.
install_gaze() {
    local keyring=/usr/share/keyrings/gundulabs-archive-keyring.gpg
    sudo install -D -m 644 "$REPO/apt/gundulabs-archive-keyring.gpg" "$keyring" &&
        echo "deb [arch=amd64 signed-by=$keyring] https://packages.gundulabs.com/deb $CODENAME main" |
        sudo tee /etc/apt/sources.list.d/gundulabs.list >/dev/null &&
        sudo apt-get update &&
        sudo apt-get install -y gaze gaze-gui gaze-gnome-extension &&
        set_extension_enabled gaze@gundulabs.com true
}
uninstall_gaze() {
    set_extension_enabled gaze@gundulabs.com false &&
        sudo apt-get remove -y gaze gaze-gui gaze-gnome-extension &&
        sudo rm -f /etc/apt/sources.list.d/gundulabs.list /usr/share/keyrings/gundulabs-archive-keyring.gpg
}

# From its latest GitHub release, after checking the download's checksum. Its own installer also adds Filee's GNOME
# extension (the donut at the cursor). Filee then starts at login, in the background.
install_filee() {
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
# Filee's own uninstaller, which keeps your Filee settings and converted files.
uninstall_filee() {
    local uninstaller="$HOME/.local/share/filee/application/uninstall.sh"
    rm -f "$HOME/.config/autostart/filee.desktop"
    if [ -x "$uninstaller" ]; then
        "$uninstaller"
    fi
}

# FluxCast from its latest GitHub release, the FluxCast Quick Settings extension, and that extension's patch that makes
# FluxCast remember the screen-share choice instead of asking on every cast. Install this again after an upgrade of
# FluxCast, which undoes the patch.
install_fluxcast() {
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
uninstall_fluxcast() {
    remove_extension fluxcast@rayen.local && sudo apt-get remove -y fluxcast
}

# With its own installer, which signs you in to Google Drive.
install_gdrive_sync() {
    clone_or_pull https://github.com/cyborgcode/gdrive-sync.git "$HOME/gdrive-sync" &&
        (cd "$HOME/gdrive-sync" && bash src/install.sh)
}
# With its own uninstaller, which keeps your files and Google sign-in.
uninstall_gdrive_sync() {
    local dir="$HOME/gdrive-sync"
    if [ ! -f "$dir/src/install.sh" ]; then
        dir="$TMP/gdrive-sync"
        git clone -q https://github.com/cyborgcode/gdrive-sync.git "$dir" || return 1
    fi
    bash "$dir/src/install.sh" --uninstall
}

# With its own setup: the panel, the receiver service and the radio driver. Setup leaves the panel off.
install_puffdrop() {
    clone_or_pull https://github.com/cyborgcode/puffdrop.git "$HOME/puffdrop" &&
        (cd "$HOME/puffdrop" && bin/puffdrop setup && bin/puffdrop install-driver) &&
        set_extension_enabled puffdrop@cyborgcode.github.io true
}
# Undoes what `puffdrop setup` and `puffdrop install-driver` added. Keeps this computer's AirDrop identity (~/.omdrop)
# and Puffdrop's settings (~/.config/airdrop).
uninstall_puffdrop() {
    local puffdrop="$HOME/puffdrop/bin/puffdrop" link="$HOME/.local/bin/puffdrop" units="$HOME/.config/systemd/user"
    if [ -x "$puffdrop" ]; then
        "$puffdrop" off --force
        "$puffdrop" links remove
        "$puffdrop" firewall remove
    fi
    systemctl --user disable --now airdrop-receiver.service
    rm -rf "$units/airdrop-receiver.service" "$units/airdrop-receiver.service.d"
    systemctl --user daemon-reload
    if [ -L "$link" ] && [[ $(readlink "$link") == */bin/puffdrop ]]; then
        rm -f "$link"
    fi
    remove_extension puffdrop@cyborgcode.github.io && sudo apt-get remove -y omdrop-owl
}

install_wallpaper() {
    install -D -m 644 "$REPO/wallpaper.jpg" "$WALLPAPER" &&
        gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER" &&
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER"
}
# Back to Ubuntu's wallpaper. The picture is deleted only if it is still this repo's.
uninstall_wallpaper() {
    gsettings reset org.gnome.desktop.background picture-uri &&
        gsettings reset org.gnome.desktop.background picture-uri-dark || return 1
    if cmp -s "$REPO/wallpaper.jpg" "$WALLPAPER"; then
        rm -f "$WALLPAPER"
    fi
}

# ---- running ----------------------------------------------------------------------------------------------------

# Stops unless this runs as the user, in a terminal inside the GNOME session.
check_session() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Run this as your normal user, not with sudo. It asks for your password when it needs to." >&2
        exit 1
    fi
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "Run this from a terminal inside your GNOME session." >&2
        exit 1
    fi
    TMP=$(mktemp -d) || exit 1
    trap 'rm -rf "$TMP"' EXIT
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
}

# Shows the checklist of features and sets PICKED to the checked ones, in FEATURES order. Features named in the
# arguments start checked; with none named, every feature starts in default_state.
pick_features() { # title prompt default_state(ON|OFF) [feature...]
    local title=$1 prompt=$2 default=$3 feature state choice height items=()
    shift 3
    for feature in "$@"; do
        if ! has "$feature" "${FEATURES[@]}"; then
            echo "Unknown feature '$feature'. The features are: ${FEATURES[*]}" >&2
            exit 1
        fi
    done
    for feature in "${FEATURES[@]}"; do
        if [ $# -gt 0 ]; then
            has "$feature" "$@" && state=ON || state=OFF
        else
            state=$default
        fi
        items+=("$feature" "${ABOUT[$feature]}" "$state")
    done
    height=$(($(tput lines 2>/dev/null || echo 24) - 2))
    ((height > ${#FEATURES[@]} + 8)) && height=$((${#FEATURES[@]} + 8))
    if ! choice=$(whiptail --title "$title" --separate-output --checklist \
        "$prompt Space checks or unchecks a feature, Enter goes ahead." \
        "$height" 78 $((height - 8)) "${items[@]}" 3>&1 1>&2 2>&3); then
        echo "Cancelled. Nothing was changed."
        exit 1
    fi
    if [ -z "$choice" ]; then
        echo "Nothing was checked, so nothing was changed."
        exit 0
    fi
    mapfile -t PICKED <<<"$choice"
}

# The bar printed above each feature's output: how much of the run is done, and what comes next.
progress() { # done total label
    local width=30 filled=$(($1 * 30 / $2)) bar='' i
    for ((i = 0; i < width; i++)); do
        if ((i < filled)); then bar+='█'; else bar+='░'; fi
    done
    printf '\n\e[1m%s %3d%%  [%d/%d]  %s\e[0m\n' "$bar" $(($1 * 100 / $2)) "$1" "$2" "$3"
}

# Runs install or uninstall for each feature, with the progress bar, and sets FAILED to the features that failed.
run_features() { # install|uninstall feature...
    local action=$1 feature fn ini i=0 total=$(($# - 1))
    shift
    FAILED=()
    for feature in "$@"; do
        progress "$i" "$total" "${action^} $feature: ${ABOUT[$feature]:-tools the other features need}"
        i=$((i + 1))
        fn="${action}_${feature//-/_}"
        ini="$REPO/settings/$feature.ini"
        if [ "$action" = install ]; then
            { ! declare -F "$fn" >/dev/null || "$fn"; } &&
                { [ ! -f "$ini" ] || dconf load / <"$ini"; }
        else
            { [ ! -f "$ini" ] || reset_settings "$ini"; } &&
                { ! declare -F "$fn" >/dev/null || "$fn"; }
        fi || FAILED+=("$feature")
    done
    if [ ${#FAILED[@]} -eq 0 ]; then
        progress "$total" "$total" "Done"
    else
        progress "$total" "$total" "Done, but these failed: ${FAILED[*]}"
    fi
}
