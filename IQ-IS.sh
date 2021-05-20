#!/bin/sh

while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit 1 ;;
	r) DotFilesRepo=${OPTARG} && git ls-remote "$DotFilesRepo" || exit 1 ;;
	b) RepoBranch=${OPTARG} ;;
	p) ProgramsFile=${OPTARG} ;;
	a) AurHelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$DotFilesRepo" ] && DotFilesRepo="https://github.com/IntelligentQuantum/IQ-DotFiles.git"
[ -z "$ProgramsFile" ] && ProgramsFile="https://raw.githubusercontent.com/IntelligentQuantum/IQ-IS/main/Programs.csv"
[ -z "$AurHelper" ] && AurHelper="yay"
[ -z "$RepoBranch" ] && RepoBranch="main"

InstallPKG()
{
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1;
}

Error()
{
    clear;
    printf "ERROR:\\n%s\\n" "$1" >&2; exit 1;
}

WelcomeMessage()
{ \
	dialog --title "Welcome!" --msgbox "Welcome to IntelligentQuantum Installation Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, which I use as my main machine.\\n\\n-IntelligentQuantum" 10 60
	dialog --colors --title "Important Note!" --yes-label "All ready!" --no-label "Return..." --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

GetUserAndPass()
{ \
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done ;
}

CheckUser()
{ \
	! { id -u "$name" >/dev/null 2>&1; } ||
	dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. IQ-IS can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nIQ-IS will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that IQ-IS will change $name's password to the one you just gave." 14 70
}

PreInstallMessage()
{ \
	dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
}

AddUserAndPass()
{ \
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2;
}

RefreshKeys()
{ \
	dialog --infobox "Refreshing Arch Keyring..." 4 40
	pacman -Q artix-keyring >/dev/null 2>&1 && pacman --noconfirm -S artix-keyring >/dev/null 2>&1
	pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
}

NewPermissions()
{
    # Set special sudoers settings for install (or after).
	sed -i "/#IQ-IS/d" /etc/sudoers
	echo "$* #IQ-IS" >> /etc/sudoers;
}

ManualInstall()
{
    # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	cd /tmp || exit 1
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return 1);
}

MainInstall()
{
    # Installs all needed programs from main repo.
	dialog --title "IQ-IS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	InstallPKG "$1"
}

GitMakeInstall()
{
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	dialog --title "IQ-IS Installation" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin main;}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1;
}

AurInstall()
{ \
	dialog --title "IQ-IS Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $AurHelper -S --noconfirm "$1" >/dev/null 2>&1
}

PipInstall()
{ \
	dialog --title "IQ-IS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	[ -x "$(command -v "pip")" ] || InstallPKG python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

InstallationLoop()
{ \
	([ -f "$ProgramsFile" ] && cp "$ProgramsFile" /tmp/Programs.csv) || curl -Ls "$ProgramsFile" | sed '/^#/d' > /tmp/Programs.csv
	total=$(wc -l < /tmp/Programs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") AurInstall "$program" "$comment" ;;
			"G") GitMakeInstall "$program" "$comment" ;;
			"P") PipInstall "$program" "$comment" ;;
			*) MainInstall "$program" "$comment" ;;
		esac
	done < /tmp/Programs.csv;
}

PutGitRepo()
{
    # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	dialog --infobox "Downloading and installing config files..." 4 60
	[ -z "$3" ] && branch="master" || branch="$RepoBranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git clone --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir" >/dev/null 2>&1
	sudo -u "$name" cp -rfT "$dir" "$2"
}

SystemBeepOff()
{
    dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf;
}

Finalize()
{ \
	dialog --infobox "Preparing welcome message..." 4 50
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t IntelligentQuantum" 12 80
}

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || Error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user and pick dotfiles.
WelcomeMessage || Error "User exited."

# Get and verify username and password.
GetUserAndPass || Error "User exited."

# Give warning if user already exists.
CheckUser || Error "User exited."

# Last chance for user to back out before install.
PreInstallMessage || Error "User exited."

# Refresh Arch keyrings.
RefreshKeys || Error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl base-devel git ntp zsh; do
	dialog --title "IQ-IS Installation" --infobox "Installing \`$x\` which is required to install and configure other programs." 5 70
	InstallPKG "$x"
done

dialog --title "IQ-IS Installation" --infobox "Synchronizing system time to ensure successful and secure installation of software..." 4 70
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

AddUserAndPass || Error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fake root environment, this is required for all builds with AUR.
NewPermissions "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

ManualInstall $AurHelper || Error "Failed to install AUR helper."

# The command that does all the installing. Reads the Programs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has privileges to run sudo without a password
# and all build dependencies are installed.
InstallationLoop

dialog --title "IQ-IS Installation" --infobox "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes." 5 70
yes | sudo -u "$name" $AurHelper -S libxft-bgra-git >/dev/null 2>&1

# Install the dotfiles in the user's home directory
PutGitRepo "$DotFilesRepo" "/home/$name" "$RepoBranch"
rm -f "/home/$name/README.md" "/home/$name/.editorconfig" "/home/$name/.gitignore" "/home/$name/.gitmodules" "/home/$name/.git"
# Create default urls file if none exists.
[ ! -f "/home/$name/.config/newsboat/urls" ] && echo "https://www.archlinux.org/feeds/news/" > "/home/$name/.config/newsboat/urls"

# Most important command! Get rid of the beep!
SystemBeepOff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen > /var/lib/dbus/machine-id

# Tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
	echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# Start/restart PulseAudio.
killall pulseaudio; sudo -u "$name" pulseaudio --start

# This line, overwriting the `NewPermissions` command above will allow the user to run
# several important commands, `shutdown`, `reboot`, updating, etc. without a password.
NewPermissions "%wheel ALL=(ALL) ALL #IQ-IS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
Finalize
clear
