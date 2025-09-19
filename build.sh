#!/bin/sh -e

# shellcheck disable=SC2086
set -e
set -x

target="${1:-install}"

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-/}"

program="snapshot.bash"
program2="systemd-boot-btrfsd.bash"
service="systemd-boot-btrfsd.service"
hook="systemctl-pacman.hook"

echo "0$0"

case "$target" in
"uninstall")
    rm -f ${DESTDIR}${PREFIX}/bin/${program}
    rm -f ${DESTDIR}${PREFIX}/bin/${program2}
    rm -f ${DESTDIR}${PREFIX}/lib/systemd/system/${service}
    rm -f ${DESTDIR}${PREFIX}/share/libalpm/hooks/${hook}
    ;;
"install")
    install -Dm755 ${program}  ${DESTDIR}${PREFIX}/bin/${program}
    install -Dm755 ${program2} ${DESTDIR}${PREFIX}/bin/${program2}
    install -Dm644 ${service}  ${DESTDIR}${PREFIX}/lib/systemd/system/${service}
    install -Dm644 ${hook}     ${DESTDIR}${PREFIX}/share/libalpm/hooks/${hook}
    ;;
esac
