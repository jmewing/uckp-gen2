#!/bin/bash

# Start first, by holding reset for 30 seconds and getting into recovery mode.
# Once in recovery mode, update the device to version v0.8.6 (UCKP.apq8053.v0.8.6.8cf5792.181017.0942.bin)
# This allows for more space on the original install/squish.fs locations
# After updating to v0.8.6, reset to factory, then reboot.
# Default Username/Password is ubnt/ubnt
# $curl https://raw.githubusercontent.com/jmewing/uckp-gen2/main/reinstall.sh
# $bash reinstall.sh

trap ctrl_c INT
trap cleanup EXIT
function cleanup {
	rm -f upgrade.list
}
function ctrl_c() {
	rm -f upgrade.list
	ubnt-systool reset2defaults
}
lsb_release -a
tar -zcvf ~/sources.tgz /etc/apt/sources.list.d/
rm -rfv /etc/apt/sources.list.d/*

# select NO here
dpkg-reconfigure dash

cat << EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ stretch main contrib non-free
deb http://deb.debian.org/debian/ stretch-updates main contrib non-free
deb http://deb.debian.org/debian/ stretch-backports main
deb http://security.debian.org/ stretch/updates main contrib non-free
EOF
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32 871920D1991BC93C 648ACFD622F3D138
apt update
apt -y purge mongodb-clients  mongodb-server  mongodb-server-core  postgresql  postgresql-9.6  postgresql-client  postgresql-common  postgresql-contrib  postgresql-contrib-9.6  ubnt-archive-keyring  ubnt-certgen  ubnt-postgresql-setup  ubnt-unifi-setup  unifi  unifi-management-portal  unifi-protect  unifi-protect-setup

cat << EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports xenial main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports xenial-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports xenial-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports xenial-security main restricted universe multiverse
EOF
apt update
apt -y upgrade
apt -y full-upgrade
apt autoremove
lsb_release -a

cat << EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports bionic main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports bionic-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports bionic-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports bionic-security main restricted universe multiverse
EOF

apt update
apt -y upgrade
apt -y full-upgrade
apt autoremove
cat << EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports focal main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports focal-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports focal-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports focal-security main restricted universe multiverse
EOF

lsb_release -a
apt update
apt list --upgradable | egrep focal | cut -d"/" -f1 | egrep -v "^lib"> upgrade.list; for file in `cat upgrade.list`; do echo -en "\n Installing $file \n" $file;apt -y install $file;done
apt -y upgrade
apt -y full-upgrade
apt -y autoremove

# This area will halfway break the system.  It cant use usrmerge, cant redo the /bin dir.  apt update shows the system
# is up2date, but any attempts to install additional software, you get complaints from apt.
# I will try it again without using the update manager
# Added to upgrade to 22.04

# apt install update-manager-core
# do-release-upgrade -d
