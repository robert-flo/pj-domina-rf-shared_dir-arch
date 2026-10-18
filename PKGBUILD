pkgname=shared_dir
pkgver=0.3.0
pkgrel=1
pkgdesc='Create a group-shared directory with ACL and systemd permission monitoring'
arch=('any')
url='https://github.com/robert-flo/pj-domina-rf-shared_dir'
license=('MIT')
options=('!debug')
depends=('acl' 'inotify-tools' 'sudo')
source=(
  "${pkgname}-${pkgver}.tar.gz::${url}/archive/refs/tags/v${pkgver}.tar.gz"
  "${pkgname}"
)
sha256sums=(
  'b57f8925832c3d82c88f892c305c8e83590432e6ec653457bdf8af2689c07501'
  '2c949232dd9bf8a4a0b43e56af15039565d47f1a07184ad9d8b5896a24e4940d'
)

package() {
  local source_dir="${srcdir}/pj-domina-rf-${pkgname}-${pkgver}"
  local payload_dir="${pkgdir}/opt/${pkgname}"

  install -d "${payload_dir}"
  install -Dm755 "${source_dir}/shared_dir" "${payload_dir}/shared_dir"
  install -Dm755 "${srcdir}/${pkgname}" "${pkgdir}/usr/bin/${pkgname}"
  install -Dm644 "${source_dir}/LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  install -Dm644 /dev/stdin "${pkgdir}/usr/share/applications/${pkgname}.desktop" << 'DESKTOP_ENTRY'
[Desktop Entry]
Name=shared_dir
Comment=Create a group-shared directory with ACL and systemd permission monitoring
Exec=shared_dir
TryExec=shared_dir
Terminal=true
Type=Application
Icon=utilities-terminal
Categories=System;Utility;
Keywords=shared;directory;ACL;permissions;systemd;
DESKTOP_ENTRY
}
