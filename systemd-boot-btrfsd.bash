#!/bin/bash

# shellcheck disable=SC2317,SC2001
printf "\n$0\n\n"

error () {
    script="$(basename "$0")"
    message="$1"
    >&2 echo "${script}: $message"
}

export LC_ALL=C
snapshots="/.snapshots/"

if btrfs subvol show / | head -n 1 | grep -q -- "$snapshots"; then
    error "Snapshot mounted. Exiting..."
    exit 1
fi

template="$(bootctl | awk '/Current Entry:/ {print $NF}')"
if [ ! -e "/boot/loader/entries/$template" ]; then
    error "template boot entry '$template' does not exist"
    exit 1
fi

template2="$(awk '/default/ {print $NF}' "/boot/loader/loader.conf")"
if [ "$template2" != "$template" ]; then
    error "Default boot option ($template2) is not the booted one ($template)"
    exit 1
fi

error "Deleting boot entries with inexistent snapshots or kernels or initrds"
for entry in /boot/loader/entries/*.conf; do
    snap="$(echo "$entry" \
            | sed -E -e 's|/boot/loader/entries/||' \
                     -e 's|.conf||')"
    if echo "$snap" | grep -qv "^[0-9]\{8\}_[0-9]\{6\}"; then
        continue
    fi

    match="$(find "/$snapshots/" -maxdepth 2 -name "$snap" | wc -l)"
    if [ "$match" = "0" ]; then
        error "$snap not found\n"
        rm -v "$entry"
        continue
    fi

    linux="$(awk '/^linux/{printf("%s/%s\n", "/boot", $NF);}' "$entry")"
    if [ ! -e "$linux" ]; then
        error "Referenced kernel $linux no longer exists. Deleting entry..."
        rm -v "$entry"
        continue
    fi

    initrds="$(awk '/^initrd/{printf("%s/%s\n", "/boot", $NF);}' "$entry")"
    for initrd in $initrds; do
        if [ ! -e "$initrd" ]; then
            error "Referenced initrd $initrd no longer exists. Deleting entry..."
            rm -v "$entry"
            continue
        fi
    done
done

lock="/var/lib/pacman/db.lck"
cleanup() {
    rm -v "$lock"
    rm -rf /tmp/boot
}

savefrom() {
    dir="$1"
    current="$2"
    base="$(echo "$current" | sed -E 's/\..+//')"
    ext="$(echo "$current" | sed -E 's/[^.]+(\..+)?/\1/')"

    # shellcheck disable=SC2231
    for file in "$dir"/"$base"-*; do
        if [ ! -e "$file" ]; then
            continue
        fi
        if diff "$file" "/boot/$current" >/dev/null 2>&1; then
            printf "$file\n"
            return 0
        fi
    done

    conf="${base}-${snapdate}${ext}"
    cp -f "$dir/$current" "/boot/$conf" >/dev/null \
        && printf "/boot/$conf\n"
}

error "Generating boot entries for existing snapshots..."
find /.snapshots/ -mindepth 2 -maxdepth 2 \
| while read -r snapshot; do
    snap=$(echo "$snapshot" | awk -F'/' '{print $NF}')
    kind=$(echo "$snapshot" | awk -F'/' '{print $(NF-1)}')
    entry="/boot/loader/entries/$snap.conf"

    if [ -e "$entry" ]; then
        error "$entry already exists."
        continue
    fi

    # shellcheck disable=SC2012
    kernel="$(ls -1t "$snapshot/usr/lib/modules" | head -n 1)"
    if echo "$kernel" | grep -q -- "-lts$"; then
        kernel_type="linux-lts"
    elif echo "$kernel" | grep -q -- "-hardened$"; then
        kernel_type="linux-hardened"
        error "snapshot $snapshot used linux-hardened which is not supported."
        exit 1
    elif echo "$kernel" | grep -q -- "-zen$"; then
        kernel_type="linux-zen"
    elif echo "$kernel" | grep -q -- "-arch"; then
        kernel_type="linux"
    else
        error "Unknown kernel type $kernel"
        exit 1
    fi

    mkdir -p /tmp/boot
    cp -v "$snapshot/usr/lib/modules/$kernel/vmlinuz" \
          "/tmp/boot/vmlinuz-$kernel_type"

    set -x
    if ! "$snapshot/usr/bin/mkinitcpio" \
        --config "$snapshot/etc/mkinitcpio.conf" \
        -r "$snapshot" \
        --kernel "$kernel" \
        --generate "/tmp/boot/initramfs-$kernel_type.img"; then
        error "Error generating initramfs using snapshotted mkinitcpio"
    fi
    if ! "$snapshot/usr/bin/booster" \
        -c "$snapshot/etc/booster.yaml" \
        -p "$snapshot/usr/lib/modules/$kernel" \
        -o "/tmp/boot/initramfs-$kernel_type.img"; then
        error "Error generating initramfs using snapshotted booster"
    fi
    set +x

    linux_conf="$(savefrom             /tmp/boot "vmlinuz-$kernel_type")"
    initrd_conf_mkinitcpio="$(savefrom /tmp/boot "initramfs-$kernel_type.img")"
    initrd_conf_booster="$(savefrom    /tmp/boot "booster-$kernel_type.img")"

    if [ -z "$initrd_conf_mkinitcpio" ] && [ -z "$initrd_conf_booster" ]; then
        error "Error generating initramfs: both mkinitcpio and booster failed."
        exit 1
    fi

    linux_conf="$(echo "$linux_conf" | sed 's|/boot/||')"
    initrd_conf_mkinitcpio="$(echo "$initrd_conf_mkinitcpio" | sed 's|/boot/||')"
    initrd_conf_booster="$(echo "$initrd_conf_booster" | sed 's|/boot/||')"

    if [ -z "$linux_conf" ]; then
        error "Error creating configuration for snapshotted kernel."
        exit 1
    fi

    sed -E -e "s|^title .+|title $kind/$snap|" \
           -e "s|subvol=@|subvol=@/.snapshots/$kind/$snap|" \
           -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
           -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf_mkinitcpio|" \
           -e "s|^initrd .+/booster-linux.*\.img$|initrd /$initrd_conf_booster|" \
           -e "s|//+|/|g" \
        "/boot/loader/entries/$template" \
        | tee "$entry"

done

while true; do
snap="$(inotifywait -e create \
        "/$snapshots/"{manual,boot,hour,day,week,month} \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind snapdate <<END
$snap
END

while [ -e "$lock" ]; do
    error "$lock exists. You can't run this script while pacman is running."
    sleep 10
done

touch "$lock"
trap cleanup EXIT

kernel="$(uname -r)"
if echo "$kernel" | grep -q -- "-lts$"; then
    kernel_type="linux-lts"
elif echo "$kernel" | grep -q -- "-hardened$"; then
    kernel_type="linux-hardened"
    error "linux-hardened not supported"
    exit 1
elif echo "$kernel" | grep -q -- "-zen$"; then
    kernel_type="linux-zen"
else
    kernel_type="linux"
fi

linux_conf="$(savefrom  /boot "vmlinuz-$kernel_type"       | sed 's|/boot/||')"
initrd_conf="$(savefrom /boot "initramfs-$kernel_type.img" | sed 's|/boot/||')"

if [ -z "$initrd_conf" ]; then
    error "Trying to get booster initrd..."
    initrd_conf="$(savefrom /boot "booster-$kernel_type.img" | sed 's|/boot/||')"
fi

if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
    error "Error creating configuration for kernel and initrd"
    continue
fi

# shellcheck disable=SC2001
kind="$(echo "$kind" | sed 's|/||g')"

sed -E \
    -e "s|^title .+|title   $kind/$snapdate|;" \
    -e "s|subvol=@|subvol=@/$snapshots/$kind/$snapdate|" \
    -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
    -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf|" \
    -e "s|^initrd .+/booster-linux.*\.img$|initrd /$initrd_conf|" \
    -e "s|//+|/|g" \
    "/boot/loader/entries/$template" \
    | tee "/boot/loader/entries/$snapdate.conf"
done
