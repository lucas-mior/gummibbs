#!/bin/bash

# shellcheck disable=SC2012

if [ -z "$1" ]; then
    echo "usage: $(basename "$0") <kind of snapshot>"
    exit 1
fi

kind="$1"
snapshots=".snapshots"

dir="/$snapshots/$kind"

if btrfs subvol show / | head -n 1 | grep -q -- "$snapshots"; then
    echo "$(basename "$0"):" "Snapshot mounted. Exiting..."
    exit 1
fi

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

mkdir -p "$dir"
mkdir -p "/home/$dir"

root_subvol="$(btrfs subvol show /     2>/dev/null | awk '/Name:/ {print $NF}')"
home_subvol="$(btrfs subvol show /home 2>/dev/null | awk '/Name:/ {print $NF}')"

if [ "$root_subvol" = "$home_subvol" ]; then
    echo "Warning: / and /home are the same subvolume."
    echo "Skipping /home snapshot and cleanup."
    take_home_snapshot=false
else
    take_home_snapshot=true
fi

while [ "$(ls -- "$dir" | wc -l)" -gt "$max_of_kind" ]; do
    oldest="$(ls -- "$dir" | sort | head -n 1)"
    btrfs subvol delete "$dir/$oldest"
    entry="/boot/loader/entries/$oldest.conf"

    linux_used="$(awk  '/^linux/  {print $NF}' "$entry")"
    initrd_used="$(awk '/^initrd/ {print $NF}' "$entry")"

    if [ -n "$linux_used" ]; then
        grep -FR -- "$linux_used" /boot/loader/entries/ \
            || rm -f "/boot/$linux_used"
    fi
    if [ -n "$initrd_used" ]; then
        grep -FR -- "$initrd_used" /boot/loader/entries/ \
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
