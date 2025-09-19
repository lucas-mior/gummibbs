#!/bin/bash
# shellcheck disable=SC2012

if [ -z "$1" ]; then
    error.sh "$0" "usage: $(basename "$0") <kind of snapshot>"
    exit 1
fi

set -x

kind="$1"
snapshots=".snapshots"

dir="/$snapshots/$kind"

case $kind in
    "manual") max_of_kind=12 ;;
    "boot")   max_of_kind=4  ;;
    "hour")   max_of_kind=8  ;;
    "day")    max_of_kind=8  ;;
    "week")   max_of_kind=8  ;;
    "month")  max_of_kind=12 ;;
    *) error "$0" "kind of snapshot: {manual, boot, hour, day, week, month}"; exit 1 ;;
esac

mkdir -p "$dir"
mkdir -p "/home/$dir"

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

while [ "$(ls -- "/home/$dir" | wc -l)" -gt "$max_of_kind" ]; do
    oldest="$(ls -- "/home/$dir" | sort | head -n 1)"
    btrfs subvol delete "/home/$dir/$oldest"
done

date="$(date +"%Y%m%d_%H%M%S")"
btrfs subvolume snapshot /     "/$snapshots/$kind/$date"
btrfs subvolume snapshot /home "/home/$snapshots/$kind/$date"
