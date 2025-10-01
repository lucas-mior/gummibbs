#!/bin/bash

# shellcheck disable=SC2001
# shellcheck source=./systemd-boot-btrfsd-common.bash
common="systemd-boot-btrfsd-common.bash"
if ! source ./$common; then
    if ! source /lib/$common; then
        >&2 printf "Error sourcing $common.\n"
        exit
    fi
fi

script=$(basename "$0")
set -E
fatal_error=2
trap 'test "$?" = "$fatal_error" && exit $fatal_error' ERR

if [[ $subvol =~ ([|/&\\$\(\)*+[]|]) ]]; then
    error "Subvolume name contains invalid chars: $subvol \n"
    exit 1
fi

template=$(bootctl | awk '/Current Entry:/ {print $NF}')
if ! test -e "/boot/loader/entries/$template"; then
    error "Template boot entry '$template' does not exist.\n"
    exit 1
fi

template2=$(awk '/default/ {print $NF}' "/boot/loader/loader.conf")
if test "$template2" != "$template"; then
    error "Default boot option ($template2)"
    error " is not the booted one ($template).\n"
    exit 1
fi

initramfs=$(awk '/^initrd .+(mkinitcpio|booster|dracut)/{print $NF}' \
                "/boot/loader/entries/$template")
if test -z "$initramfs"; then
    error "You must set the initramfs.img prefix"
    error " as the name of the initramfs generator to keep track of it.\n"
    exit 1
fi
initramfs2=$(sed -nE \
                 -e '/initrd/{
                         s/initrd=(.+(initramfs|mkinitcpio|booster|dracut).+\.img).+/\1/;
                         s|\\|/|;
                         p;
                     }' /proc/cmdline)

if [[ "$initramfs" != "$initramfs2" ]]; then
    error "Initramfs specified in boot entry ($initramfs)"
    error "does not match the one in /proc/cmdline ($initramfs2)\n"
    exit 1
fi

subvol2=$(sed -En '/rootflags/{s/.*subvol=([^ ,;]*).*/\1/p}' \
                  "/boot/loader/entries/$template")

if test "$subvol" != "$subvol2"; then
    error "Root subvolume ($subvol)"
    error " is not the one specified in $template ($subvol2).\n"
    exit 1
fi

