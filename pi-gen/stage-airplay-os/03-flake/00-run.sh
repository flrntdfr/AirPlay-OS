#!/bin/bash -e
# Ship the flake source for the build-time evaluation in 04-nix (and as first-boot fallback).
# files/airplay-os/ is the git-filtered store copy of the flake, placed by tools/build-image.sh.
# After activation, /opt/airplay-os is a tmpfiles symlink into the Nix store (same source).
[ -f files/airplay-os/flake.nix ] || { echo "missing files/airplay-os/flake.nix — run tools/build-image.sh" >&2; exit 1; }
rm -rf "${ROOTFS_DIR}/usr/local/src/airplay-os"
install -d -m 755 "${ROOTFS_DIR}/usr/local/src/airplay-os"
cp -a files/airplay-os/. "${ROOTFS_DIR}/usr/local/src/airplay-os/"
chown -R root:root "${ROOTFS_DIR}/usr/local/src/airplay-os"
log "flake source installed at /usr/local/src/airplay-os ($(du -sh files/airplay-os | cut -f1))"
