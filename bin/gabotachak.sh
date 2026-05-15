#!/bin/bash
set -e

# 1. Detect native monitor resolution
echo "[*] Detecting monitor resolution..."
NATIVE_HEIGHT=""

if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
    NATIVE_HEIGHT=$(hyprctl monitors | grep -oP '\d+x\K\d+(?=@)' | sort -n | tail -1)
fi

if [[ -z "$NATIVE_HEIGHT" ]]; then
    NATIVE_HEIGHT=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oP '^\d+x\K\d+' | sort -n | tail -1 || true)
fi

if [[ -z "$NATIVE_HEIGHT" ]]; then
    echo "[!] Could not detect monitor resolution. Skipping scaling."
    exit 0
fi

echo "[*] Native height: ${NATIVE_HEIGHT}p"

# 2. Only scale if above 1080p
if [[ "$NATIVE_HEIGHT" -le 1080 ]]; then
    echo "[*] Resolution is 1080p or below. No scaling needed."
    exit 0
fi

# 3. Calculate scale factor for logical 1080p
SCALE=$(awk "BEGIN { printf \"%.6f\", $NATIVE_HEIGHT / 1080 }")
echo "[*] Monitor scale: $SCALE (logical 1080p on ${NATIVE_HEIGHT}p display)"

# 4. Patch monitors.lua
MONITORS_LUA="$HOME/.config/hypr/monitors.lua"

if [[ ! -f "$MONITORS_LUA" ]]; then
    echo "[!] $MONITORS_LUA not found. Skipping."
    exit 0
fi

sed -i "s/local omarchy_gdk_scale = .*/local omarchy_gdk_scale = 1/" "$MONITORS_LUA"
sed -i "s/local omarchy_monitor_scale = .*/local omarchy_monitor_scale = $SCALE/" "$MONITORS_LUA"

echo "[*] monitors.lua patched."

# 5. Reload Hyprland if running
if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
    hyprctl reload
    echo "[*] Hyprland reloaded."
fi

# 6. Install personal software
echo "[*] Installing personal software..."
sudo pacman -S --needed --noconfirm steam discord spotify visual-studio-code-bin ttf-iosevka-nerd inter-font adobe-source-serif-fonts proton-cachyos proton-cachyos-slr heroic-games-launcher-bin xorg-xrdb vlc

# Remove Omarchy's Discord webapp in favor of the native app installed above
rm -f "$HOME/.local/share/applications/Discord.desktop"
echo "[*] Removed Discord webapp entry."

# Add Shutdown app to launcher
cat > "$HOME/.local/share/applications/shutdown.desktop" << 'EOF'
[Desktop Entry]
Name=Shutdown
Exec=systemctl poweroff
Icon=system-shutdown
Type=Application
Categories=System;
EOF
echo "[*] Shutdown app added to launcher."

cat > "$HOME/.local/share/applications/reboot.desktop" << 'EOF'
[Desktop Entry]
Name=Reboot
Exec=systemctl reboot
Icon=system-reboot
Type=Application
Categories=System;
EOF
echo "[*] Reboot app added to launcher."

echo "[*] Installing Google Antigravity IDE from AUR..."
yay -S --needed --noconfirm antigravity

# 7. Set system fonts: Iosevka (monospace), Inter (sans-serif), Source Serif 4 (serif)
echo "[*] Setting system fonts (macOS style)..."
omarchy font set "Iosevka Nerd Font"
FONTS_CONF="$HOME/.config/fontconfig/fonts.conf"
if [[ -f "$FONTS_CONF" ]]; then
  xmlstarlet ed -L \
    -u '//match[@target="pattern"][test/string="sans-serif"]/edit[@name="family"]/string' -v "Inter" \
    -u '//match[@target="pattern"][test/string="serif"]/edit[@name="family"]/string' -v "Source Serif 4" \
    -u '//alias[family="system-ui"]/prefer/family' -v "Inter" \
    -u '//alias[family="-apple-system"]/prefer/family' -v "Inter" \
    -u '//alias[family="BlinkMacSystemFont"]/prefer/family' -v "Inter" \
    "$FONTS_CONF"
  fc-cache -fv
