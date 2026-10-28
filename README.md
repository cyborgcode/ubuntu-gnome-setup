# Ubuntu GNOME setup

Everything I added to Ubuntu GNOME, installed on a fresh machine in one go. Made for Ubuntu 26.04 with GNOME Shell 50.

## Install on a fresh Ubuntu

The repo is private, so sign in to GitHub first:

```bash
sudo apt install -y git gh
gh auth login
gh repo clone cyborgcode/ubuntu-gnome-setup ~/ubuntu-gnome-setup
~/ubuntu-gnome-setup/install.sh
```

Run it as your normal user, from a terminal in your GNOME session. It asks for your password when apt needs it, and
gdrive-sync's installer opens the browser to sign you in to Google Drive.

When it finishes:

1. Log out and back in. GNOME Shell on Wayland loads new extensions only at login.
2. Open Gaze and enroll your face, for face unlock.

If a step fails, the script says which ones at the end. Fix the problem and run only those again, for example
`./install.sh gaze fluxcast`. Every step is safe to run again, so `git pull && ./install.sh` also updates a machine.

## What it sets up

| Step | What |
| --- | --- |
| `packages` | git, curl, unzip, python3 and patch, which the other steps use |
| `extensions` | This repo's own extension, **Tray icons**: hides tray icons, with exceptions, and draws custom icons for Filee and Beeper |
| `quick-settings-scroll` | [**Quick Settings Scroll**](https://github.com/cyborgcode/quick-settings-scroll), which scrolls Quick Settings when it is taller than the screen |
| `gnome-extensions` | **Caffeine** and **Clipboard Indicator** from extensions.gnome.org |
| `gaze` | **Gaze** face unlock and its extension, from Gundu Labs' apt repository |
| `filee` | **Filee** file converter from its latest GitHub release, its donut-at-the-cursor extension, and starting it at login |
| `fluxcast` | **FluxCast** TV casting, the [FluxCast Quick Settings](https://github.com/cyborgcode/fluxcast-gnome-extension) extension, and its patch so FluxCast stops asking which screen to share |
| `gdrive-sync` | [**gdrive-sync**](https://github.com/cyborgcode/gdrive-sync) Google Drive sync and its Quick Settings toggle |
| `puffdrop` | [**Puffdrop**](https://github.com/cyborgcode/puffdrop) AirDrop: the panel, the receiver and the radio driver |
| `caffeine-lid-sync` | A user service that keeps the machine awake with the lid closed while Caffeine is on |
| `settings` | The GNOME settings in `settings.ini` (theme, French keyboard, text size, dock, night light, power, extension settings, which extensions are on) and the wallpaper |

Your own projects (Quick Settings Scroll, FluxCast Quick Settings, gdrive-sync, Puffdrop) are cloned into your home
folder and installed with their own installers, so they stay up to date with their repos.

## Not included

- Apps that aren't GNOME features, such as Beeper, Claude, VS Code and Docker. The dock favorites still list them and
  fill in once they're installed.
- The jcode keyboard shortcuts (Super+; and Super+'), which need jcode installed first.
- Touchpad Speed Control, which is turned on in GNOME's list but isn't installed on the original machine.
- Night Light's saved location, the app grid layout and per-app notification settings, which belong to one machine.

## Keeping it up to date

When you change something on your machine, copy it here and commit:

- an extension in `extensions/`: copy its folder from `~/.local/share/gnome-shell/extensions/`
- a GNOME setting: find it with `dconf dump /org/gnome/` and add the key to `settings.ini`
