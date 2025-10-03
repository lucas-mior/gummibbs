#!/bin/bash

# shellcheck source=./systemd-boot-btrfsd-common.bash
common=systemd-boot-btrfsd-common.bash
if ! source /lib/$common; then
    if ! source ./$common; then
        >&2 printf "Error sourcing $common.\n"
        exit
    fi
fi

if [[ -z "$1" ]]; then
    error "usage: $(basename "$0") <kind of snapshot>\n"
    exit 1
fi

kind="$1"

dir="/$snapshots/$kind"

if ! btrfs_subvol_show_home=$(btrfs subvol show /home 2>&1); then
    error "Error running btrfs subvol show /home:\n"
    error "$btrfs_subvol_show_home"
    take_home_snapshot=false
else
    mkdir -p "/home/$dir"
    take_home_snapshot=true
fi

mkdir -p "$dir"

if [ -e "$lock" ]; then
    error "$lock exists. You can't run this script while pacman is running.\n"
    exit 1
fi

cleanup() {
    rm -v "$lock"
}
touch "$lock"
trap cleanup EXIT

if ! is_valid "$kind"; then
    error "Error: Invalid snapshot kind.\n"
    exit 1
fi
max_of_kind=$(awk -F"[ =]+" "/$kind/ {print \$2}" "$config")

get_first () {
    sort -z "$1" | head -z -n 1 | tr -d '\0'
}

get_count () {
    tr -cd '\0' < "$1" | wc -c
}

get_files () {
    find "$1" -mindepth 1 -maxdepth 1 -printf "%f\0"
}

while : ; do
    tmpfile=$(mktemp)
    get_files "$dir" > "$tmpfile"

    if [[ $(get_count "$tmpfile") -le $max_of_kind ]]; then
        rm "$tmpfile"
        break
    fi

    oldest=$(get_first "$tmpfile")
    set -x
    btrfs subvol delete "$dir/$oldest"
    set +x
    rm "$tmpfile"

    entry="/boot/loader/entries/$oldest.conf"

    linux_used=$(awk '/^linux/  {print $NF}' "$entry")
    initrd_used=$(awk '/^initrd/ {print $NF}' "$entry")

    if [ -n "$linux_used" ]; then
        grep -FRq -- "$linux_used" /boot/loader/entries/ \
            || rm -vf "/boot/$linux_used"
    fi
    if [ -n "$initrd_used" ]; then
        grep -FRq -- "$initrd_used" /boot/loader/entries/ \
            || rm -vf "/boot/$initrd_used"
    fi

    rm -vf "$entry"
done

if [ "$take_home_snapshot" = true ]; then
    while : ; do
        tmpfile=$(mktemp)
        get_files "/home/$dir" > "$tmpfile"
        if [[ $(get_count "$tmpfile") -le $max_of_kind ]]; then
            rm "$tmpfile"
            break
        fi
        oldest=$(get_first "$tmpfile")
        set -x
        btrfs subvol delete "/home/$dir/$oldest"
        set +x
        rm "$tmpfile"
    done
fi

snapdate=$(date +"%Y%m%d_%H%M%S")

if already=$(find "/$snapshots" -mindepth 2 -maxdepth 2 -print0 \
             | grep -zF -- "$snapdate"); then
    error "Snapshot for $snapdate already exists in $already.\n"
    exit 1
fi

btrfs subvolume snapshot / "$dir/$snapdate"
if [ "$take_home_snapshot" = true ]; then
    btrfs subvolume snapshot /home "/home/$snapshots/$kind/$snapdate"
fi
