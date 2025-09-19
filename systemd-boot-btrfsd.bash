#!/bin/bash

exec 1>&2

snapshots="/.snapshots/"
template="arch.conf"

# add missing boot entries for existing snapshots
kinds=("manual" "boot" "hour" "day" "week" "month")

for kind in "${kinds[@]}"; do
    # shellcheck disable=SC2010
    for snap in "/$snapshots/$kind/"*; do
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
    echo "entry=$entry"
    snap="$(echo "$entry" \
            | sed -E -e 's|/boot/loader/entries/||' \
                     -e 's|.conf||')"
    if echo "$snap" | grep -qv "^[0-9]\{8\}_[0-9]\{6\}"; then
        continue
    fi

    match="$(find "/$snapshots/" -maxdepth 2 -name "$snap")"
    if [ "$(echo "$match" | wc -l)" = "0" ]; then
        error.sh "$0" "$snap not found"
        rm -v "$entry"
    fi
done

while true; do
    snap="$(inotifywait -e create \
            "/$snapshots/"{manual,boot,hour,day,week,month} \
            | awk -v snapshots="$snapshots" \
              '{printf("%s,%s\n", gensub(snapshots, "", "g", $1), $NF)}')"

IFS="," read -r kind date <<END
$snap
END

kind="$(echo "$kind" | sed 's|/||g')"

    sed -E \
        -e "s|^title .+|title   $kind/$date|;" \
        -e "s|subvol=@|subvol=@/$snapshots/$kind/$date|" \
        -e "s|^linux .+/vmlinuz-linux$|linux /vmlinuz-linux-$date|" \
        -e "s|^linux .+/vmlinuz-linux-lts$|linux /vmlinuz-linux-lts-$date|" \
        -e "s|^initrd .+/initramfs-linux.img$|initrd /initramfs-linux-$date.img|" \
        -e "s|^initrd .+/initramfs-linux-lts.img$|initrd /initramfs-linux-lts-$date.img|" \
        -e "s|//+|/|g" \
        "/boot/loader/entries/$template" \
        | tee "/boot/loader/entries/$date.conf"
done
