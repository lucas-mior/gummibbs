#!/bin/bash

printf "\n$0\n\n"

export LC_ALL=C
snapshots="/.snapshots/"

if btrfs subvol show / | head -n 1 | grep -q -- "$snapshots"; then
    echo "$(basename "$0"):" "Snapshot mounted. Exiting..."
    exit 1
fi

template="$(bootctl | awk '/Current Entry:/ {print $NF}')"
if [ ! -e "/boot/loader/entries/$template" ]; then
    echo "template boot entry '$template' does not exist"
    exit 1
fi

# delete existing boot entries for missing snapshots
for entry in /boot/loader/entries/*.conf; do
    snap="$(echo "$entry" \
            | sed -E -e 's|/boot/loader/entries/||' \
                     -e 's|.conf||')"
    if echo "$snap" | grep -qv "^[0-9]\{8\}_[0-9]\{6\}"; then
        continue
    fi

    match="$(find "/$snapshots/" -maxdepth 2 -name "$snap" | wc -l)"
    if [ "$match" = "0" ]; then
        printf "$snap not found\n"
        rm -v "$entry"
        continue
    fi

    linux="$(awk '/^linux/{printf("%s/%s\n", "/boot", $NF);}' "$entry")"
    if [ ! -e "$linux" ]; then
        printf "referenced kernel $linux no longer exists."
        rm -v "$entry"
        continue
    fi

    initrds="$(awk '/^initrd/{printf("%s/%s\n", "/boot", $NF);}' "$entry")"
    for initrd in $initrds; do
        if [ ! -e "$initrd" ]; then
            printf "referenced initrd $initrd no longer exists."
            rm -v "$entry"
            continue
        fi
    done
done

# add missing boot entries for existing snapshots
kinds=("manual" "boot" "hour" "day" "week" "month")

for kind in "${kinds[@]}"; do
    # shellcheck disable=SC2010,SC2045
    for snap in $(ls -1 "/$snapshots/$kind/"); do
        snap="$(echo "$snap" | sed -E "s|/$snapshots/$kind/||")"

        entry="/boot/loader/entries/$snap.conf"
        if [ ! -e "$entry" ]; then
            sed -E -e "s|^title .+|title $kind/$snap|" \
                   -e "s|subvol=@|subvol=@/$snapshots/$kind/$snap|" \
                   -e "s|//+|/|g" \
                "/boot/loader/entries/$template" \
                | tee "$entry"
        fi
    done
done

savefromboot() {
    current="$1"
    base="$(echo "$current" | sed -E 's/\..+//')"
    ext="$(echo "$current" | sed -E 's/[^.]+(\..+)?/\1/')"

    # shellcheck disable=SC2231
    for file in /boot/$base-*; do
        [ -e "$file" ] || continue
        if diff "$file" "/boot/$current" >/dev/null 2>&1; then
            printf "$file\n"
            return 0
        fi
    done

    conf="${base}-${snapdate}${ext}"
    cp -f "/boot/$current" "/boot/$conf" >/dev/null \
        && printf "/boot/$conf\n"
}

while true; do
snap="$(inotifywait -e create \
        "/$snapshots/"{manual,boot,hour,day,week,month} \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind snapdate <<END
$snap
END

kernel="$(uname -r)"
if echo "$kernel" | grep -q -- "-lts$"; then
    kernel="linux-lts"
elif echo "$kernel" | grep -q "-hardened$"; then
    kernel="linux-hardened"
else
    kernel="linux"
fi

linux_conf="$(savefromboot  "vmlinuz-$kernel"       | sed 's|/boot/||')"
initrd_conf="$(savefromboot "initramfs-$kernel.img" | sed 's|/boot/||')"

if [ -z "$initrd_conf" ]; then
    echo "Trying to get booster initrd..."
    initrd_conf="$(savefromboot "booster-$kernel.img" | sed 's|/boot/||')"
fi

if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
    echo "Error creating configuration for kernel and initrd"
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
