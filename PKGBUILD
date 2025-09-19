# Maintainer: lucas <lucas.mior.2@gmail.com>

pkgname=systemd-boot-btrfs-snapshots-git
pkgver=r2.602d645
pkgrel=1
pkgdesc="Btrfs snapshot scripts with systemd-boot integration"
arch=(x86_64)
url="https://github.com/lucas-mior/systemd-boot-btrfs-snapshots"
license=(AGPL)
depends=()
makedepends=(git)
provides=("systemd-boot-btrfs-snapshots")
conflicts=("systemd-boot-btrfs-snapshots")
source=("git+https://github.com/lucas-mior/systemd-boot-btrfs-snapshots.git")
md5sums=('SKIP')  # git sources are variable, skip checksum

pkgver() {
    cd "$srcdir/${pkgname%-git}"
    echo "r$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
}

package() {
    cd "$srcdir/${pkgname%-git}"
    export DESTDIR="$pkgdir"
    export PREFIX="/usr"
    ./build.sh install
}

post_install() {
    systemctl enable --now systemd-boot-btrfsd.service
}

post_upgrade() {
    systemctl enable --now systemd-boot-btrfsd.service
}
