#!/usr/bin/env bash

# Simulates the PKGBUILD package() step with the pinned upstream source and
# verifies the installed payload actually runs: /opt/shared_dir/shared_dir
# --help must work from the packaging tree, which is only true when helper/
# and scripts/ were installed next to the main script.
#
# Source resolution, first match wins:
#   1. SHARED_DIR_SRC      path to an upstream git checkout (tarball is
#                          rebuilt with git archive and its SHA-256 must
#                          match the checksum pinned in PKGBUILD)
#   2. ../pj-domina-rf-shared_dir   sibling checkout, same rules
#   3. SHARED_DIR_TARBALL  path to a ready-made release tarball
#   4. the PKGBUILD source URL (works once the upstream repo is public)
# With no source at all the test SKIPs with exit 0.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR
readonly PKGBUILD_PATH="$PACKAGE_DIR/PKGBUILD"
readonly UPSTREAM_REPO="robert-flo/pj-domina-rf-shared_dir"

die() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

read_pkgver() {
  awk -F= '/^pkgver=/{gsub(/ /, "", $2); print $2; exit}' "$PKGBUILD_PATH"
}

read_archive_checksum() {
  awk -F "'" '
    /^sha256sums=\(/ { in_checksums = 1; next }
    in_checksums && /^\)/ { exit }
    in_checksums && NF >= 2 { print $2; exit }
  ' "$PKGBUILD_PATH"
}

pkgver="$(read_pkgver)"
readonly pkgver
archive_prefix="pj-domina-rf-shared_dir-${pkgver}/"
readonly archive_prefix

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
src_dir="$tmp_dir/src"
pkg_dir="$tmp_dir/pkg"

resolve_source_dir() {
  if [[ -n ${SHARED_DIR_SRC:-} ]]; then
    printf '%s\n' "$SHARED_DIR_SRC"
    return 0
  fi
  if [[ -d "$PACKAGE_DIR/../pj-domina-rf-shared_dir" ]]; then
    printf '%s\n' "$PACKAGE_DIR/../pj-domina-rf-shared_dir"
    return 0
  fi
  return 1
}

# Reproduce the byte-exact GitHub web tarball from a git checkout.
build_tarball_from_checkout() {
  local checkout=$1
  local tarball=$2
  git -C "$checkout" archive --format=tar \
    --prefix="$archive_prefix" "v${pkgver}" | gzip -n -6 >"$tarball"
  local checksum
  checksum="$(sha256sum "$tarball" | awk '{print $1}')"
  [[ $checksum == "$(read_archive_checksum)" ]] ||
    die "tarball checksum $checksum does not match the one pinned in PKGBUILD"
}

# A plain source tree (no .git): tar it under the expected prefix. The
# checksum cannot be verified in this mode.
build_tarball_from_tree() {
  local tree=$1
  local tarball=$2
  cp -a "$tree" "$tmp_dir/$archive_prefix"
  tar -C "$tmp_dir" -czf "$tarball" "$archive_prefix"
}

main() {
  local source_dir="" tarball=""

  if source_dir="$(resolve_source_dir)"; then
    tarball="$tmp_dir/source.tar.gz"
    if [[ -d "$source_dir/.git" ]]; then
      build_tarball_from_checkout "$source_dir" "$tarball"
    else
      printf 'WARN: %s no es un checkout git; no se puede verificar el checksum\n' "$source_dir" >&2
      build_tarball_from_tree "$source_dir" "$tarball"
    fi
  elif [[ -n ${SHARED_DIR_TARBALL:-} ]]; then
    tarball="$SHARED_DIR_TARBALL"
    local checksum
    checksum="$(sha256sum "$tarball" | awk '{print $1}')"
    [[ $checksum == "$(read_archive_checksum)" ]] ||
      die "tarball checksum $checksum does not match the one pinned in PKGBUILD"
  else
    tarball="$tmp_dir/source.tar.gz"
    if ! curl --fail --location --silent --show-error \
      "https://github.com/${UPSTREAM_REPO}/archive/refs/tags/v${pkgver}.tar.gz" \
      --output "$tarball"; then
      printf 'SKIP: no hay fuente de %s v%s disponible (repo privado y sin checkout)\n' \
        "$UPSTREAM_REPO" "$pkgver"
      exit 0
    fi
  fi

  mkdir -p "$src_dir"
  tar -C "$src_dir" -xzf "$tarball"
  cp "$PACKAGE_DIR/shared_dir" "$src_dir/shared_dir"

  # package() tal como la correría makepkg.
  (cd "$PACKAGE_DIR" && srcdir="$src_dir" pkgdir="$pkg_dir" bash -c 'source ./PKGBUILD && package')
  [[ -x "$pkg_dir/usr/bin/shared_dir" ]] || die "falta el wrapper /usr/bin/shared_dir"

  # Todo .sh de helper/ y scripts/ debe estar instalado, ejecutable y 755.
  local rel
  while IFS= read -r rel; do
    expected="$pkg_dir/opt/shared_dir/$rel"
    installed_mode="$(stat -c '%a' "$expected" 2>/dev/null || echo ausente)"
    if [[ $installed_mode != 755 ]]; then
      die "helper/scripts: $rel no quedó instalado con 755 (está: $installed_mode)"
    fi
  done < <(cd "$src_dir/$archive_prefix" && find helper scripts -name '*.sh' | sort)

  # La sonda que atrapa este bug: el script corre desde el pkgdir.
  if ! "$pkg_dir/opt/shared_dir/shared_dir" --help >/dev/null 2>&1; then
    die "shared_dir --help no corre desde el pkgdir (¿falta helper/ o scripts/?)"
  fi

  printf 'ok package() instaló el payload completo; shared_dir --help corre desde /opt/shared_dir\n'
}

main
