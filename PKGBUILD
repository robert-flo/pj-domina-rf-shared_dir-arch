pkgname=shared_dir
pkgver=0.1.0
pkgrel=1
pkgdesc='Create a group-shared directory with ACL and systemd permission monitoring'
arch=('any')
url='https://github.com/robert-flo/shared_dir'
license=('MIT')
options=('!debug')
depends=('acl' 'inotify-tools')
source=(
  "${pkgname}-${pkgver}.tar.gz::${url}/archive/refs/tags/v${pkgver}.tar.gz"
  "${pkgname}"
)
sha256sums=(
  'ba8f1fc199094a3dddff9a972f1b877348116152f318e211e5f602afde63d780'
  '2907286aacaf3b6bb32fd996a40c23536e24d52d4aec321c96d541152317dfbb'
)

package() {
  local source_dir="${srcdir}/${pkgname}-${pkgver}"
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