error "Deleting boot entries with inexistent snapshots or kernels or initrds.\n"
for entry in /boot/loader/entries/*.conf; do
    snap=$(echo "$entry" \
           | sed -E -e 's|/boot/loader/entries/||' \
                    -e 's|.conf||')
    if [[ ! "$snap" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        error "Ignoring entry $entry...\n"
        continue
    fi

    match=$(find "/$snapshots/" -maxdepth 2 -name "$snap" | wc -l)
    if test "$match" = "0"; then
        error "$snap not found\n"
        rm -v "$entry"
        continue
    fi

    linux=$(awk '/^linux/{printf("%s/%s\n", "/boot", $NF);}' "$entry")
    if ! test -e "$linux"; then
        error "Referenced kernel $linux no longer exists. Deleting entry...\n"
        rm -v "$entry"
        continue
    fi

    initrds=$(awk '/^initrd/{printf("%s/%s\n", "/boot", $NF);}' "$entry")
    for initrd in $initrds; do
        if ! test -e "$initrd"; then
            error "Referenced initrd $initrd does not exist."
            error " Deleting entry...\n"
            rm -v "$entry"
            continue
        fi
    done
done

cleanup() {
    grep -F "$snapshots" /proc/mounts \
        | while read -r fs; do
        fuser -vk "$fs"
        umount -v "$fs"
    done

    rm -vrf "/tmp/$script/"
}

savefrom() {
    current=$1
    base=$(basename "$current" | sed -E 's/\..+//')
    ext=$(basename "$current" | sed -E 's/[^.]+(\..+)?/\1/')

    if test -z "$snapdate"; then
        error "\$snapdate must be set.\n"
        exit 1
    fi

    if ! test -s "$current"; then
        error "$current is empty.\n"
        return 0
    fi

    for file in /boot/"$base"-*; do
        if ! test -e "$file"; then
            continue
        fi
        if diff "$file" "$current" >/dev/null 2>&1; then
            printf "$file\n"
            return 0
        fi
    done

    conf="${base}-${snapdate}${ext}"
    cp -f "$current" "/boot/$conf" >/dev/null \
        && printf "/boot/$conf\n"
}

get_kernel_type () {
    if [[ $1 =~ "-lts$" ]]; then
        kernel_type="linux-lts"
    elif [[ $1 =~ "-hardened$" ]]; then
        kernel_type="linux-hardened"
    elif [[ $1 =~ "-zen$" ]]; then
        kernel_type="linux-zen"
    elif [[ $1 =~ "-arch" ]]; then
        kernel_type="linux"
    else
        error "Unknown kernel type $1.\n"
        exit $fatal_error
    fi
    echo "$kernel_type"
}

error "Generating boot entries for existing snapshots...\n"
find "/$snapshots" -mindepth 2 -maxdepth 2 \
| while read -r snapshot; do
    snapshot=$(echo "$snapshot" | sed -E 's|//|/|; s|/$||;')
    snap=$(echo "$snapshot" | awk -F'/' '{print $NF}')
    kind=$(echo "$snapshot" | awk -F'/' '{print $(NF-1)}')
    entry="/boot/loader/entries/$snap.conf"

    if ! is_valid "$kind"; then
        error "Invalid kind: $kind\n"
        error "Valid kinds are: {${valid_kinds[*]}}\n"
        exit "$fatal_error"
    fi

    if test -e "$entry"; then
        error "$entry already exists.\n"
        continue
    fi

    kernel=$(find "$snapshot/lib/modules" \
             -mindepth 2 -maxdepth 2 \
             -iname "vmlinuz" \
             -type f -printf '%T@ %p\n' \
             | sort -nr | head -n1 \
             | awk -F/ '{print $(NF-1)}')
    kernel_type=$(get_kernel_type "$kernel")

    rm -rf "/tmp/$script"
    mkdir -p "/tmp/$script"
    if ! cp -v "$snapshot/lib/modules/$kernel/vmlinuz" \
               "/tmp/$script/vmlinuz-$kernel_type"; then
        error "Error getting kernel from snapshot.\n"
        continue
    fi

    snapdate=$snap
    linux=$(savefrom "/tmp/$script/vmlinuz-$kernel_type" | sed 's|/boot/||')
    if test -z "$linux"; then
        error "Error creating configuration for snapshotted kernel.\n"
        continue
    fi

    if grep -q "\b$snapshot\b" /proc/mounts; then
        error "Snapshot $snapshot is mounted. This should not be the case.\n"
        exit 2
    fi
    if grep -q "\b$snapshot/mnt/\b" /proc/mounts; then
        error "Snapshot $snapshot is mounted. This should not be the case.\n"
        exit 2
    fi

    mount -v --bind "$snapshot" "$snapshot"
    mount -v --bind "/tmp/" "$snapshot/mnt/" --mkdir

    set -x
    if ! arch-chroot "$snapshot" \
        mkinitcpio \
        -k "/mnt/$script/vmlinuz-$kernel_type" \
        -g "/mnt/$script/mkinitcpio-$kernel_type.img"; then
        set +x
        error "\nError generating initramfs using mkinitcpio.\n\n"
    fi
    set -x
    if ! arch-chroot "$snapshot" \
        booster build \
        --kernel-version "$kernel" \
        "/mnt/$script/booster-$kernel_type.img"; then
        set +x
        error "\nError generating initramfs using booster.\n\n"
    fi
    set -x
    if ! arch-chroot "$snapshot" \
        dracut \
        --kver "$kernel" \
        "/mnt/$script/dracut-$kernel_type.img"; then
        set +x
        error "\nError generating initramfs using dracut.\n\n"
    fi
    set +x

    umount -v "$snapshot/mnt"
    umount -v "$snapshot"

    mkinitcpio=$(savefrom "/tmp/$script/mkinitcpio-$kernel_type.img")
    booster=$(savefrom    "/tmp/$script/booster-$kernel_type.img")
    dracut=$(savefrom     "/tmp/$script/dracut-$kernel_type.img")

    mkinitcpio=$(echo "$mkinitcpio" | sed 's|/boot/||')
    booster=$(echo    "$booster"    | sed 's|/boot/||')
    dracut=$(echo     "$dracut"     | sed 's|/boot/||')

    if test -z "$mkinitcpio" && test -z "$booster" && test -z "$dracut"; then
        error "\nError creating initramfs for $snapdate.\n\n"
        continue
    fi

    if test -n "$mkinitcpio" \
        && { test -n "$booster" || test -n "$dracut"; }; then
        error "Warning: Snapshot has more than one initramfs generator.\n"
        error "Defaulting to mkinitcpio...\n"
    elif test -n "$booster" \
        && { test -n "$mkinitcpio" || test -n "$dracut"; }; then
        error "Warning: Snapshot has more than one initramfs generator.\n"
        error "Defaulting to booster...\n"
    elif test -n "$dracut" \
        && { test -n "$mkinitcpio" || test -n "$booster"; }; then
        error "Warning: Snapshot has more than one initramfs generator.\n"
        error "Defaulting to dracut...\n"
    fi

    if test -n "$mkinitcpio"; then
        initramfs="$mkinitcpio"
    elif test -n "$booster"; then
        initramfs="$booster"
    elif test -n "$dracut"; then
        initramfs="$dracut"
    fi

    sed -E \
        -e "s|^title .+|title $kind/$snap|" \
        -e "s|subvol=$subvol|subvol=$subvol/.snapshots/$kind/$snap|" \
        -e "s|^linux .+/vmlinuz-linux.*|linux /$linux|" \
        -e "s|^initrd .+/(mkinitcpio|booster|dracut)|initrd /$initramfs|" \
        -e "s|//+|/|g" \
        "/boot/loader/entries/$template" \
        | tee "$entry"
done

unset kind snap snapshot linux mkinitcpio booster dracut

while true; do
snap=$(inotifywait \
       --format "%w %f%n" \
       -e create "/$snapshots/"{manual,boot,hour,day,week,month})
if test $? != 0 || test -z "$snap"; then
    error "Error in inotifywait.\n"
    exit 1
fi
snap=$(echo "$snap" | sed -E "s|$snapshots||; s|/||g")

IFS=" " read -r kind snapdate <<END
$snap
END

if ! is_valid "$kind"; then
    error "Invalid kind: $kind\n"
    error "Valid kinds are: {${valid_kinds[*]}}\n"
    exit "$fatal_error"
fi

sleep 2
n=0
while test -e "$lock"; do
    error "$lock exists. Trying again in 5 seconds..."
    sleep 5
    n=$((n+1))
    if test $n -gt 12; then
        error "Timeout waiting for $lock. Continuing..."
        continue
    fi
done

trap cleanup EXIT
touch "$lock"

kernel_type=$(get_kernel_type "$(uname -r)")

linux=$(savefrom      "/boot/vmlinuz-$kernel_type")
mkinitcpio=$(savefrom "/boot/mkinitcpio-$kernel_type.img")
booster=$(savefrom    "/boot/booster-$kernel_type.img")
dracut=$(savefrom     "/boot/dracut-$kernel_type.img")

if test -z "$mkinitcpio" && test -z "$booster"; then
    error "Error creating configuration for initramfs.\n"
    exit $fatal_error
fi

if test -z "$linux"; then
    error "Error creating configuration for kernel.\n"
    exit $fatal_error
fi

linux=$(echo "$linux"           | sed 's|/boot/||')
mkinitcpio=$(echo "$mkinitcpio" | sed 's|/boot/||')
booster=$(echo "$booster"       | sed 's|/boot/||')
dracut=$(echo "$dracut"         | sed 's|/boot/||')

kind="$(echo "$kind" | sed 's|/||g')"

sed -E \
    -e "s|^title .+|title   $kind/$snapdate|;" \
    -e "s|subvol=$subvol|subvol=$subvol/$snapshots/$kind/$snapdate|" \
    -e "s|^linux .+/vmlinuz-linux.*|linux /$linux|" \
    -e "s|^initrd .+/mkinitcpio-linux.*\.img$|initrd /$mkinitcpio|" \
    -e "s|^initrd .+/booster-linux.*\.img$|initrd /$booster|" \
    -e "s|^initrd .+/dracut-linux.*\.img$|initrd /$dracut|" \
    -e "s|//+|/|g" \
    "/boot/loader/entries/$template" \
    | tee "/boot/loader/entries/$snapdate.conf"

rm -v "$lock"
done
