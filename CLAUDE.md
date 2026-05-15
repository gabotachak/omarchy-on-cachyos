# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A set of shell scripts that install and customize [Omarchy](https://omarchy.org/) (DHH's opinionated Hyprland desktop) on top of [CachyOS](https://cachyos.org/) (a performance-optimized Arch Linux distribution). The main value is patching the two systems' conflicts and providing personal customizations on top.

## Scripts

### `bin/install-omarchy-on-cachyos.sh`
The main installer. It:
1. Clones the upstream Omarchy repo into `../omarchy/`
2. Applies `sed` patches directly to Omarchy's own install scripts to resolve CachyOS conflicts
3. Copies the patched tree to `~/.local/share/omarchy/`
4. Runs Omarchy's `install.sh`

All CachyOS compatibility fixes live as in-place `sed` edits inside this script. When Omarchy changes upstream, these patches may need updating.

### `bin/nvidia.sh`
Installs NVIDIA 580xx proprietary drivers via CachyOS's `chwd` tool. Removes conflicting `nvidia-open-dkms` packages and patches `/var/lib/chwd/ids/nvidia-580.ids` if the GPU ID is missing. Run separately from the main installer when needed.

### `bin/gabotachak.sh`
Personal post-install customization script. Idempotent — safe to re-run. Steps:
1. Auto-detects monitor resolution and patches `~/.config/hypr/monitors.lua` for logical 1080p scaling
2. Installs personal software (Steam, Discord, Spotify, VSCode, Iosevka Nerd Font, Proton, Heroic, Antigravity, xorg-xrdb)
3. Sets Iosevka Nerd Font as system font
4. Adds macOS-style screenshot bindings + remaps `SUPER+SHIFT+N` → `SUPER+CTRL+N` for window-to-workspace
5. Adds `SUPER+CTRL+arrows` workspace navigation
6. Sets `rounding = 12` in `looknfeel.lua`
7. Rewrites SDDM `Main.qml` to match Omarchy/hyprlock visual style
8. Disables SDDM autologin, ensures `theme.conf` persists separately
9. Sets US International keyboard layout
10. Sets Alacritty font size to 12
11. Rebrands boot: Limine entry → "Omarchy", splash → current Omarchy wallpaper (PNG via `magick`), Plymouth → `fade-in` with `mkinitcpio -P` rebuild
12. Installs `~/.config/omarchy/hooks/theme-set` to sync SDDM wallpaper and Limine splash on theme change
13. Sets `Xft.dpi` (96 × scale) in `~/.Xresources` and loads via `xrdb` autostart — fixes Steam CEF UI scaling on XWayland without blur
14. Sets Lumon as default Omarchy theme

## Key CachyOS vs Omarchy Conflicts Resolved

| Conflict | Resolution |
|---|---|
| `tldr` vs `tealdeer` | Removes tldr from Omarchy's package list |
| `paru` vs `yay` | Installs yay; Omarchy uses yay |
| `wpa_supplicant` vs `iwd` | Disables wpa_supplicant; configures NetworkManager to use iwd backend |
| Fish vs Bash | Keeps Fish; patches `mise activate` to detect shell |
| CachyOS walker version conflict | Pins walker to omarchy repo via `IgnorePkg` |
| Plymouth/Limine/SDDM | Removes Plymouth/limine-snapper/alt-bootloaders from Omarchy's login install |
| NVIDIA open-dkms | Replaced by `nvidia.sh` with 580xx proprietary via `chwd` |
| `claude-code` file conflict | Removes any pre-existing claude-code before Omarchy installs it |

## Omarchy Config Files (post-install)

Omarchy uses Lua for Hyprland config. User overrides live in `~/.config/hypr/` and are loaded after Omarchy defaults from `~/.local/share/omarchy/`:

- `monitors.lua` — display scale; `omarchy_monitor_scale` and `omarchy_gdk_scale`
- `bindings.lua` — keybindings appended idempotently with guard `grep -q`
- `looknfeel.lua` — appearance appended idempotently
- `input.lua` — keyboard layout
- `autostart.lua` — startup commands (xrdb for Xft.dpi)
- `hyprland.lua` — main entry point; add personal global config here

**Never edit `~/.local/share/omarchy/`** — changes are lost on `omarchy update`.

