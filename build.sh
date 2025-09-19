#!/bin/sh -e

# shellcheck disable=SC2086

target="${1:-install}"

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-/}"

program="snapshot.bash"
program2="systemd-boot-btrfsd.bash"
service="systemd-boot-btrfsd.service"

case "$target" in
"uninstall")
    rm -f ${DESTDIR}${PREFIX}/bin/${program}
    rm -f ${DESTDIR}${PREFIX}/bin/${program}
    exit
    ;;
"install")
    install -Dm755 ${program}  ${DESTDIR}${PREFIX}/bin/${program}
    install -Dm755 ${program2} ${DESTDIR}${PREFIX}/bin/${program2}
    install -Dm644 ${service}  ${DESTDIR}${PREFIX}/lib/systemd/system/${service}
    systemctl enable --now $service
    exit
    ;;
esac
