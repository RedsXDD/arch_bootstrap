#!/usr/bin/env sh

# Setup "Reds" user & account passwords:
useradd -mG 'wheel,input' Reds # Input group is for waybar.
passwd
passwd Reds

# until [ -n "$password1" -a -n "$password2" -a "$password1" = "$password2" ];
# do
# 	printf 'Please provide a password for the root user and the new user "Reds": '; read password1
# 	printf 'Please repeat the password provided: '; read password2
# 	[ "$password1" != "$password2" ] && echo 'Passwords are not the same, please try again'; echo ''
# done
# pass="$password1"
# yes "$pass" | passwd
# yes "$pass" | passwd Reds

#: Generate pacman config file {{{
pacman_conf(){
	cat <<- PACMAN_EOF
	[options]
	HoldPkg = pacman glibc
	Architecture = auto
	Color
	CheckSpace
	VerbosePkgLists
	ParallelDownloads = 5
	ILoveCandy
	SigLevel = Required DatabaseOptional
	LocalFileSigLevel = Optional

	[core]
	Include = /etc/pacman.d/mirrorlist

	[extra]
	Include = /etc/pacman.d/mirrorlist

	[multilib]
	Include = /etc/pacman.d/mirrorlist

	[chaotic-aur]
	Include = /etc/pacman.d/chaotic-mirrorlist
	PACMAN_EOF
}

# Setup chaotic aur:
gpg --list-keys >/dev/null 2>&1
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# Setup new pacman.conf
sudo cp -rvf /etc/pacman.conf /etc/pacman.conf.bak
pacman_conf | sudo tee /etc/pacman.conf >/dev/null 2>&1
#: }}}
#: Inital setup {{{
# Install basic packages:
sudo pacman --noconfirm -Syyu networkmanager neovim grub efibootmgr ntp git dash gpm opendoas man-db man-pages

# Setup GRUB:
sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Enable basic systemctl stuff:
sudo systemctl enable NetworkManager
sudo systemctl enable gpm
sudo systemctl start gpm

# Setup time:
sudo ln -svf /usr/share/zoneinfo/Brazil/East /etc/localtime
sudo hwclock --systohc
sudo systemctl enable ntpd.service
sudo systemctl enable ntpdate.service
sudo systemctl start ntpd.service
sudo timedatectl set-ntp true

# Enable sysrq
echo "1" | sudo tee /proc/sys/kernel/sysrq >/dev/null 2>&1

# Cache manpages (useful for man -k)
sudo mandb
#: }}}
#: Setup locales {{{
# shellcheck disable=2024
tmp_locale_gen="$(mktemp)"
trap 'rm -rf "$tmp_locale_gen"' 0 1 15

sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/; s/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen > "$tmp_locale_gen"
sudo tee /etc/locale.gen < "$tmp_locale_gen"  >/dev/null 2>&1
echo 'LANG=en_US.UTF-8' | sudo tee -a /etc/locale.conf >/dev/null 2>&1
sudo locale-gen
#: }}}
#: Setup hostname/hosts {{{
gen_hosts(){
	cat <<- HOSTS_EOF
	127.0.0.1	localhost
	::1		localhost
	127.0.1.1	Redsarch.localdomain	Redsarch
	HOSTS_EOF
}
gen_hosts | sudo tee /etc/hosts >/dev/null 2>&1
echo 'Redsarch' | sudo tee /etc/hostname >/dev/null 2>&1
#: }}}
#: Generate vconsole.conf {{{
gen_vconsole(){
	cat <<- VCONF
	KEYMAP=br-abnt2
	# FONT=Agafari-16.psfu.gz
	FONT=ter-118b.psf.gz
	XKBLAYOUT=br
	XKBMODEL=pc105
	XKBVARIANT=,nodeadkeys
	XKBOPTIONS=grp:win_space_toggle
	VCONF
}
gen_vconsole | sudo tee /etc/vconsole.conf >/dev/null 2>&1
#: }}}
#: Notification daemon {{{
notify_txt(){
	cat <<- NOTIFY_EOF
	[D-BUS Service]
	Name=org.freedesktop.Notifications
	Exec=/usr/lib/notification-daemon-1.0/notification-daemon
	NOTIFY_EOF
}
sudo mkdir -p /usr/share/dbus-1/services
notify_txt | sudo tee /usr/share/dbus-1/services/org.freedesktop.Notifications.service >/dev/null 2>&1
#: }}}
#: Setup dash as /bin/sh {{{
redash_txt(){
	cat <<- REDASH_EOF
	[Trigger]
	Type = Package
	Operation = Install
	Operation = Upgrade
	Target = bash

	[Action]
	Description = Re-pointing /bin/sh symlink to dash...
	When = PostTransaction
	Exec = /usr/bin/ln -sfT dash /usr/bin/sh
	Depends = dash
	REDASH_EOF
}
sudo ln -sfT dash /usr/bin/sh
redash_txt | sudo tee /usr/share/libalpm/hooks/redash.hook >/dev/null 2>&1
#: }}}
#: Inital setup of doas.conf/sudoers file {{{
# Add wheel group to /etc/sudoers file:
tmp_sudoers="$(mktemp)"
trap 'rm -rf "$tmp_sudoers"' 0 1 15
sed 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers > "$tmp_sudoers"
cat "$tmp_sudoers" > /etc/sudoers

# Generate doas.conf:
echo 'permit nopass persist :wheel' | sudo tee /etc/doas.conf >/dev/null 2>&1
echo 'permit nopass root as root' | sudo tee -a /etc/doas.conf >/dev/null 2>&1

# Set the right permissions to the config file:
sudo chown -c root:root /etc/doas.conf
sudo chmod -c 0400 /etc/doas.conf
#: }}}
#: Generate/execute part two of script {{{
gen_part2(){
	cat <<- GENPART2_EOF
	#!/usr/bin/env sh

	# Install Paru & install packages:
	tmp_paru="\$(mktemp -d)"
	trap 'rm -rf "\$tmp_paru"' 0 1 9 15
	git clone https://aur.archlinux.org/paru.git "\$tmp_paru"/paru
	cd "\$tmp_paru"/paru
	sudo makepkg --noconfirm -si
	rm -rf "\$tmp_paru"
	list_file="/home/Reds/.local/bin/not_path/post-install/arch/pkgs"
	sed '/^#/d; s/#.*//g; /^$/d' < "\$list_file" | xargs -ro paru --needed -S

	# Starship Prompt:
	curl -fsSL https://starship.rs/install.sh | sh

	# Ollama:
	curl -fsSL https://ollama.com/install.sh | sh
	GENPART2_EOF
}
part2_script_path="$(mktemp)"
gen_part2 > "$part2_script_path"
chmod u+x "$part2_script_path"
sudo chown Reds:Reds "$part2_script_path"
su -c "$part2_script_path" -s /bin/sh Reds
#: }}}
#: Fix sudo/doas permissions {{{
echo 'permit persist :wheel' | sudo tee /etc/doas.conf >/dev/null 2>&1
sed 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g; s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers > "$tmp_sudoers"
sudo tee /etc/sudoers < "$tmp_sudoers" >/dev/null 2>&1

# Create a symlink from /usr/bin/sudo to /usr/bin/doas:
sudo ln -sf /usr/bin/doas /usr/bin/sudo
#: }}}

# vim:fileencoding=utf-8:foldmethod=marker:filetype=sh
