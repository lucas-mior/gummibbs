# shellcheck disable=SC2034

export LC_ALL=C
shopt -s nullglob

error () {
    >&2 printf "$@"
    return
}

valid_kinds=(manual boot hour day week month)
is_valid () {
    for valid_kind in "${valid_kinds[@]}"; do
        if [ "$valid_kind" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

config="/etc/systemd-boot-btrfsd.conf"

if [ ! -f /etc/os-release ] || ! grep -q '^ID=arch' /etc/os-release; then
    error "Not running Arch Linux. Exiting...\n"
    exit 1
fi

if ! bootctl status >/dev/null 2>&1; then
    error "Not using systemd-boot. Exiting...\n"
    exit 1
fi

if test -n "$(find /boot/ -maxdepth 1 -iname "*.efi" -print -quit)"; then
    error "Unified kernel images detected in /boot. Exiting...\n"
    exit 1
fi

if command -v dracut >/dev/null 2>&1; then
    error "Dracut detected. Exiting..."
    exit 1
fi

snapshots="/.snapshots/"

if btrfs subvol show / | head -n 1 | grep -Eq -- "$snapshots"; then
    error "Snapshot mounted. Exiting...\n"
    exit 1
fi