fi
echo "[*] Fonts set: Iosevka Nerd Font (mono), Inter (sans-serif), Source Serif 4 (serif)."

# 8. macOS-style keybindings: screenshots + remap move-window off SUPER+SHIFT+number
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [[ -f "$BINDINGS_LUA" ]] && ! grep -q "macOS-style screenshot" "$BINDINGS_LUA"; then
    cat >> "$BINDINGS_LUA" << 'EOF'

-- macOS-style screenshot shortcuts (Cmd+Shift+3/4/5).
-- SUPER+SHIFT+number was "move window to workspace" — rebind to SUPER+CTRL+number.
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
  hl.bind("SUPER + CTRL + " .. key, hl.dsp.window.move({ workspace = tostring(workspace) }), { description = "Move window to workspace " .. workspace })
  hl.bind("SUPER + CTRL + ALT + " .. key, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }), { description = "Move window silently to workspace " .. workspace })
end
hl.bind("SUPER + SHIFT + code:12", hl.dsp.exec_cmd("omarchy capture screenshot fullscreen copy"), { description = "Screenshot fullscreen → clipboard (macOS Cmd+Shift+3)" })
hl.bind("SUPER + SHIFT + code:13", hl.dsp.exec_cmd("omarchy capture screenshot region copy"), { description = "Screenshot region → clipboard (macOS Cmd+Shift+4)" })
hl.bind("SUPER + SHIFT + code:14", hl.dsp.exec_cmd("omarchy capture screenshot smart copy"), { description = "Screenshot smart → clipboard (macOS Cmd+Shift+5)" })
hl.bind("SUPER + CTRL + SHIFT + code:12", hl.dsp.exec_cmd("omarchy capture screenshot fullscreen save"), { description = "Screenshot fullscreen → file" })
hl.bind("SUPER + CTRL + SHIFT + code:13", hl.dsp.exec_cmd("omarchy capture screenshot region save"), { description = "Screenshot region → file" })
hl.bind("SUPER + CTRL + SHIFT + code:14", hl.dsp.exec_cmd("omarchy capture screenshot smart save"), { description = "Screenshot smart → file" })
EOF
    echo "[*] Screenshot bindings applied."
fi

# 9. SUPER+CTRL+arrows: workspace navigation (overrides niche group-focus bindings)
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [[ -f "$BINDINGS_LUA" ]] && ! grep -q "SUPER + CTRL + LEFT.*workspace" "$BINDINGS_LUA"; then
    cat >> "$BINDINGS_LUA" << 'EOF'

-- SUPER+CTRL+arrows: workspace navigation (overrides niche group-focus bindings).
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")
hl.bind("SUPER + CTRL + LEFT",  hl.dsp.focus({ workspace = "-1" }), { description = "Previous workspace" })
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.focus({ workspace = "+1" }), { description = "Next workspace" })
hl.bind("SUPER + CTRL + UP",    hl.dsp.focus({ workspace = "+1" }), { description = "Next workspace" })
hl.bind("SUPER + CTRL + DOWN",  hl.dsp.focus({ workspace = "-1" }), { description = "Previous workspace" })
EOF
    echo "[*] Workspace arrow navigation applied."
fi

# 10. Logarithmic volume steps (equal perceived change at any level, like Windows/macOS)
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/omarchy-volume-up" << 'EOF'
#!/bin/bash
monitor=$(omarchy-hyprland-monitor-focused)
current=$(pamixer --get-volume)

# +2 dB: multiply by 10^(1/30) ≈ 1.0801
new=$(awk -v v="$current" 'BEGIN { n=int(v * 1.0801 + 0.5); print (n > v) ? n : v+1 }')
[[ $new -gt 100 ]] && new=100

