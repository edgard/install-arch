#!/usr/bin/env bash

set -Eeuxo pipefail

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
	yay -S --needed --noconfirm --noprogressbar --nocleanmenu --nodiffmenu --noeditmenu --removemake --cleanafter ${_packages}
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

helper_cfg_get() {
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
install_yay() {
	if ! helper_pkg_exists "yay"; then
		sudo pacman -S --needed --noconfirm --noprogressbar base-devel git

		build_root=$(mktemp -d)

		(
			cd "${build_root}" || exit 1
			git clone "https://aur.archlinux.org/yay.git" --depth=1

			cd "${build_root}/yay" || exit 1
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
# install tools pkgs
# -----------------------------------------------------------------------------
install_packages_tools() {
	helper_pkg_install $(helper_cfg_get "packages.install.tools")
}

# -----------------------------------------------------------------------------
# install dwm pkgs
# -----------------------------------------------------------------------------
install_packages_dwm() {
	helper_pkg_install $(helper_cfg_get "packages.install.dwm")
	helper_pkg_remove $(helper_cfg_get "packages.remove.dwm")
	helper_svc_disable $(helper_cfg_get "services.disable.dwm")
	helper_svc_enable $(helper_cfg_get "services.enable.dwm")
	helper_svc_mask $(helper_cfg_get "services.mask.dwm")
}

# -----------------------------------------------------------------------------
# install dwm_minimal pkgs
# -----------------------------------------------------------------------------
install_packages_dwm_minimal() {
	helper_pkg_install $(helper_cfg_get "packages.install.dwm_minimal")
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
# install virtualbox host pkgs
# -----------------------------------------------------------------------------
install_packages_virtualbox_host() {
	helper_pkg_install $(helper_cfg_get "packages.install.misc.virtualbox_host")
}

# -----------------------------------------------------------------------------
# install virtualbox guest pkgs
# -----------------------------------------------------------------------------
install_packages_virtualbox_guest() {
	helper_pkg_install $(helper_cfg_get "packages.install.misc.virtualbox_guest")
	echo -e "vboxguest\nvboxsf\nvboxvideo" | sudo tee /etc/modules-load.d/virtualbox.conf
}

# -----------------------------------------------------------------------------
# install vmware guest pkgs
# -----------------------------------------------------------------------------
install_packages_vmware_guest() {
	helper_pkg_install $(helper_cfg_get "packages.install.misc.vmware_guest")
	helper_svc_enable "vmtoolsd.service vmware-vmblock-fuse.service"
}

# -----------------------------------------------------------------------------
# install gaming pkgs
# -----------------------------------------------------------------------------
install_packages_gaming() {
	helper_pkg_install $(helper_cfg_get "packages.install.misc.gaming")
}

# -----------------------------------------------------------------------------
# install minikube pkgs
# -----------------------------------------------------------------------------
install_packages_minikube() {
	helper_pkg_install $(helper_cfg_get "packages.install.misc.minikube")
	helper_svc_enable "libvirtd.service virtlogd.service"
}

# -----------------------------------------------------------------------------
# configuration for common
# -----------------------------------------------------------------------------
config_common() {
	sudo usermod -a -G docker "${USER}"
	sudo sed 's/^#SystemMaxUse=.*/SystemMaxUse=50M/' -i /etc/systemd/journald.conf
}

# -----------------------------------------------------------------------------
# configuration for dwm
# -----------------------------------------------------------------------------
config_dwm() {
	sudo usermod -a -G adm,audio,disk,floppy,input,log,lp,optical,power,rfkill,root,scanner,storage,sys,uucp,video "${USER}"
	sudo sed 's/^hosts:.*/hosts: files mymachines myhostname mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns/' -i /etc/nsswitch.conf
	sudo nscd -i hosts

	sudo ln -sf /etc/fonts/conf.avail/10-hinting-slight.conf /etc/fonts/conf.d/10-hinting-slight.conf
	sudo ln -sf /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
	sudo ln -sf /etc/fonts/conf.avail/11-lcdfilter-light.conf /etc/fonts/conf.d/11-lcdfilter-light.conf

	sudo install -Dm644 -o root -g root files/desktop/lxdm.conf /etc/lxdm/lxdm.conf

	sudo install -Dm644 -o root -g root files/desktop/20-mouse-tweaks.conf /etc/X11/xorg.conf.d/20-mouse-tweaks.conf
	sudo install -Dm644 -o root -g root files/desktop/20-touchpad-tweaks.conf /etc/X11/xorg.conf.d/20-touchpad-tweaks.conf

	echo -e "[Qt]\nstyle=GTK+" | sudo tee /etc/xdg/Trolltech.conf
	helper_file_append /etc/environment "QT_QPA_PLATFORMTHEME=gtk2"

	sudo sed '/^load-module module-suspend-on-idle/ s/^#*/#/' -i /etc/pulse/default.pa
}

# -----------------------------------------------------------------------------
# configuration for dwm_minimal
# -----------------------------------------------------------------------------
config_dwm_minimal() {
	sudo ln -sf /etc/fonts/conf.avail/10-hinting-slight.conf /etc/fonts/conf.d/10-hinting-slight.conf
	sudo ln -sf /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
	sudo ln -sf /etc/fonts/conf.avail/11-lcdfilter-light.conf /etc/fonts/conf.d/11-lcdfilter-light.conf

	sudo install -Dm644 -o root -g root files/desktop/20-mouse-tweaks.conf /etc/X11/xorg.conf.d/20-mouse-tweaks.conf
	sudo install -Dm644 -o root -g root files/desktop/20-touchpad-tweaks.conf /etc/X11/xorg.conf.d/20-touchpad-tweaks.conf

	echo -e "needs_root_rights=yes" | sudo tee /etc/X11/Xwrapper.config
}

# -----------------------------------------------------------------------------
# configuration for minikube
# -----------------------------------------------------------------------------
config_minikube() {
	sudo usermod -a -G libvirt "${USER}"
}

# -----------------------------------------------------------------------------
# install script dependencies
# -----------------------------------------------------------------------------
sudo pacman -S --needed --noconfirm --noprogressbar libnewt jq

# -----------------------------------------------------------------------------
# install menu
# -----------------------------------------------------------------------------
cmd=(whiptail --separate-output --notags --backtitle "Arch Install" --title "Tasks" --checklist "Select options:" 21 47 15)
options=("install_yay" "1 | Install AUR helper tool" off
	"install_packages_common" "2 | Install common pkgs" off
	"config_common" "3 | Configuration for common" off
	"install_packages_tools" "4 | Install tools pkgs" off
	"install_packages_dwm" "5 | Install dwm pkgs" off
	"install_packages_dwm_minimal" "5 | Install dwm minimal pkgs" off
	"config_dwm" "6 | Configuration for dwm" off
	"config_dwm_minimal" "6 | Configuration for dwm minimal" off
	"install_packages_nvidia" "O | Install Nvidia driver pkgs" off
	"install_packages_virtualbox_host" "O | Install VirtualBox host pkgs" off
	"install_packages_virtualbox_guest" "O | Install VirtualBox guest pkgs" off
	"install_packages_vmware_guest" "O | Install VMware guest pkgs" off
	"install_packages_gaming" "O | Install gaming pkgs" off
	"install_packages_minikube" "O | Install minikube pkgs" off
	"config_minikube" "O | Configuration for minikube" off)

choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

clear
sudo -v

for choice in ${choices}; do
	if ! (eval "${choice}"); then
		echo "ERROR: task ${choice} failed, aborting..."
		exit 1
	fi
done
