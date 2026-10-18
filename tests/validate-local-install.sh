#!/usr/bin/env bash

# End-to-end validation for a local shared_dir source checkout.
#
# Creates a release-shaped archive from committed upstream HEAD, starts a
# privileged Arch container with systemd as PID 1 (same model as the upstream
# source `make docker-run` trial), builds/installs the package inside it, and
# runs shared_dir end-to-end. Never installs packages on the host and never
# mounts the host HOME directory.
#
# Important: `git archive HEAD` excludes staged, unstaged, ignored, and
# untracked source files. Commit source changes before running this validation.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR
readonly CONTAINER_SCRIPT="$SCRIPT_DIR/lib/container-validate.sh"
PKG_VERSION="$(awk -F= '/^pkgver=/{print $2; exit}' "$PACKAGE_DIR/PKGBUILD")"
readonly PKG_VERSION
readonly PKG_ARCHIVE_PREFIX="PJ-DOMINA-rf-shared_dir-${PKG_VERSION}/"
readonly SANDBOX_NAME="shared_dir-package-validate-$$"
readonly READY_TIMEOUT=40

# shellcheck disable=SC1091 # The library path is derived from this script's location.
source "$SCRIPT_DIR/lib/host-checks.sh"

source_dir="${SHARED_DIR_SOURCE_DIR:-}"
source_commit=""
archive_dir=""
archive_path=""

usage() {
  cat <<'USAGE'
Usage:
  SHARED_DIR_SOURCE_DIR=/path/to/shared_dir \
    tests/validate-local-install.sh

  # or via Make:
  make test-local SOURCE_DIR=/path/to/shared_dir

Purpose:
  Build the package from a local source checkout, install it in a disposable
  privileged Arch Linux container with systemd as PID 1, and run the installed
  shared_dir product end-to-end (ACLs + permission units).

Required input:
  SHARED_DIR_SOURCE_DIR
    Path to the separate shared_dir source-repository checkout. The directory
    must be a Git worktree and contain the root ./shared_dir product.

Source snapshot rule:
  The test uses `git archive HEAD`, so it validates committed source files only.

Container model:
  Matches the upstream source Docker trial: detached privileged container,
  systemd as PID 1, then docker exec of the validation script.

Host impact:
  - No host packages are installed or upgraded by this script.
  - No host HOME is mounted.
  - Temporary archives and the sandbox container are removed on exit.

Checksum behavior:
  The generated local archive is not byte-identical to GitHub's release archive,
  so this test redirects PKGBUILD to the local file and uses --skipchecksums.
  validate-release-archive.sh independently verifies the published checksums.

Exit status:
  0  Package installation and product e2e checks passed.
  2  Usage, host dependency, or source-checkout configuration error.
  *  Docker, pacman, makepkg, installation, or a product assertion failed.
USAGE
}

check_host_deps() {
  command -v git > /dev/null 2>&1 || die 'git is required on the host to create the source archive.'
  require_docker
  [[ -f $CONTAINER_SCRIPT ]] || die "missing companion script: $CONTAINER_SCRIPT"
  [[ $PKG_VERSION =~ ^[0-9]+([.][0-9]+)*$ ]] || die 'PKGBUILD contains an invalid pkgver.'
}

validate_source_dir() {
  if [[ -z $source_dir || ! -d $source_dir || ! -f $source_dir/shared_dir ]]; then
    printf '%s\n\n' 'ERROR: Set SHARED_DIR_SOURCE_DIR to a shared_dir source checkout.' >&2
    usage >&2
    exit 2
  fi

  if [[ $(git -C "$source_dir" rev-parse --is-inside-work-tree 2> /dev/null) != true ]]; then
    die "SHARED_DIR_SOURCE_DIR is not a Git worktree: $source_dir"
  fi

  source_dir="$(cd "$source_dir" && pwd)"
  source_commit="$(git -C "$source_dir" rev-parse --short HEAD)"
}

setup_archive_workspace() {
  archive_dir="$(mktemp -d "${TMPDIR:-/tmp}/shared_dir-package.XXXXXX")"
  chmod 0755 "$archive_dir"
  archive_path="$archive_dir/shared_dir-${PKG_VERSION}.tar.gz"
}

cleanup() {
  docker rm -f "$SANDBOX_NAME" > /dev/null 2>&1 || true
  rm -rf "$archive_dir"
}

print_plan() {
  cat <<PLAN
Local package installation validation
-------------------------------------
Source checkout: $source_dir
Source commit:   $source_commit (committed HEAD only)
Package files:   $PACKAGE_DIR
Container:       privileged archlinux:latest + systemd (ephemeral)

makepkg and shared_dir run inside the container, not on the host.
PLAN
}

build_source_archive() {
  printf '\n==> [host 1/3] Creating the temporary source archive\n'
  git -C "$source_dir" archive --format=tar.gz \
    --prefix="$PKG_ARCHIVE_PREFIX" \
    HEAD > "$archive_path"
}

wait_for_systemd() {
  local st
  for _ in $(seq 1 "$READY_TIMEOUT"); do
    if ! docker container inspect "$SANDBOX_NAME" > /dev/null 2>&1; then
      die 'sandbox container exited before systemd became ready'
    fi
    st="$(docker exec "$SANDBOX_NAME" systemctl is-system-running 2> /dev/null || true)"
    case $st in
      running | degraded)
        return 0
        ;;
    esac
    sleep 1
  done
  docker logs "$SANDBOX_NAME" 2>&1 | tail -50 || true
  die "timed out waiting for systemd (last state=${st:-empty})"
}

run_container_validation() {
  printf '==> [host 2/3] Starting privileged systemd sandbox\n'
  docker rm -f "$SANDBOX_NAME" > /dev/null 2>&1 || true
  docker run -d \
    --name "$SANDBOX_NAME" \
    --privileged \
    --cgroupns=host \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --volume "$PACKAGE_DIR:/package:ro" \
    --volume "$archive_dir:/archive:ro" \
    --volume "$CONTAINER_SCRIPT:/container-validate.sh:ro" \
    --env "PKG_VERSION=$PKG_VERSION" \
    archlinux:latest \
    /usr/lib/systemd/systemd --system > /dev/null

  wait_for_systemd
  printf '==> [host 3/3] Building the package and running shared_dir e2e inside the sandbox\n'
  docker exec "$SANDBOX_NAME" bash /container-validate.sh
}

main() {
  parse_help_arg "$@"
  check_host_deps
  validate_source_dir
  setup_archive_workspace
  trap cleanup EXIT
  print_plan
  build_source_archive
  run_container_validation
  printf '\nPASS: local package validation succeeded — build, installation, launcher, payload, and shared_dir e2e behaved as expected.\n\n'
}

main "$@"
