#!/bin/bash
# shellcheck disable=SC2034

export LC_ALL=C
shopt -s nullglob

error () {
    >&2 printf "$@"
    return
}

valid_kinds=(manual boot hour day week month)
is_valid () {
    for valid_kind in "${valid_kinds[@]}"; do
        if [[ "$valid_kind" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

config="/etc/systemd-boot-btrfsd.conf"
snapshots="/.snapshots/"
lock="/var/lib/pacman/db.lck"

if [[ ! -f /etc/os-release ]] || ! grep -q '^ID=arch' /etc/os-release; then
    error "Not running Arch Linux. Exiting...\n"
    exit 1
fi

if ! bootctl status >/dev/null 2>&1; then
    error "Not using systemd-boot. Exiting...\n"
    exit 1
fi

if test -n "$(find /boot/ -maxdepth 1 -iname "*.efi" -print -quit)"; then
    error "Unified kernel images detected in /boot. Exiting...\n"
    exit 1
fi

fs=$(awk '$2 == "/boot" {print $3}' /proc/mounts)
if [[ "$fs" != "vfat" ]]; then
    error "Error: /boot must be a vfat partition.\n"
    exit 2
fi

if ! ls /sys/firmware/efi; then
    error "/sys/firmware/efi directory not found.\n"
    error "Are you using UEFI?\n"
    exit 2
fi

if [ "$0" = "$BASH_SOURCE" ]; then
    exit 0
fi

if ! btrfs_subvol_show_root=$(btrfs subvol show /); then
    error "Error running btrfs subvol show /."
    error "Are your using btrfs?\n"
    exit 2
fi

subvol_root=$(echo "$btrfs_subvol_show_root" | head -n 1)
if [[ $subvol_root =~ $snapshots ]]; then
    error "Snapshot mounted as root. Exiting...\n"
    exit 1
fi

subvol=$(btrfs subvol show / | awk '/Name:/{print $NF}')
if [[ $subvol =~ ^[0-9]{8}_[0-9]{6} ]]; then
    error "Subvolume name matches date format. Exiting...\n"
    exit 1
fi