pactl set-sink-volume @DEFAULT_SINK@ ${new}%
swayosd-client --monitor "$monitor" --output-volume +0
EOF
chmod +x "$HOME/.local/bin/omarchy-volume-up"

cat > "$HOME/.local/bin/omarchy-volume-down" << 'EOF'
#!/bin/bash
monitor=$(omarchy-hyprland-monitor-focused)
current=$(pamixer --get-volume)

# -2 dB: multiply by 10^(-1/30) ≈ 0.9259
new=$(awk -v v="$current" 'BEGIN { n=int(v * 0.9259 + 0.5); print (n < v) ? n : (v > 0 ? v-1 : 0) }')

pactl set-sink-volume @DEFAULT_SINK@ ${new}%
swayosd-client --monitor "$monitor" --output-volume +0
EOF
chmod +x "$HOME/.local/bin/omarchy-volume-down"

BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [[ -f "$BINDINGS_LUA" ]] && ! grep -q "Logarithmic volume" "$BINDINGS_LUA"; then
    cat >> "$BINDINGS_LUA" << 'EOF'

-- Volume: logarithmic dB steps (equal perceived change at any level, like Windows/macOS).
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("omarchy-volume-up"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("omarchy-volume-down"), { locked = true, repeating = true, description = "Volume down" })
EOF
    echo "[*] Logarithmic volume bindings applied."
fi

# 11. macOS-style rounded window corners
LOOKNFEEL_LUA="$HOME/.config/hypr/looknfeel.lua"
if [[ -f "$LOOKNFEEL_LUA" ]] && ! grep -q "rounding = 12" "$LOOKNFEEL_LUA"; then
    cat >> "$LOOKNFEEL_LUA" << 'EOF'

hl.config({
  decoration = {
    rounding = 12,
  },
})
EOF
    echo "[*] Rounded corners applied."
fi

# 11. Unify SDDM login screen with Omarchy/hyprlock look
SDDM_THEME_DIR="/usr/share/sddm/themes/omarchy"

sudo cp "$SDDM_THEME_DIR/Main.qml" "$SDDM_THEME_DIR/Main.qml.bak" 2>/dev/null || true

sudo tee "$SDDM_THEME_DIR/Main.qml" > /dev/null << 'EOF'
import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#1a1b26"

    property string currentUser: userModel.lastUser
    property bool loginFailed: false
    property int sessionIndex: {
        for (var i = 0; i < sessionModel.rowCount(); i++) {
            var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
            if (name.indexOf("uwsm") !== -1)
                return i
        }
        return sessionModel.lastIndex
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loginFailed = true
            password.text = ""
            password.focus = true
        }
        function onLoginSucceeded() {
            root.loginFailed = false
        }
    }

    Image {
        id: bg
        anchors.fill: parent
        source: "background"
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color: "#cc1a1b26"
    }

    Column {
        anchors.centerIn: parent
        spacing: 48

        Image {
            id: logo
            source: "logo.png"
            width: Math.min(sourceSize.width, root.width * 0.5)
            height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
            id: inputBox
            width: 650
            height: 80
            radius: 12
            color: "#cc1a1b26"
            border.color: root.loginFailed ? "#f7768e" : "#a9b9d6"
            border.width: 4
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: root.loginFailed ? "Wrong password — try again" : "Enter Password"
                color: root.loginFailed ? "#f7768e" : "#565f89"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 20
                visible: password.text.length === 0
            }

            TextInput {
                id: password
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 24
                font.letterSpacing: 6
                color: "#a9b9d6"
                selectionColor: "#3d59a1"
                selectedTextColor: "#c0caf5"
                cursorDelegate: Item {}
                focus: true

                onTextChanged: root.loginFailed = false

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        sddm.login(root.currentUser, password.text, root.sessionIndex)
                        event.accepted = true
                    }
                }
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
EOF

