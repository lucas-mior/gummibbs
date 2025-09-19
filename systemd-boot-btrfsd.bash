#!/bin/bash

printf "\n$0\n\n"

snapshots="/.snapshots/"
template="arch.conf"

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

    find /boot/ \
        -regextype egrep \
        -iregex "/boot/$base-.*" 2>&1 \
        | while read -r file; do
            diff "$file" "$current" >/dev/null 2>&1 \
                && echo "$file" \
                && return
        done

    conf="/boot/$base-$date$ext"
    cp "/boot/$current" "$conf" >/dev/null \
        && echo "$conf"
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

linux_conf="$(savefromboot "vmlinuz-$kernel")"
initrd_conf="$(savefromboot "initramfs-$kernel.img")"

if [ -z "$linux_conf" ] || [ -z "$linux_conf" ]; then
    echo "Error creating configuration for kernel and initrd"
    continue
fi

# shellcheck disable=SC2001
kind="$(echo "$kind" | sed 's|/||g')"

sed -E \
    -e "s|^title .+|title   $kind/$date|;" \
    -e "s|subvol=@|subvol=@/$snapshots/$kind/$date|" \
    -e "s|^linux .+/vmlinuz-linux.*|linux $linux_conf|" \
    -e "s|^initrd .+/initramfs-linux.*\.img$|initrd $initrd_conf|" \
    -e "s|//+|/|g" \
    "/boot/loader/entries/$template" \
    | tee "/boot/loader/entries/$date.conf"
done
