#!/bin/sh

# shellcheck disable=SC2010
template="arch.conf"

find /.snapshots/ -mindepth 2 -maxdepth 2 \
| while read -r snapshot; do
    snap=$(echo "$snapshot" | awk -F'/' '{print $NF}')
    kind=$(echo "$snapshot" | awk -F'/' '{print $(NF-1)}')
    # if ls -1 "$snapshot/usr/lib/modules" | grep -q -- "-lts"; then
    #     kernel="$(ls -1 "$snapshot/usr/lib/modules" | grep -- "-lts")"
    #     name="$(echo "$kernel" | sed 's/-lts//')"
    #     down="linux-lts-$name-x86_64.pkg.tar.xz"
    #     down2="linux-lts-$name-x86_64.pkg.tar.zst"
    #     url="https://archive.archlinux.org/packages/l/linux-lts"
    #     echo "down=$down"

    #     pacman -U "$url/$down" --noconfirm --needed \
    #         || pacman -U "$url/$down2" --noconfirm --needed \
    #         || continue

    #     linux_conf="$(savefromboot "vmlinuz-linux-lts" | sed 's|/boot/||')"
    #     initrd_conf="$(savefromboot "initramfs-linux-lts.img" | sed 's|/boot/||')"

    #     if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
    #         echo "Error creating configuration for kernel and initrd"
    #         continue
    #     fi

    #     entry="/boot/loader/entries/$snap.conf"
    #         sed -E -e "s|^title .+|title $kind/$snap|" \
    #                -e "s|subvol=@|subvol=@/.snapshots/$kind/$snap|" \
    #                -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
    #                -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf|" \
    #                -e "s|//+|/|g" \
    #             "/boot/loader/entries/$template" \
    #             | tee "$entry"

    if ls -1 "$snapshot/usr/lib/modules" | grep -q -- "-arch"; then
        kernel="$(ls -1 "$snapshot/usr/lib/modules" | grep -- "-arch")"
        name="$(echo "$kernel" | sed 's/-arch/.arch/')"
        down="linux-$name-x86_64.pkg.tar.zst"
        down2="linux-$name-x86_64.pkg.tar.xz"
        url="https://archive.archlinux.org/packages/l/linux"
        echo "down=$down"

        pacman -U "$url/$down" --noconfirm --needed \
            || pacman -U "$url/$down2" --noconfirm --needed \
            || continue

        linux_conf="$(savefromboot "vmlinuz-linux" | sed 's|/boot/||')"
        initrd_conf="$(savefromboot "initramfs-linux.img" | sed 's|/boot/||')"

        if [ -z "$linux_conf" ] || [ -z "$initrd_conf" ]; then
            echo "Error creating configuration for kernel and initrd"
            continue
        fi

        entry="/boot/loader/entries/$snap.conf"
        sed -E -e "s|^title .+|title $kind/$snap|" \
               -e "s|subvol=@|subvol=@/.snapshots/$kind/$snap|" \
               -e "s|^linux .+/vmlinuz-linux.*|linux /$linux_conf|" \
               -e "s|^initrd .+/initramfs-linux.*\.img$|initrd /$initrd_conf|" \
               -e "s|//+|/|g" \
            "/boot/loader/entries/$template" \
            | tee "$entry"
    else
        echo "$snap has no kernel"
    fi
done

pacman -S linux-lts --noconfirm
