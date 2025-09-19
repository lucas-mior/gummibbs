#!/bin/bash

printf "\n$0\n\n"

snapshots="/.snapshots/"
template="arch.conf"

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
        echo "$snap not found"
        rm -v "$entry"
    fi
done

savefromboot() {
    current="$1"
    base="$(echo "$current" | sed -E 's/\..+//')"
    ext="$(echo "$current" | sed -E 's/[^.]+(\..+)?/\1/')"

    for file in /boot/$base-*; do
        [ -e "$file" ] || continue
        if diff "$file" "/boot/$current" >/dev/null 2>&1; then
            echo "$file"
            return 0
        fi
    done

    conf="$base-$date$ext"
    cp -f "/boot/$current" "/boot/$conf" >/dev/null \
        && echo "/boot/$conf"
}

while true; do
snap="$(inotifywait -e create \
        "/$snapshots/"{manual,boot,hour,day,week,month} \
        | awk -v snapshots="$snapshots" \
          '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind date <<END
$snap
END

if uname -r | grep -q -- "-lts$"; then
    kernel="linux-lts"
else
    kernel="linux"
fi

linux_conf="$(savefromboot  "vmlinuz-$kernel" | sed 's|/boot/||')"
initrd_conf="$(savefromboot "initramfs-$kernel.img" | sed 's|/boot/||')"

if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
    echo "Error creating configuration for kernel and initrd"
    continue
fi

# shellcheck disable=SC2001
kind="$(echo "$kind" | sed 's|/||g')"

sed -E \
    -e "s|^title .+|title   $kind/$date|;" \
    -e "s|subvol=@|subvol=@/$snapshots/$kind/$date|" \
    -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
    -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf|" \
    -e "s|//+|/|g" \
    "/boot/loader/entries/$template" \
    | tee "/boot/loader/entries/$date.conf"
done
