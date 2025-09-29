#!/bin/bash

# shellcheck disable=SC2001,SC2181

printf "\n$0\n\n"
script=$(basename "$0")

error () {
    >&2 printf "$@"
}

set -E
fatal_error=2
trap '[ "$?" = "$fatal_error" ] && exit $fatal_error' ERR

export LC_ALL=C
snapshots="/.snapshots/"

if btrfs subvol show / | head -n 1 | grep -Eq -- "$snapshots"; then
    error "Snapshot mounted. Exiting...\n"
    exit 1
fi

subvol=$(btrfs subvol show / | awk '/Name:/{print $NF}')
if echo "$subvol" | grep -Eq "^[0-9]{8}_[0-9]{6}"; then
    error "Subvolume name matches date format. Exiting...\n"
    exit 1
fi

if echo "$subvol" | grep -Eq '([|/&\\$\(\)*+[]|])'; then
    error "Subvolume name contains invalid chars: $subvol \n"
    exit 1
fi

template=$(bootctl | awk '/Current Entry:/ {print $NF}')
if [ ! -e "/boot/loader/entries/$template" ]; then
    error "Template boot entry '$template' does not exist.\n"
    exit 1
fi

template2=$(awk '/default/ {print $NF}' "/boot/loader/loader.conf")
if [ "$template2" != "$template" ]; then
    error "Default boot option ($template2)"
    error " is not the booted one ($template).\n"
    exit 1
fi

subvol2=$(sed -En '/rootflags/{s/.*subvol=([^ ,;]*).*/\1/p}' \
                  "/boot/loader/entries/$template")

if [ "$subvol" != "$subvol2" ]; then
    error "Root subvolume ($subvol)"
    error " is not the one specified in $template ($subvol2).\n"
    exit 1
fi

