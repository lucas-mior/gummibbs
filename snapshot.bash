#!/bin/bash

# shellcheck disable=SC2012

shopt -s nullglob

error () {
    >&2 printf "$@"
    return
}

if [ -z "$1" ]; then
    error "usage: $(basename "$0") <kind of snapshot>\n"
    exit 1
fi

kind="$1"
snapshots=".snapshots"
lock="/var/lib/pacman/db.lck"

dir="/$snapshots/$kind"

if ! btrfs_subvol_show_root=$(btrfs subvol show /); then
    error "Error running btrfs subvol show /."
    error "Are your using btrfs?"
    exit 2
fi

if ! btrfs_subvol_show_home=$(btrfs subvol show /home 2>&1); then
    error "Error running btrfs subvol show /home:\n"
    error "$btrfs_subvol_show_home"
    take_home_snapshot=false
else
    mkdir -p "/home/$dir"
    take_home_snapshot=true
fi

mkdir -p "$dir"

if echo "$btrfs_subvol_show_root" | head -n 1 | grep -Eq -- "$snapshots"; then
    error "Snapshot mounted. Exiting...\n"
    exit 1
fi

if [ -e "$lock" ]; then
    error "$lock exists. You can't run this script while pacman is running.\n"
    exit 1
fi

cleanup() {
    rm -v "$lock"
}
touch "$lock"
trap cleanup EXIT

case $kind in
    "manual") max_of_kind=12 ;;
    "boot")   max_of_kind=4  ;;
    "hour")   max_of_kind=8  ;;
    "day")    max_of_kind=8  ;;
    "week")   max_of_kind=8  ;;
    "month")  max_of_kind=12 ;;
    *) printf "$0:"
       printf " kind of snapshot: {manual, boot, hour, day, week, month}"
       exit 1 ;;
esac

while [ "$(ls -- "$dir" | wc -l)" -gt "$max_of_kind" ]; do
    oldest="$(ls -- "$dir" | sort | head -n 1)"
    btrfs subvol delete "$dir/$oldest"
    entry="/boot/loader/entries/$oldest.conf"

    linux_used="$(awk  '/^linux/  {print $NF}' "$entry")"
    initrd_used="$(awk '/^initrd/ {print $NF}' "$entry")"

    if [ -n "$linux_used" ]; then
        grep -FRq -- "$linux_used" /boot/loader/entries/ \
            || rm -f "/boot/$linux_used"
    fi
    if [ -n "$initrd_used" ]; then
        grep -FRq -- "$initrd_used" /boot/loader/entries/ \
            || rm -f "/boot/$initrd_used"
    fi

    rm -f "$entry"
done

if [ "$take_home_snapshot" = true ]; then
    while [ "$(ls -- "/home/$dir" | wc -l)" -gt "$max_of_kind" ]; do
        oldest="$(ls -- "/home/$dir" | sort | head -n 1)"
        btrfs subvol delete "/home/$dir/$oldest"
    done
fi

date="$(date +"%Y%m%d_%H%M%S")"

btrfs subvolume snapshot / "$dir/$date"
if [ "$take_home_snapshot" = true ]; then
    btrfs subvolume snapshot /home "/home/$snapshots/$kind/$date"
fi
