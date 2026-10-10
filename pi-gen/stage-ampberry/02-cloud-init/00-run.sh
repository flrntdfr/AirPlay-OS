#!/bin/bash -e
# A personal image carries a rendered cloud-init seed (files/ from tools/build-user-data.rb: the
# Wi-Fi passphrase, SSH keys, the pi password hash — exactly like Raspberry Pi Imager does). The
# public, secret-free image (GENERIC=1) ships none: pi-gen's stock seed stays, so the Raspberry Pi
# Imager's own customization works, and 05-firstboot activates the system instead.
if [ -f files/user-data ]; then
	for f in user-data network-config meta-data; do
		[ -f "files/${f}" ] || { echo "missing files/${f} — run tools/build-image.sh, not pi-gen directly" >&2; exit 1; }
		install -v -m 644 "files/${f}" "${ROOTFS_DIR}/boot/firmware/${f}"
	done
	log "personal cloud-init seed installed"
else
	log "generic image: no cloud-init seed of our own (Raspberry Pi Imager customization applies)"
fi
