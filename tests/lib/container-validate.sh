#!/usr/bin/env bash

# Runs INSIDE the disposable privileged Arch container started by
# validate-local-install.sh (systemd already running as PID 1). Never run on
# the host.
#
# Expects, mounted read-only by the caller:
#   /package               the shared_dir package sources (PKGBUILD, launcher)
#   /archive/shared_dir-${PKG_VERSION}.tar.gz   the local source snapshot
#
# Expects, from the environment:
#   PKG_VERSION             package version, matches the archive filename

set -Eeuo pipefail

readonly DEMO_DIR=/demo-shared

phase_install_prereqs() {
  printf '\n==> [container 1/5] Refreshing Arch and installing package prerequisites\n'
  printf '    These packages exist only inside this disposable container.\n\n'
  pacman -Syu --noconfirm --needed \
    fakeroot \
    sudo \
    acl \
    inotify-tools
}

phase_create_builder_user() {
  printf '\n==> [container 2/5] Creating the unprivileged makepkg user\n'
  if ! id builder > /dev/null 2>&1; then
    useradd --create-home builder
  fi
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/builder
  chmod 0440 /etc/sudoers.d/builder
}

phase_prepare_workspace() {
  printf '==> [container 3/5] Preparing the writable package workspace\n'
  rm -rf /work/package
  install -d -m 0755 /work/package
  cp -a /package/. /work/package/

  # The checkout may contain ignored makepkg artifacts. They must not let this
  # validation install an older package instead of building the current PKGBUILD.
  find /work/package -maxdepth 1 -type f -name '*.pkg.tar.*' -delete

  # A local git archive has different bytes from the published GitHub archive.
  # Redirect PKGBUILD to it here; validate-release-archive.sh independently
  # checks the published checksums.
  sed -i \
    "s|\${url}/archive/refs/tags/v\${pkgver}.tar.gz|file:///archive/shared_dir-${PKG_VERSION}.tar.gz|" \
    /work/package/PKGBUILD

  chown -R builder:builder /work/package
}

phase_build_and_install() {
  printf '==> [container 4/5] Building and installing the local package\n'
  su --shell /bin/bash builder --command \
    'cd /work/package && makepkg -Cfi --noconfirm --needed --skipchecksums'
}

phase_verify_package_and_product() {
  local desktop_file=/usr/share/applications/shared_dir.desktop
  local nonroot_status=0

  printf '==> [container 5/5] Verifying package files and running shared_dir e2e\n'

  test -x /usr/bin/shared_dir
  test -x /opt/shared_dir/shared_dir
  test -f /usr/share/licenses/shared_dir/LICENSE
  grep -Fq '/opt/shared_dir/shared_dir' /usr/bin/shared_dir

  test -f "$desktop_file"
  grep -Fxq '[Desktop Entry]' "$desktop_file"
  grep -Fxq 'Name=shared_dir' "$desktop_file"
  grep -Fxq 'Exec=shared_dir' "$desktop_file"
  grep -Fxq 'TryExec=shared_dir' "$desktop_file"
  grep -Fxq 'Terminal=true' "$desktop_file"
  grep -Fxq 'Type=Application' "$desktop_file"
  grep -Fxq 'Icon=utilities-terminal' "$desktop_file"
  grep -Fxq 'Categories=System;Utility;' "$desktop_file"

  # Installer defaults to group wheel.
  getent group wheel > /dev/null || groupadd -r wheel

  # Non-root must refuse (run as the unprivileged builder account).
  su --shell /bin/bash builder --command \
    "printf '%s\n' '$DEMO_DIR' | /usr/bin/shared_dir" \
    > /tmp/shared_dir-nonroot.out 2>&1 || nonroot_status=$?
  ((nonroot_status != 0)) || {
    printf 'ERROR: shared_dir succeeded without root\n' >&2
    cat /tmp/shared_dir-nonroot.out >&2
    exit 1
  }
  grep -Fq 'This script must be run as root.' /tmp/shared_dir-nonroot.out

  # Root e2e on a disposable path inside this throwaway container.
  printf '%s\n' "$DEMO_DIR" | /usr/bin/shared_dir > /tmp/shared_dir-e2e.out

  grep -Fq 'Configuration completed successfully.' /tmp/shared_dir-e2e.out
  grep -Fq "Directory:            $DEMO_DIR" /tmp/shared_dir-e2e.out
  grep -Fq 'Group:                wheel' /tmp/shared_dir-e2e.out

  test -d "$DEMO_DIR"
  systemctl is-active demo-shared-perms.service
  test -x /usr/local/bin/fix_shared_dir_perms.sh
  test -f /etc/systemd/system/demo-shared-perms.service
  test -f /etc/systemd/system/demo-shared-perms.timer
  getfacl -p "$DEMO_DIR" | grep -Fq 'group:wheel:rwx'

  printf '==> [container 5/5] PASS: package layout and shared_dir e2e succeeded\n'
}

main() {
  phase_install_prereqs
  phase_create_builder_user
  phase_prepare_workspace
  phase_build_and_install
  phase_verify_package_and_product
}

main "$@"