# Sync current wallpaper to SDDM theme
if [[ -f "$HOME/.config/omarchy/current/background" ]]; then
    sudo cp "$HOME/.config/omarchy/current/background" "$SDDM_THEME_DIR/background"
    echo "[*] SDDM theme updated."
fi

# Hook: keep SDDM wallpaper in sync on theme changes
HOOKS_DIR="$HOME/.config/omarchy/hooks"
mkdir -p "$HOOKS_DIR"
if [[ ! -f "$HOOKS_DIR/theme-set" ]]; then
    cat > "$HOOKS_DIR/theme-set" << 'HOOKEOF'
#!/bin/bash
# Sync omarchy wallpaper to SDDM login screen after theme change
SDDM_BG="/usr/share/sddm/themes/omarchy/background"
OMARCHY_BG="$HOME/.config/omarchy/current/background"
if [[ -f "$OMARCHY_BG" ]]; then
    sudo cp "$OMARCHY_BG" "$SDDM_BG"
fi
HOOKEOF
    chmod +x "$HOOKS_DIR/theme-set"
    echo "[*] SDDM wallpaper sync hook installed."
fi

# 12. SDDM: disable autologin and set omarchy theme
sudo rm -f /etc/sddm.conf.d/autologin.conf
if [[ ! -f /etc/sddm.conf.d/theme.conf ]]; then
    printf '[Theme]\nCurrent=omarchy\n' | sudo tee /etc/sddm.conf.d/theme.conf > /dev/null
    echo "[*] SDDM theme set to omarchy."
fi

# 13. US International keyboard layout for Spanish characters
INPUT_LUA="$HOME/.config/hypr/input.lua"
if [[ -f "$INPUT_LUA" ]] && ! grep -q 'kb_variant = "intl"' "$INPUT_LUA"; then
    sed -i 's|-- kb_layout = "us,dk,eu",|-- kb_layout = "us,dk,eu",\n    kb_layout = "us",|' "$INPUT_LUA"
    sed -i 's|-- kb_variant = "intl",|kb_variant = "intl",|' "$INPUT_LUA"
    echo "[*] Keyboard layout set to US International."
fi

# 12. Set terminal font size to 12
ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if [[ -f "$ALACRITTY_CONF" ]]; then
    sed -i "s/^size = .*/size = 12/" "$ALACRITTY_CONF"
    echo "[*] Alacritty font size set to 12."
fi

# 14. Rebrand boot sequence: Limine + Plymouth → Omarchy

# 14a. Limine: rename boot entry from CachyOS to Omarchy
if ! grep -q 'TARGET_OS_NAME="Omarchy"' /etc/default/limine; then
    echo 'TARGET_OS_NAME="Omarchy"' | sudo tee -a /etc/default/limine > /dev/null
    echo "[*] Limine TARGET_OS_NAME set to Omarchy."
fi
sudo sed -i 's|^/+CachyOS$|/+Omarchy|' /boot/limine.conf
echo "[*] Limine boot entry renamed to Omarchy."

# 14b. Limine splash: replace with current Omarchy wallpaper
WALLPAPER="$HOME/.config/omarchy/current/background"
if [[ -f "$WALLPAPER" ]] && command -v magick &>/dev/null; then
    magick "$WALLPAPER" -resize 2560x1440^ -gravity Center -extent 2560x1440 /tmp/omarchy-limine-splash.png
    sudo cp /tmp/omarchy-limine-splash.png /boot/limine-splash.png
    echo "[*] Limine splash set to current Omarchy wallpaper."
fi

# 14c. Plymouth: change from cachyos-bootanimation to fade-in
if ! grep -q 'Theme=fade-in' /etc/plymouth/plymouthd.conf; then
    sudo sed -i 's/^Theme=.*/Theme=fade-in/' /etc/plymouth/plymouthd.conf
    echo "[*] Plymouth theme set to fade-in (rebuilding initramfs, please wait...)"
    sudo mkinitcpio -P
    echo "[*] Initramfs rebuilt."
