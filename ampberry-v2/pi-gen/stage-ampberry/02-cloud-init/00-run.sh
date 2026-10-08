#!/bin/bash -e
# Replace pi-gen's placeholder cloud-init seed with the rendered Ampberry one.
# files/ is populated by tools/build-image.sh from tools/build-user-data.pl output
# (it carries the Wi-Fi passphrase and the pi password hash, exactly like Raspberry Pi Imager does).
for f in user-data network-config meta-data; do
	[ -f "files/${f}" ] || { echo "missing files/${f} — run tools/build-image.sh, not pi-gen directly" >&2; exit 1; }
	install -v -m 644 "files/${f}" "${ROOTFS_DIR}/boot/firmware/${f}"
done
