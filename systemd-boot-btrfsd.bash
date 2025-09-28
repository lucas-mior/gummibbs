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

find /.snapshots/ -mindepth 2 -maxdepth 2 \
| while read -r snapshot; do
    snap=$(echo "$snapshot" | awk -F'/' '{print $NF}')
    kind=$(echo "$snapshot" | awk -F'/' '{print $(NF-1)}')
    echo "getkernel $kind/$snap"

    # kernel="$(
    # if ls -1 "$snapshot/usr/lib/modules" | grep -q -- "-arch"; then
#         kernel="$(ls -1 "$snapshot/usr/lib/modules" | grep -- "-arch")"
#         name="$(echo "$kernel" | sed 's/-arch/.arch/')"
#         down="linux-$name-x86_64.pkg.tar.zst"
#         down2="linux-$name-x86_64.pkg.tar.xz"
#         url="https://archive.archlinux.org/packages/l/linux"
#         echo "down=$down"

#         pacman -U "$url/$down" --noconfirm --needed \
#             || pacman -U "$url/$down2" --noconfirm --needed \
#             || continue

#         linux_conf="$(savefromboot "vmlinuz-linux" | sed 's|/boot/||')"
#         initrd_conf="$(savefromboot "initramfs-linux.img" | sed 's|/boot/||')"

#         if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
#             echo "Error creating configuration for kernel and initrd"
#             continue
#         fi

#         entry="/boot/loader/entries/$snap.conf"
#         sed -E -e "s|^title .+|title $kind/$snap|" \
#                -e "s|subvol=@|subvol=@/.snapshots/$kind/$snap|" \
#                -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
#                -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf|" \
#                -e "s|//+|/|g" \
#             "/boot/loader/entries/$template" \
#             | tee "$entry"
#     else
#         echo "$snap has no kernel"
#     fi
done

# pacman -S linux-lts --noconfirm

while true; do
snap="$(inotifywait -e create \
        "/$snapshots/"{manual,boot,hour,day,week,month} \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind snapdate <<END
$snap
END

lock="/var/lib/pacman/db.lck"
while [ -e "$lock" ]; do
    echo "$lock exists. You can't run this script while pacman is running."
    sleep 10
done

cleanup() {
    rm -v "$lock"
}
touch "$lock"
trap cleanup EXIT

kernel="$(uname -r)"
if echo "$kernel" | grep -q -- "-lts$"; then
    kernel="linux-lts"
elif echo "$kernel" | grep -q -- "-hardened$"; then
    kernel="linux-hardened"
elif echo "$kernel" | grep -q -- "-zen$"; then
    kernel="linux-zen"
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