fi

# 14d. Hook: keep Limine splash in sync with Omarchy theme changes
HOOKS_DIR="$HOME/.config/omarchy/hooks"
mkdir -p "$HOOKS_DIR"
if ! grep -q "limine-splash" "$HOOKS_DIR/theme-set" 2>/dev/null; then
    cat >> "$HOOKS_DIR/theme-set" << 'HOOKEOF'
# Sync Limine boot splash with current Omarchy wallpaper
if [[ -f "$OMARCHY_BG" ]] && command -v magick &>/dev/null; then
    magick "$OMARCHY_BG" -resize 2560x1440^ -gravity Center -extent 2560x1440 /tmp/omarchy-limine-splash.png
    sudo cp /tmp/omarchy-limine-splash.png /boot/limine-splash.png
fi
HOOKEOF
    echo "[*] Limine splash sync hook updated."
fi

# 15. Steam HiDPI scaling via Xft.dpi (CEF reads this to set device pixel ratio)
XFT_DPI=$(awk "BEGIN { printf \"%d\", 96 * $SCALE + 0.5 }")
printf 'Xft.dpi: %s\n' "$XFT_DPI" > "$HOME/.Xresources"
xrdb -merge "$HOME/.Xresources"
echo "[*] Xft.dpi set to $XFT_DPI for Steam/CEF HiDPI scaling."

AUTOSTART_LUA="$HOME/.config/hypr/autostart.lua"
if [[ -f "$AUTOSTART_LUA" ]] && ! grep -q "xrdb.*Xresources" "$AUTOSTART_LUA"; then
    cat >> "$AUTOSTART_LUA" << 'EOF'

-- Load X11 DPI so CEF/Steam scales its UI correctly on XWayland.
hl.on("hyprland.start", function()
  hl.exec_cmd("xrdb -merge ~/.Xresources")
end)
EOF
    echo "[*] xrdb autostart added."
fi

# Clean up failed Steam scaling attempts
rm -f "$HOME/.config/environment.d/steam-scale.conf"
rm -f "$HOME/.local/share/applications/steam.desktop"

# 16. Claude Code plugins
echo "[*] Installing Claude Code plugins..."

# Caveman: compresses Claude output ~65-75% using terse language
if ! claude plugin list 2>/dev/null | grep -q "caveman"; then
    curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash
    echo "[*] Caveman installed."
else
    echo "[*] Caveman already installed, skipping."
fi

# find-skills: discover and install skills from the skills.sh marketplace
if [[ ! -d "$HOME/.agents/skills/find-skills" ]]; then
    cd "$HOME" && npx skills add https://github.com/vercel-labs/skills --skill find-skills
    echo "[*] find-skills installed."
else
    echo "[*] find-skills already installed, skipping."
fi

# 17. Set Nord as default theme
echo "[*] Setting Nord theme..."
omarchy theme set "Nord"
echo "[*] Nord theme applied."

# 17. Copy GitHub keys to clipboard
echo ""
echo "[*] Ahora vamos a copiar tus llaves de GitHub al portapapeles una a una."
echo "    Agrégalas en: github.com → Settings → SSH and GPG keys"
echo ""

echo "--- LLAVE SSH ---"
echo "Presiona Enter para copiar la llave SSH al portapapeles..."
read -r
cat "$HOME/.ssh/id_ed25519.pub" | wl-copy
echo "[*] Llave SSH copiada. Pégala en GitHub como 'New SSH key'."
echo ""

echo "--- LLAVE GPG ---"
echo "Presiona Enter para copiar la llave GPG al portapapeles..."
read -r
gpg --armor --export ga.anzola15@gmail.com | wl-copy
echo "[*] Llave GPG copiada. Pégala en GitHub como 'New GPG key'."
