#!/usr/bin/env bash
# Write the AirPlay OS image to an SD card on macOS or Linux. Interactive, double-checks the target disk.
#
#   tools/flash.sh /dev/disk4                      # macOS; latest build/pi-gen/deploy/*airplay-os-lite.img.xz
#   tools/flash.sh /dev/sdb path/to/image.img.xz   # Linux (also /dev/mmcblk0)
#
# Find the card with `diskutil list` (macOS: "external, physical") or `lsblk` (Linux: removable / usb).
# The image already carries the cloud-init seed (Wi-Fi, SSH keys, hotspot PSK) from the build.
set -euo pipefail
cd "$(dirname "$0")/.."

OS="$(uname)"
DISK="${1:-}"
IMAGE="${2:-$(ls -t build/pi-gen/deploy/*airplay-os-lite.img.xz 2>/dev/null | head -1 || true)}"
[[ -n "$DISK" ]] || { echo "usage: tools/flash.sh /dev/<disk> [image.img.xz]" >&2; exit 2; }
[[ -n "$IMAGE" && -f "$IMAGE" ]] || { echo "no image found — download one or run tools/build-image.sh first" >&2; exit 1; }
command -v xz >/dev/null || { echo "xz is required to decompress the image" >&2; exit 1; }

case "$OS" in
Darwin)
	[[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || { echo "target must be a whole disk like /dev/disk4" >&2; exit 2; }
	echo "== target"
	diskutil info "$DISK" | grep -E "Device Node|Media Name|Disk Size|Protocol|Internal|Removable Media" || true
	diskutil info "$DISK" | grep -qE "Internal:\s+No|Removable Media:\s+Removable" || {
		echo "refusing: $DISK does not look like an external/removable disk" >&2; exit 1; }
	;;
Linux)
	[[ "$DISK" =~ ^/dev/(sd[a-z]+|vd[a-z]+|mmcblk[0-9]+|nvme[0-9]+n[0-9]+)$ ]] || {
		echo "target must be a whole disk like /dev/sdb or /dev/mmcblk0" >&2; exit 2; }
	[[ -b "$DISK" ]] || { echo "$DISK is not a block device" >&2; exit 1; }
	command -v lsblk >/dev/null || { echo "lsblk is required" >&2; exit 1; }
	echo "== target"
	lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINT "$DISK"
	if lsblk -nro MOUNTPOINT "$DISK" | grep -qE '^(/|/boot|/boot/efi|/home|/usr|/var)$'; then
		echo "refusing: $DISK holds a mounted system partition" >&2; exit 1
	fi
	info="$(lsblk -dno RM,TRAN "$DISK" | tr -s ' ')"
	[[ "$DISK" == /dev/mmcblk* || "$info" == "1"* || "$info" == *usb* ]] || {
		echo "refusing: $DISK does not look like removable media (RM/TRAN: $info)" >&2; exit 1; }
	;;
*)
	echo "unsupported OS: $OS (macOS and Linux only)" >&2; exit 1 ;;
esac

echo "== image: $IMAGE ($(du -h "$IMAGE" | cut -f1))"
read -r -p "ERASE $DISK and write the image? type the disk name to confirm: " ans
[[ "$ans" == "$DISK" ]] || { echo "aborted"; exit 1; }

echo "== writing (this takes a few minutes; progress needs root)"
if [[ "$OS" == Darwin ]]; then
	RAW="${DISK/disk/rdisk}"
	diskutil unmountDisk "$DISK"
	xz -dc "$IMAGE" | sudo dd of="$RAW" bs=4m status=progress conv=sync
	sync
	diskutil eject "$DISK" || true
else
	for mp in $(lsblk -nro MOUNTPOINT "$DISK" | grep -v '^$' || true); do sudo umount "$mp"; done
	xz -dc "$IMAGE" | sudo dd of="$DISK" bs=4M status=progress conv=fsync
	sync
	sudo eject "$DISK" 2>/dev/null || true
fi
echo "== done. First boot: cloud-init joins Wi-Fi, activates the Nix closure baked into the image,"
echo "   runs 'airplay-os provision'; a few minutes later http://ampberry.local/ answers."
