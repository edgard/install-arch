#!/bin/bash

set -x -e -o pipefail

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------
helper_pkg_exists() {
    if [[ "$1" == "" ]]; then return; fi
    local _package=$1
    if pacman -Qs "^${_package}$" >/dev/null; then
        return 0
    else
        return 1
    fi
}

helper_pkg_install() {
    if [[ "$1" == "" ]]; then return; fi
    local _packages=$*
    pacaur -S --needed --noconfirm --noedit --noprogressbar ${_packages}
}

helper_pkg_remove() {
    if [[ "$1" == "" ]]; then return; fi
    local _packages=$*
    sudo pacman -Rns --noconfirm --noprogressbar ${_packages}
}

helper_svc_enable() {
    if [[ "$1" == "" ]]; then return; fi
    local _services=$*
    sudo systemctl enable ${_services}
}

helper_svc_disable() {
    if [[ "$1" == "" ]]; then return; fi
    local _services=$*
    sudo systemctl disable ${_services}
}

helper_svc_mask() {
    if [[ "$1" == "" ]]; then return; fi
    local _services=$*
    sudo systemctl mask ${_services}
}

helper_cfg_get(){
    local _index=$1
    jq -r ".${_index} | flatten | join(\" \")" config.json
}

helper_file_append() {
    local _file=$1
    local _content=$2
    grep -q -F "${_content}" "${_file}" || echo -E "${_content}" | sudo tee -a "${_file}"
}

