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

template2="$(awk '/default/ {print $NF}' "/boot/loader/loader.conf")"
if [ "$template2" != "$template" ]; then
    echo "Default boot option ($template2) is not the booted one ($template)"
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

    kernel="$(ls -1t "$snapshot/usr/lib/modules" | head -n 1)"
    if echo "$kernel" | grep -q -- "-lts$"; then
        kernel_type="linux-lts"
    elif echo "$kernel" | grep -q -- "-hardened$"; then
        kernel_type="linux-hardened"
        echo "snapshot $snapshot used linux-hardened which is not supported."
        continue
    elif echo "$kernel" | grep -q -- "-zen$"; then
        kernel_type="linux-zen"
    elif echo "$kernel" | grep -q -- "-arch"; then
        kernel_type="linux"
    else
        echo "Unknown kernel type $kernel"
        continue
    fi

    version="$(echo "$kernel" | sed -E 's/-(lts|zen)$//g')"

    case "$kernel_type" in
        "linux")     pkg="linux/linux-$version-x86_64.pkg.tar"         ;;
        "linux-zen") pkg="linux-zen/linux-$version-x86_64.pkg.tar"     ;;
        "linux-lts") pkg="linux-lts/linux-lts-$version-x86_64.pkg.tar" ;;
    esac

    file=""
    for ext in zst xz; do
        url="https://archive.archlinux.org/packages/l/$pkg.$ext"
        echo "url=$url"
        sig="$url.sig"
        wget -q "$url" && wget -q "$sig" \
            && file="$(basename "$pkg").$ext"
    done

    if [ -z "$file" ]; then
        echo "Failed to download package for $kernel"
        continue
    fi

    if ! gpg --verify "$file.sig" "$file"; then
        echo "Signature verification failed for $file"
        rm -f "$file" "$file.sig"
        continue
    fi

    if ! bsdtar -xvf "$file" -C /tmp boot/vmlinuz* boot/initramfs*; then
        echo "Failed to extract $file"
        rm -f "$file"
        continue
    fi

    rm -f "$file"
done
exit

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
exit

# pacman -S linux-lts --noconfirm
lock="/var/lib/pacman/db.lck"
cleanup() {
    rm -v "$lock"
}

while true; do
snap="$(inotifywait -e create \
        "/$snapshots/"{manual,boot,hour,day,week,month} \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind snapdate <<END
$snap
END

while [ -e "$lock" ]; do
    echo "$lock exists. You can't run this script while pacman is running."
    sleep 10
done

touch "$lock"
trap cleanup EXIT

kernel="$(uname -r)"
if echo "$kernel" | grep -q -- "-lts$"; then
    kernel_type="linux-lts"
elif echo "$kernel" | grep -q -- "-hardened$"; then
    kernel_type="linux-hardened"
    echo "$0:" "linux-hardened not supported"
    exit 1
elif echo "$kernel" | grep -q -- "-zen$"; then
    kernel_type="linux-zen"
else
    kernel_type="linux"
fi

linux_conf="$(savefromboot  "vmlinuz-$kernel_type"       | sed 's|/boot/||')"
initrd_conf="$(savefromboot "initramfs-$kernel_type.img" | sed 's|/boot/||')"

if [ -z "$initrd_conf" ]; then
    echo "Trying to get booster initrd..."
    initrd_conf="$(savefromboot "booster-$kernel_type.img" | sed 's|/boot/||')"
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
