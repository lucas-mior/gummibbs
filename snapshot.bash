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
    rm "/boot/loader/entries/$oldest.conf"
    rm "/boot/vmlinuz-linux-$oldest"
    rm "/boot/vmlinuz-linux-lts-$oldest"
    rm "/boot/initramfs-linux-$oldest.img"
    rm "/boot/initramfs-linux-lts-$oldest.img"
done

while [ "$(ls -- "/home/$dir" | wc -l)" -gt "$max_of_kind" ]; do
    oldest="$(ls -- "/home/$dir" | sort | head -n 1)"
    btrfs subvol delete "/home/$dir/$oldest"
done

date="$(date +"%Y%m%d_%H%M%S")"
btrfs subvolume snapshot /     "/$snapshots/$kind/$date"
btrfs subvolume snapshot /home "/home/$snapshots/$kind/$date"
