# pj-domina-rf-shared_dir-aur

Arch packaging repository for
[`shared_dir`](https://github.com/robert-flo/pj-domina-rf-shared_dir).

This checkout is the packaging surface only. The product lives in the upstream
source repository. The local `shared_dir` file is the `/usr/bin` launcher: it
requests `sudo` when needed, then execs the private payload under
`/opt/shared_dir/shared_dir`.

## Package

| Field | Value |
| --- | --- |
| `pkgname` | `shared_dir` |
| Upstream | https://github.com/robert-flo/pj-domina-rf-shared_dir |
| Pinned release | `v0.1.0` |
| Payload | `/opt/shared_dir/shared_dir` |
| Launcher | `/usr/bin/shared_dir` |
| Runtime depends | `acl`, `inotify-tools`, `sudo` |

## Maintainer commands

```bash
make build
make install
make reinstall
make clean
make lint
make test-automation
make test-release
make test-local SOURCE_DIR=/path/to/shared_dir
make test SOURCE_DIR=/path/to/shared_dir
make update-upstream
```

`SOURCE_DIR` must point at a Git worktree of the upstream source repository
that contains the root `./shared_dir` product. Local install validation uses
`git archive HEAD`, so only **committed** upstream files are packaged.

## Validations

| Target | What it proves |
| --- | --- |
| `make lint` | `.SRCINFO` matches `PKGBUILD`, shell syntax/ShellCheck, whitespace |
| `make test-automation` | Upstream detect/update scripts (offline fixtures) |
| `make test-release` | Published GitHub archive + launcher match pinned checksums |
| `make test-local` | Build/install from local source in a privileged systemd container, then run `shared_dir` end-to-end |

## AUR remote (not published by default)

When you are ready to publish:

```bash
git remote add aur ssh://aur@aur.archlinux.org/shared_dir.git
# review PKGBUILD + .SRCINFO, then:
# git push aur master
```

This repository prepares packaging metadata for that push; it does not push to
AUR automatically.
