#!/bin/bash -e
# Ship the flake source for the build-time evaluation in 04-nix (and as first-boot fallback).
# files/ampberry/ is the git-filtered store copy of the flake, placed by tools/build-image.sh.
# After activation, /opt/ampberry is a tmpfiles symlink into the Nix store (same source).
[ -f files/ampberry/flake.nix ] || { echo "missing files/ampberry/flake.nix — run tools/build-image.sh" >&2; exit 1; }
rm -rf "${ROOTFS_DIR}/usr/local/src/ampberry"
install -d -m 755 "${ROOTFS_DIR}/usr/local/src/ampberry"
cp -a files/ampberry/. "${ROOTFS_DIR}/usr/local/src/ampberry/"
chown -R root:root "${ROOTFS_DIR}/usr/local/src/ampberry"
log "flake source installed at /usr/local/src/ampberry ($(du -sh files/ampberry | cut -f1))"