## Non-Obvious Design Decisions (gabotachak.sh)

These are decisions where the reasoning matters for future changes.

### Steam HiDPI scaling (`Xft.dpi`)
Steam's new UI is CEF-based (webhelper). `STEAM_FORCE_DESKTOPUI_SCALING` only worked with the old Qt UI — it does nothing now. With Omarchy's default `xwayland.force_zero_scaling = true`, XWayland presents a 2560×1440 native framebuffer at scale=1 to all X11 apps, with no compositor upscaling. Steam renders its UI tiny. Disabling `force_zero_scaling` makes Steam the right size but blurry at 1.333x non-integer scale. The fix: keep `force_zero_scaling = true` and set `Xft.dpi = 96 × scale` in `~/.Xresources`. CEF reads `Xft.dpi` to compute its device pixel ratio — it scales the UI to 1.333x within the native framebuffer, with no compositor blur.

### SDDM: separate `theme.conf` from `autologin.conf`
CachyOS installs autologin in `/etc/sddm.conf.d/autologin.conf`. Omarchy's SDDM theme is in `/etc/sddm.conf.d/theme.conf`. These must stay in separate files — deleting `autologin.conf` to disable autologin would also remove the theme if they were combined.

### Limine boot entry: two mechanisms needed
Renaming `/+CachyOS` to `/+Omarchy` requires both:
1. Direct `sed` on `/boot/limine.conf` — takes effect immediately
2. `TARGET_OS_NAME="Omarchy"` in `/etc/default/limine` — survives kernel updates

Without `TARGET_OS_NAME`, `limine-entry-tool` (runs on every kernel update) reads `PRETTY_NAME` from `/etc/os-release`, which `cachyos-branding.hook` resets to "CachyOS" on every package update. The machine-id comment in `limine.conf` lets the tool find the existing entry by ID regardless of its current name.

### macOS-style screenshot keybindings
`SUPER+SHIFT+3/4/5` maps to macOS `Cmd+Shift+3/4/5`. But `SUPER+SHIFT+N` was already bound to "move window to workspace N" in Omarchy. The solution: rebind move-window to `SUPER+CTRL+N` (freeing all `SUPER+SHIFT+N` combos) and add screenshots on `code:12/13/14` (keys 3, 4, 5). The `code:` prefix is required for keycodes in Hyprland's Lua binding API.

### `SUPER+CTRL+arrows` workspace navigation
Uses `"+1"`/`"-1"` (not `"e+1"`/`"e-1"`). The `e+` prefix skips empty workspaces — that broke navigation when workspaces weren't consecutively populated. Plain `+1`/`-1` always moves to adjacent workspace regardless.

### Plymouth change requires initramfs rebuild
Changing `/etc/plymouth/plymouthd.conf` alone doesn't work — Plymouth runs from the initramfs. `sudo mkinitcpio -P` is required for the theme change to take effect at boot.

### US International keyboard layout
User writes in Spanish on a US keyboard. `kb_layout = "us"` + `kb_variant = "intl"` enables ñ, accented vowels (á/é/í/ó/ú), and inverted punctuation (¡¿) via dead keys. Patched idempotently via `sed` on `input.lua`.

### Lumon as default theme
User's aesthetic preference. Applied last in the script so hooks (SDDM wallpaper sync, Limine splash sync) are already installed before the theme switch fires them.

## Snapshot Recovery (Snapper + BTRFS)

The system uses Snapper + snap-pac. Every `pacman` operation creates a pre/post snapshot automatically. Full recovery instructions are in `PANIC.md`.

**Quick reference:**

| Situation | Action |
|---|---|
| GUI broken, system boots | `Ctrl+Alt+F2` → TTY → `sudo snapper rollback <n>` → reboot |
| System doesn't boot | Live USB → `mount /dev/nvme0n1p2 /mnt` → `btrfs subvolume set-default <ID> /mnt` → reboot |

Find snapshot numbers with `sudo snapper list`. Use the **pre** snapshot just before the breaking update.

## Shell Style (from Omarchy's AGENTS.md)

- Two spaces for indentation, no tabs
- `#!/bin/bash` shebangs (never `#!/usr/bin/env bash`)
- `[[ ]]` for string/file tests, `(( ))` for numeric
- Don't quote variables inside `[[ ]]`; do quote string literals in comparisons
