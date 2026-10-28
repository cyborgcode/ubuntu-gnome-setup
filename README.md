# Ubuntu GNOME setup

Everything I added to Ubuntu GNOME, installed on a fresh machine in one go, one feature at a time. Made for Ubuntu 26.04
with GNOME Shell 50.

## Install on a fresh Ubuntu

```bash
sudo apt install -y git
git clone https://github.com/cyborgcode/ubuntu-gnome-setup.git ~/ubuntu-gnome-setup
~/ubuntu-gnome-setup/install.sh
```

It first asks which features to install: everything starts checked, Space checks or unchecks one, and Enter installs
the checked ones. A progress bar above each feature shows how far along it is. Run it as your normal user, from a
terminal in your GNOME session. It asks for your password when apt needs it, and gdrive-sync's installer opens the
browser to sign you in to Google Drive.

When it finishes:

1. Log out and back in. GNOME Shell on Wayland loads new extensions only at login.
2. If you installed Gaze, open it and enroll your face, for face unlock.

If something fails, the rest still installs, and the script says what failed at the end. Fix the problem and run it
again with those features named, for example `./install.sh gaze fluxcast`: the menu then opens with only them checked.
Every feature is safe to install again, so `git pull && ./install.sh` also updates a machine.

## Uninstall

```bash
~/ubuntu-gnome-setup/uninstall.sh
```

It shows the same list with nothing checked: check what to remove and press Enter. Extensions and apps are removed and
turned off, and settings go back to Ubuntu's defaults. Then log out and back in. `./uninstall.sh dock wallpaper` opens
the list with those already checked.

It leaves your data alone: the project checkouts in your home folder (`~/gdrive-sync`, `~/puffdrop` and the others),
your Google Drive files and sign-in, Filee's settings and converted files, Puffdrop's AirDrop identity and settings,
and Gaze's enrolled faces.

## Features

Apps and extensions:

| Feature | What it installs |
| --- | --- |
| `tray-icons` | **Tray icons**, this repo's own extension: hides tray icons, with exceptions you pick from its menu, and draws custom icons for Filee and Beeper. Also the tray icons' look |
| `quick-settings-scroll` | [**Quick Settings Scroll**](https://github.com/cyborgcode/quick-settings-scroll), which scrolls Quick Settings when it is taller than the screen |
| `caffeine` | **Caffeine** from extensions.gnome.org, with Super+C to toggle it |
| `caffeine-lid-sync` | A user service that keeps the machine awake with the lid closed while Caffeine is on |
| `clipboard-indicator` | **Clipboard Indicator** from extensions.gnome.org, opened with Alt+W at the cursor |
| `gaze` | **Gaze** face unlock and its extension, from Gundu Labs' apt repository |
| `filee` | **Filee** file converter from its latest GitHub release, its donut-at-the-cursor extension, and starting it at login |
| `fluxcast` | **FluxCast** TV casting, the [FluxCast Quick Settings](https://github.com/cyborgcode/fluxcast-gnome-extension) extension, and its patch so FluxCast stops asking which screen to share |
| `gdrive-sync` | [**gdrive-sync**](https://github.com/cyborgcode/gdrive-sync) Google Drive sync and its Quick Settings toggle |
| `puffdrop` | [**Puffdrop**](https://github.com/cyborgcode/puffdrop) AirDrop: the panel, the receiver and the radio driver |

Settings, each in its own file in `settings/`:

| Feature | What it sets |
| --- | --- |
| `appearance` | Dark style and Yaru-dark theme, text at 125%, the weekday in the clock |
| `wallpaper` | The Golden Gate Bridge wallpaper in `wallpaper.jpg` |
| `dock` | The dock on the left, always shown, 48 px icons, and the favorite apps in it |
| `keyboard-touchpad` | French keyboard layout, touchpad speed, touchpad on while typing |
| `power` | Suspend when the lid closes, never sleep on AC power |
| `night-light` | Night Light on from sunset to sunrise |
| `wellbeing` | Movement and eyesight break reminders, and an 8-hour daily screen time limit |
| `tiling` | Tiling Assistant's orange focus hint, and its tiling popup on all workspaces |
| `other-settings` | No crash reports, no startup sound, volume above 100%, the accessibility menu always shown, the search results order |

Most features first install git, curl, unzip, python3 and patch, which they need. Your own projects (Quick Settings
Scroll, FluxCast Quick Settings, gdrive-sync, Puffdrop) are cloned into your home folder and installed with their own
installers, so they stay up to date with their repos.

## Not included

- Apps that aren't GNOME features, such as Beeper, Claude, VS Code and Docker. The dock favorites still list them and
  fill in once they're installed.
- The jcode keyboard shortcuts (Super+; and Super+'), which need jcode installed first.
- Touchpad Speed Control, which is turned on in GNOME's list but isn't installed on the original machine.
- Night Light's saved location, the app grid layout and per-app notification settings, which belong to one machine.

## Adding to it

Each feature lives in `lib.sh` as `install_<name>` and `uninstall_<name>`, plus `settings/<name>.ini` if it has GNOME
settings, and is listed in `FEATURES` and `ABOUT` at the top. A feature made only of settings needs just its `.ini`
file and those two entries.

- To add a GNOME setting, find it with `dconf dump /org/gnome/` and put the key in the right `settings/*.ini` file.
- To update Tray icons, copy its folder from `~/.local/share/gnome-shell/extensions/` into `extensions/`.