error "Deleting boot entries with inexistent snapshots or kernels or initrds.\n"
for entry in /boot/loader/entries/*.conf; do
    snap=$(echo "$entry" \
            | sed -E -e 's|/boot/loader/entries/||' \
                     -e 's|.conf||')
    if echo "$snap" | grep -Eqv "^[0-9]{8}_[0-9]{6}"; then
        error "Ignoring entry $entry...\n"
        continue
    fi

    match=$(find "/$snapshots/" -maxdepth 2 -name "$snap" | wc -l)
    if [ "$match" = "0" ]; then
        error "$snap not found\n"
        rm -v "$entry"
        continue
    fi

    linux=$(awk '/^linux/{printf("%s/%s\n", "/boot", $NF);}' "$entry")
    if [ ! -e "$linux" ]; then
        error "Referenced kernel $linux no longer exists. Deleting entry...\n"
        rm -v "$entry"
        continue
    fi

    initrds=$(awk '/^initrd/{printf("%s/%s\n", "/boot", $NF);}' "$entry")
    for initrd in $initrds; do
        if [ ! -e "$initrd" ]; then
            error "Referenced initrd $initrd does not exist."
            error " Deleting entry...\n"
            rm -v "$entry"
            continue
        fi
    done
done

lock="/var/lib/pacman/db.lck"
cleanup() {
    rm -v "$lock"
    rm -vrf "/tmp/$script/"
}

savefrom() {
    dir=$1
    current=$2
    base=$(echo "$current" | sed -E 's/\..+//')
    ext=$(echo "$current" | sed -E 's/[^.]+(\..+)?/\1/')

    if [ -z "$snapdate" ]; then
        error "\$snapdate must be set.\n"
        exit 1
    fi

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

error "Generating boot entries for existing snapshots...\n"
find /.snapshots/ -mindepth 2 -maxdepth 2 \
| while read -r snapshot; do
    snap=$(echo "$snapshot" | awk -F'/' '{print $NF}')
    kind=$(echo "$snapshot" | awk -F'/' '{print $(NF-1)}')
    entry="/boot/loader/entries/$snap.conf"

    if [ -e "$entry" ]; then
        error "$entry already exists.\n"
        continue
    fi

    kernel=$(find "$snapshot/usr/lib/modules" \
             -mindepth 1 -maxdepth 1 \
             -type d -printf '%T@ %P\n' \
             | sort -nr | head -n1 \
             | cut -d' ' -f2)
    if echo "$kernel" | grep -Eq -- "-lts$"; then
        kernel_type="linux-lts"
    elif echo "$kernel" | grep -Eq -- "-hardened$"; then
        kernel_type="linux-hardened"
    elif echo "$kernel" | grep -Eq -- "-zen$"; then
        kernel_type="linux-zen"
    elif echo "$kernel" | grep -Eq -- "-arch"; then
        kernel_type="linux"
    else
        error "Unknown kernel type $kernel.\n"
        exit 2
    fi

    mkdir -p "/tmp/$script"
    cp -v "$snapshot/usr/lib/modules/$kernel/vmlinuz" \
          "/tmp/$script/vmlinuz-$kernel_type"

    set -x
    if ! "$snapshot/usr/bin/mkinitcpio" \
        --config "$snapshot/etc/mkinitcpio.conf" \
        -r "$snapshot" \
        --kernel "$kernel" \
        --generate "/tmp/$script/initramfs-$kernel_type.img"; then
        set +x
        error "Error generating initramfs using snapshotted mkinitcpio.\n"
    fi
    if ! "$snapshot/usr/bin/booster" \
        -c "$snapshot/etc/booster.yaml" \
        -p "$snapshot/usr/lib/modules/$kernel" \
        -o "/tmp/$script/initramfs-$kernel_type.img"; then
        set +x
        error "Error generating initramfs using snapshotted booster.\n"
    fi
    set +x

    snapdate=$snap
    linux=$(savefrom             "/tmp/$script" "vmlinuz-$kernel_type")
    initrd_mkinitcpio=$(savefrom "/tmp/$script" "initramfs-$kernel_type.img")
    initrd_booster=$(savefrom    "/tmp/$script" "booster-$kernel_type.img")

    if [ -z "$initrd_mkinitcpio" ] && [ -z "$initrd_booster" ]; then
        error "Error generating initramfs:"
        error " both mkinitcpio and booster failed.\n"
        exit $fatal_error
    fi

    linux=$(echo "$linux"                         | sed 's|/boot/||')
    initrd_mkinitcpio=$(echo "$initrd_mkinitcpio" | sed 's|/boot/||')
    initrd_booster=$(echo "$initrd_booster"       | sed 's|/boot/||')

    if [ -z "$linux" ]; then
        error "Error creating configuration for snapshotted kernel.\n"
        exit $fatal_error
    fi

    sed -E -e "s|^title .+|title $kind/$snap|" \
           -e "s|subvol=$subvol|subvol=$subvol/.snapshots/$kind/$snap|" \
           -e "s|^linux .+/vmlinuz-linux.*|linux /$linux|" \
           -e "s|^initrd .+/initramfs-.*\.img$|initrd /$initrd_mkinitcpio|" \
           -e "s|^initrd .+/booster-.*\.img$|initrd /$initrd_booster|" \
           -e "s|//+|/|g" \
        "/boot/loader/entries/$template" \
        | tee "$entry"

done

unset kind snap snapshot linux initrd_mkinitcpio initrd_booster

while true; do
snap=$(inotifywait -e create "/$snapshots/"{manual,boot,hour,day,week,month})
if [ $? != 0 ] || [ -z "$snap" ]; then
    error "Error in inotifywait.\n"
    exit 1
fi
snap=$(echo "$snap" \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')

IFS="," read -r kind snapdate <<END
$snap
END

sleep 2
n=0
while [ -e "$lock" ]; do
    error "$lock exists. Trying again in 5 seconds..."
    sleep 5
    n=$((n+1))
    if [ $n -gt 12 ]; then
        error "Timeout waiting for $lock. Exiting..."
        exit 2
    fi
done

trap cleanup EXIT
touch "$lock"

kernel=$(uname -r)
if echo "$kernel" | grep -Eq -- "-lts$"; then
    kernel_type="linux-lts"
elif echo "$kernel" | grep -Eq -- "-hardened$"; then
    kernel_type="linux-hardened"
elif echo "$kernel" | grep -Eq -- "-zen$"; then
    kernel_type="linux-zen"
elif echo "$kernel" | grep -Eq -- "-arch"; then
    kernel_type="linux"
else
    error "Unknown kernel type $kernel.\n"
    exit 2
fi

linux=$(savefrom             /boot "vmlinuz-$kernel_type")
initrd_mkinitcpio=$(savefrom /boot "initramfs-$kernel_type.img")
initrd_booster=$(savefrom    /boot "booster-$kernel_type.img")

if [ -z "$initrd_mkinitcpio" ] && [ -z "$initrd_booster" ]; then
    error "Error creating configuration for initramfs.\n"
    exit $fatal_error
fi

if [ -z "$linux" ]; then
    error "Error creating configuration for kernel.\n"
    exit $fatal_error
fi

linux=$(echo "$linux"                         | sed 's|/boot/||')
initrd_mkinitcpio=$(echo "$initrd_mkinitcpio" | sed 's|/boot/||')
initrd_booster=$(echo "$initrd_booster"       | sed 's|/boot/||')

kind="$(echo "$kind" | sed 's|/||g')"

sed -E \
    -e "s|^title .+|title   $kind/$snapdate|;" \
    -e "s|subvol=$subvol|subvol=$subvol/$snapshots/$kind/$snapdate|" \
    -e "s|^linux .+/vmlinuz-linux.*|linux /$linux|" \
    -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_mkinitcpio|" \
    -e "s|^initrd .+/booster-linux.*\.img$|initrd /$initrd_booster|" \
    -e "s|//+|/|g" \
    "/boot/loader/entries/$template" \
    | tee "/boot/loader/entries/$snapdate.conf"

rm -v "$lock"
done
