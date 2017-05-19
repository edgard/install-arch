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

    sudo ln -sf /etc/fonts/conf.avail/10-hinting-slight.conf /etc/fonts/conf.d/10-hinting-slight.conf
    sudo ln -sf /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
    sudo ln -sf /etc/fonts/conf.avail/11-lcdfilter-light.conf /etc/fonts/conf.d/11-lcdfilter-light.conf
    sudo ln -sf /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/70-no-bitmaps.conf

    sudo install -Dm644 -o root -g root files/desktop/20-mouse-tweaks.conf /etc/X11/xorg.conf.d/20-mouse-tweaks.conf
    sudo install -Dm644 -o root -g root files/desktop/20-touchpad-tweaks.conf /etc/X11/xorg.conf.d/20-touchpad-tweaks.conf

    sudo sed 's/^#WaylandEnable=.*/WaylandEnable=false/' -i /etc/gdm/custom.conf

    helper_file_append /etc/xdg/Trolltech.conf "[Qt]"
    helper_file_append /etc/xdg/Trolltech.conf "style=GTK+"
    helper_file_append /etc/environment "QT_QPA_PLATFORMTHEME=gtk2"

    sudo sed '/^load-module module-suspend-on-idle/ s/^#*/#/' -i /etc/pulse/default.pa
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
         "install_packages_nvidia" "3 | Install Nvidia driver pkgs" off
         "install_packages_kubernetes" "O | Install Kubernetes dev pkgs" off
         "install_packages_gaming" "O | Install gaming pkgs" off
         "config_desktop" "4 | Configuration for desktop" off
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