helper_update_boot() {
    sudo dkms autoinstall || true
    sudo mkinitcpio -P
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

# -----------------------------------------------------------------------------
# install aur helper tool
# -----------------------------------------------------------------------------
install_pacaur() {
    if ! helper_pkg_exists "pacaur"; then
        gpg_key_file=$(mktemp)
        curl -so "${gpg_key_file}" "https://pgp.mit.edu/pks/lookup?op=get&search=0x1EB2638FF56C0C53"
        gpg --import "${gpg_key_file}"

        sudo pacman -S --needed --noconfirm --noprogressbar base-devel git

        build_root=$(mktemp -d)

        (
            cd "${build_root}" || exit 1
            git clone "https://aur.archlinux.org/cower.git" --depth=1
            git clone "https://aur.archlinux.org/pacaur.git" --depth=1

            cd "${build_root}/cower" || exit 1
            makepkg -si --noconfirm --needed

            cd "${build_root}/pacaur" || exit 1
            makepkg -si --noconfirm --needed
        )

        rm -rf "${build_root}"
    fi
}


# -----------------------------------------------------------------------------
# install common pkgs
# -----------------------------------------------------------------------------
install_packages_common() {
    helper_pkg_install $(helper_cfg_get "packages.install.common")
    helper_pkg_remove $(helper_cfg_get "packages.remove.common")
    helper_svc_disable $(helper_cfg_get "services.disable.common")
    helper_svc_enable $(helper_cfg_get "services.enable.common")
    helper_svc_mask $(helper_cfg_get "services.mask.common")
}


# -----------------------------------------------------------------------------
# install desktop pkgs
# -----------------------------------------------------------------------------
install_packages_desktop() {
    helper_pkg_install $(helper_cfg_get "packages.install.desktop")
    helper_pkg_remove $(helper_cfg_get "packages.remove.desktop")
    helper_svc_disable $(helper_cfg_get "services.disable.desktop")
    helper_svc_enable $(helper_cfg_get "services.enable.desktop")
    helper_svc_mask $(helper_cfg_get "services.mask.desktop")
}


# -----------------------------------------------------------------------------
# install nvidia driver pkgs
# -----------------------------------------------------------------------------
install_packages_nvidia() {
    helper_pkg_install $(helper_cfg_get "packages.install.misc.nvidia")
    helper_update_boot
    helper_svc_enable "nvidia-persistenced"
}


# -----------------------------------------------------------------------------
# install kubernetes dev pkgs
# -----------------------------------------------------------------------------
install_packages_kubernetes() {
    helper_pkg_install $(helper_cfg_get "packages.install.misc.kubernetes")
}


# -----------------------------------------------------------------------------
# install gaming pkgs
# -----------------------------------------------------------------------------
install_packages_gaming() {
    helper_pkg_install $(helper_cfg_get "packages.install.misc.gaming")
}


# -----------------------------------------------------------------------------
# install atom extensions
# -----------------------------------------------------------------------------
install_atom_extensions() {
    for ext in $(helper_cfg_get "misc.atom_ext"); do
        apm install "${ext}" || true
    done
}


# -----------------------------------------------------------------------------
# configuration for base
# -----------------------------------------------------------------------------
config_base() {
    sudo usermod -a -G docker "${USER}"
    helper_file_append /etc/hosts "127.0.1.1	$(hostname -s).localdomain	$(hostname -s)"
    sudo sed 's/^#SystemMaxUse=.*/SystemMaxUse=50M/' -i /etc/systemd/journald.conf
    sudo sed '/^# %wheel ALL=(ALL) ALL/ s/^# //' -i /etc/sudoers
}


# -----------------------------------------------------------------------------
# configuration for desktop
# -----------------------------------------------------------------------------
config_desktop() {
    sudo usermod -a -G adm,audio,disk,floppy,input,log,lp,optical,power,rfkill,scanner,storage,sys,uucp,video "${USER}"

    sudo sed 's/^hosts:.*/hosts: files mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns myhostname/' -i /etc/nsswitch.conf
    sudo nscd -i hosts

    sudo ln -sf /etc/fonts/conf.avail/10-antialias.conf /etc/fonts/conf.d/10-antialias.conf
    sudo ln -sf /etc/fonts/conf.avail/10-hinting.conf /etc/fonts/conf.d/10-hinting.conf
    sudo ln -sf /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
    sudo ln -sf /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d/11-lcdfilter-default.conf
    sudo ln -sf /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/70-no-bitmaps.conf

    sudo install -Dm644 -o root -g root files/desktop/20-mouse-tweaks.conf /etc/X11/xorg.conf.d/20-mouse-tweaks.conf
    sudo install -Dm644 -o root -g root files/desktop/20-touchpad-tweaks.conf /etc/X11/xorg.conf.d/20-touchpad-tweaks.conf

    sudo sed 's/^#WaylandEnable=.*/WaylandEnable=false/' -i /etc/gdm/custom.conf

    helper_file_append /etc/xdg/Trolltech.conf "[Qt]"
    helper_file_append /etc/xdg/Trolltech.conf "style=GTK+"
    helper_file_append /etc/environment "QT_QPA_PLATFORMTHEME=gtk2"
}


# -----------------------------------------------------------------------------
# configuration of gnome desktop
# -----------------------------------------------------------------------------
config_gnome() {
    gsettings set org.gnome.desktop.datetime automatic-timezone true
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us+intl')]"
    gsettings set org.gnome.desktop.interface clock-format "'12h'"
    gsettings set org.gnome.desktop.interface gtk-theme "'Arc'"
    gsettings set org.gnome.desktop.interface icon-theme "'Papirus'"
    gsettings set org.gnome.desktop.notifications show-in-lock-screen false
    gsettings set org.gnome.desktop.peripherals.mouse accel-profile "'flat'"
    gsettings set org.gnome.desktop.wm.preferences button-layout "'appmenu:minimize,maximize,close'"
    gsettings set org.gnome.desktop.wm.preferences num-workspaces "6"
    gsettings set org.gnome.mutter center-new-windows true
    gsettings set org.gnome.nautilus.preferences executable-text-activation "'launch'"
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'suspend'"
    gsettings set org.gnome.settings-daemon.plugins.xsettings antialiasing "'rgba'"
    gsettings set org.gnome.settings-daemon.plugins.xsettings hinting "'slight'"
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'atom.desktop', 'spotify.desktop', 'skypeforlinux.desktop', 'telegramdesktop.desktop', 'chromium.desktop']"
    gsettings set org.gnome.shell.extensions.user-theme name "'Arc-Dark'"
    gsettings set org.gnome.shell.overrides dynamic-workspaces false
    gsettings set org.gnome.system.locale region "'en_US.UTF-8'"
    gsettings set org.gnome.system.location enabled true
    gsettings set org.gtk.Settings.FileChooser clock-format "'12h'"
    gsettings set org.gtk.Settings.FileChooser sort-directories-first true

    # shortcuts
    gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Shift><Super>1']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Shift><Super>2']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Shift><Super>3']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Shift><Super>4']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Shift><Super>5']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-6 "['<Shift><Super>6']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-down "['<Control><Shift><Alt>Down']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-up "['<Control><Shift><Alt>Up']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Super>5']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-6 "['<Super>6']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down "['<Control><Alt>Down']"
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up "['<Control><Alt>Up']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding "'<Super>Return'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command "'gnome-terminal'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name "'Launch Terminal'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ binding "'<Super>slash'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ command "'chromium'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ name "'Launch Browser'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ binding "'<Super>period'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ command "'gedit'"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ name "'Launch Editor'"

    # terminal: one-dark
    gsettings set org.gnome.Terminal.Legacy.Settings new-terminal-mode "'tab'"
    gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" use-system-font false
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" font "'PragmataPro Mono 12'"
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" login-shell true
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" allow-bold false
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" bold-color-same-as-fg true
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" use-theme-colors false
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" scrollbar-policy "'never'"

    # terminal: one dark
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" palette "['#282c34', '#e06c75', '#98c379', '#e5c07b', '#61afef', '#c678dd', '#56b6c2', '#abb2bf', '#5c6370', '#be5046', '#7a9f60', '#d19a66', '#3b84c0', '#9a52af', '#3c909b', '#828997']"
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" background-color "'#282c34'"
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" foreground-color "'#abb2bf'"
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | sed s/^\'// | sed s/\'$//)/" bold-color "'#abb2bf'"

    # extensions
    gsettings set org.gnome.shell enabled-extensions "['user-theme@gnome-shell-extensions.gcampax.github.com', 'alternate-tab@gnome-shell-extensions.gcampax.github.com', 'dash-to-panel@jderose9.github.com', 'openweather-extension@jenslody.de', 'caffeine@patapon.info', 'clipboard-indicator@tudmotu.com', 'nohotcorner@azuri.free.fr', 'TopIcons@phocean.net', 'impatience@gfxmonk.net', 'panel-osd@berend.de.schouwer.gmail.com']"

    # ext: dash-to-panel
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel dot-style-focused "SQUARES"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel dot-style-unfocused "SQUARES"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel location-clock "'NATURAL'"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel animate-show-apps true
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel tray-padding "2"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel status-icon-padding "8"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel appicon-margin "6"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas gsettings set org.gnome.shell.extensions.dash-to-panel show-showdesktop-button false

    # ext: topicons-plus
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/TopIcons@phocean.net/schemas gsettings set org.gnome.shell.extensions.topicons icon-saturation "0.0"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/TopIcons@phocean.net/schemas gsettings set org.gnome.shell.extensions.topicons icon-opacity "255"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/TopIcons@phocean.net/schemas gsettings set org.gnome.shell.extensions.topicons icon-size "22"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/TopIcons@phocean.net/schemas gsettings set org.gnome.shell.extensions.topicons icon-spacing "14"
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/TopIcons@phocean.net/schemas gsettings set org.gnome.shell.extensions.topicons tray-order "2"

    # ext: openweather
    gsettings set org.gnome.shell.extensions.openweather weather-provider "'darksky.net'"
    gsettings set org.gnome.shell.extensions.openweather geolocation-provider "'geocode'"
    gsettings set org.gnome.shell.extensions.openweather unit "'celsius'"
    gsettings set org.gnome.shell.extensions.openweather wind-speed-unit "'kph'"
    gsettings set org.gnome.shell.extensions.openweather pressure-unit "'hPa'"
    gsettings set org.gnome.shell.extensions.openweather center-forecast true
    gsettings set org.gnome.shell.extensions.openweather decimal-places "0"
    gsettings set org.gnome.shell.extensions.openweather show-text-in-panel false

    # ext: clipboard indicator
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/clipboard-indicator@tudmotu.com/schemas gsettings set org.gnome.shell.extensions.clipboard-indicator notify-on-copy false
    GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/clipboard-indicator@tudmotu.com/schemas gsettings set org.gnome.shell.extensions.clipboard-indicator enable-keybindings false

    # ext: caffeine
    gsettings set org.gnome.shell.extensions.caffeine show-notifications false

    # ext: panel-osd
    gsettings set org.gnome.shell.extensions.panel-osd x-pos 100.0
    gsettings set org.gnome.shell.extensions.panel-osd y-pos 0.0
}


