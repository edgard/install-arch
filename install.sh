#!/usr/bin/env bash

set -Eeuxo pipefail

# -----------------------------------------------------------------------------
# install config
# -----------------------------------------------------------------------------
CONFIG_DISK="/dev/sda"
CONFIG_HOSTNAME="arch"
CONFIG_USER="edgard"
CONFIG_ZONEINFO="Europe/Warsaw"
CONFIG_COUNTRY="PL"

# -----------------------------------------------------------------------------
# update mirrorlist
# -----------------------------------------------------------------------------
MIRRORLIST="https://www.archlinux.org/mirrorlist/?country=${CONFIG_COUNTRY}&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"
curl -s "${MIRRORLIST}" | sed 's/^#Server/Server/' >/etc/pacman.d/mirrorlist

# -----------------------------------------------------------------------------
# system install
# -----------------------------------------------------------------------------
timedatectl set-ntp true
sgdisk --zap ${CONFIG_DISK}
dd if=/dev/zero of=${CONFIG_DISK} bs=512 count=2048
wipefs --all ${CONFIG_DISK}
sgdisk -n 1:0:+1M -c 1:"BIOS Boot Partition" -t 1:ef02 ${CONFIG_DISK}
sgdisk -n 2:0:+200M -c 2:"EFI System Partition" -t 2:ef00 ${CONFIG_DISK}
sgdisk -n 3:0:+200M -c 3:"Linux boot" -t 3:8300 ${CONFIG_DISK}
sgdisk -n 4:0:0 -c 4:"Linux root" -t 4:8300 ${CONFIG_DISK}
sgdisk ${CONFIG_DISK} -A 1:set:2
sgdisk -p ${CONFIG_DISK}
mkfs.fat -F32 ${CONFIG_DISK}2
mkfs.ext4 -O ^64bit -F -m 0 -q ${CONFIG_DISK}3
mkfs.ext4 -O ^64bit -F -m 0 -q ${CONFIG_DISK}4
mount ${CONFIG_DISK}4 /mnt
mkdir -p /mnt/efi /mnt/boot
mount ${CONFIG_DISK}2 /mnt/efi
mount ${CONFIG_DISK}3 /mnt/boot
pacstrap /mnt base base-devel
genfstab -U /mnt >>/mnt/etc/fstab

cat <<EOF >/mnt/install.sh
pacman -S --needed --noconfirm openssh grub os-prober efibootmgr
ln -sf /usr/share/zoneinfo/${CONFIG_ZONEINFO} /etc/localtime
sed '/^#en_US\.UTF-8/ s/^#//' -i /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "${CONFIG_HOSTNAME}" > /etc/hostname
echo "127.0.1.1	${CONFIG_HOSTNAME}.localdomain	${CONFIG_HOSTNAME}" >> /etc/hosts
mkinitcpio -p linux
useradd -m -p \$(openssl passwd -crypt "${CONFIG_USER}") ${CONFIG_USER}
usermod -a -G wheel ${CONFIG_USER}
sed '/^# %wheel ALL=(ALL) ALL/ s/^# //' -i /etc/sudoers
grub-install --target=i386-pc ${CONFIG_DISK}
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable dhcpcd sshd
EOF

chmod +x /mnt/install.sh
arch-chroot /mnt /install.sh
rm /mnt/install.sh

# -----------------------------------------------------------------------------
# system cleanup
# -----------------------------------------------------------------------------
cat <<'EOF' >/mnt/cleanup.sh
usermod -L root
yes | pacman -Scc
rm -rf /tmp/*
rm -rf /var/lib/dhcp/*
rm -rf /root/.ssh
unset HISTFILE
rm -f /root/.bash_history
find /var/log -type f | while read f; do echo -ne '' > "${f}"; done;
>/var/log/lastlog
>/var/log/wtmp
>/var/log/btmp
rm -rf /dev/.udev/
EOF

chmod +x /mnt/cleanup.sh
arch-chroot /mnt /cleanup.sh
rm /mnt/cleanup.sh

# -----------------------------------------------------------------------------
# finish installation
# -----------------------------------------------------------------------------
umount /mnt/efi
umount /mnt/boot
umount /mnt
sync