# -----------------------------------------------------------------------------
# configuration of personal desktop fixes
# -----------------------------------------------------------------------------
config_personal_fixes_desktop() {
    sudo install -Dm644 -o root -g root files/personal/20-nvidia.conf /etc/X11/xorg.conf.d/20-nvidia.conf
    sudo sed 's/^GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX=text/' -i /etc/default/grub
    helper_file_append /etc/environment "CLUTTER_VBLANK=none"
    helper_update_boot
}


# -----------------------------------------------------------------------------
# configuration of personal notebook fixes
# -----------------------------------------------------------------------------
config_personal_fixes_notebook() {
    sudo install -Dm644 -o root -g root files/personal/20-intel.conf /etc/X11/xorg.conf.d/20-intel.conf
}


# -----------------------------------------------------------------------------
# generate ssh keys
# -----------------------------------------------------------------------------
generate_sshkeys() {
    ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
}


# -----------------------------------------------------------------------------
# install script dependencies
# -----------------------------------------------------------------------------
sudo pacman -S --needed --noconfirm --noprogressbar jq


# -----------------------------------------------------------------------------
# install menu
# -----------------------------------------------------------------------------
cmd=(whiptail --separate-output --notags --backtitle "Arch Install" --title "Tasks" --checklist "Select options:" 18 49 13)
options=("install_pacaur" "1 | Install AUR helper tool" off
         "install_packages_common" "1 | Install common pkgs" off
         "config_base" "1 | Configuration for base" off
         "install_packages_desktop" "2 | Install desktop pkgs" off
         "config_desktop" "2 | Configuration for desktop" off
         "config_personal_fixes_desktop" "3 | Configuration of desktop fixes" off
         "config_personal_fixes_notebook" "3 | Configuration of notebook fixes" off
         "install_packages_nvidia" "4 | Install Nvidia driver pkgs" off
         "config_gnome" "5 | Configuration of GNOME desktop" off
         "install_atom_extensions" "5 | Install Atom extensions" off
         "install_packages_kubernetes" "O | Install Kubernetes dev pkgs" off
         "install_packages_gaming" "O | Install gaming pkgs" off
         "generate_sshkeys" "O | Generate new SSH keys" off)

choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

clear
sudo -v

for choice in ${choices}; do
    if ! (eval "${choice}"); then
    echo "ERROR: task ${choice} failed, aborting..."
    exit 1
    fi
done
