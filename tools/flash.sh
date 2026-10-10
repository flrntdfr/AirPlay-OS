#!/usr/bin/env bash
# Write the Ampberry image to an SD card on macOS. Interactive, double-checks the target disk.
#
#   tools/flash.sh /dev/disk4                      # latest build/pi-gen/deploy/*Ampberry-lite.img.xz
#   tools/flash.sh /dev/disk4 path/to/image.img.xz
#
# Find the card with `diskutil list` (look for the SD card's size and "external, physical").
# The image already carries the cloud-init seed (Wi-Fi, SSH keys, hotspot PSK) from the build.
set -euo pipefail
cd "$(dirname "$0")/.."

DISK="${1:-}"
IMAGE="${2:-$(ls -t build/pi-gen/deploy/*Ampberry-lite.img.xz 2>/dev/null | head -1 || true)}"
[[ -n "$DISK" ]] || { echo "usage: tools/flash.sh /dev/diskN [image.img.xz]" >&2; exit 2; }
[[ -n "$IMAGE" && -f "$IMAGE" ]] || { echo "no image found — run tools/build-image.sh first" >&2; exit 1; }
[[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || { echo "target must be a whole disk like /dev/disk4" >&2; exit 2; }
[[ "$(uname)" == Darwin ]] || { echo "this script uses diskutil (macOS)" >&2; exit 1; }

echo "== target"
diskutil info "$DISK" | grep -E "Device Node|Media Name|Disk Size|Protocol|Internal|Removable Media" || true
diskutil info "$DISK" | grep -qE "Internal:\s+No|Removable Media:\s+Removable" || {
	echo "refusing: $DISK does not look like an external/removable disk" >&2; exit 1; }
echo "== image: $IMAGE ($(du -h "$IMAGE" | cut -f1))"
read -r -p "ERASE $DISK and write the image? type the disk name to confirm: " ans
[[ "$ans" == "$DISK" ]] || { echo "aborted"; exit 1; }

RAW="${DISK/disk/rdisk}"
diskutil unmountDisk "$DISK"
echo "== writing (this takes a few minutes; progress needs root)"
xz -dc "$IMAGE" | sudo dd of="$RAW" bs=4m status=progress conv=sync
sync
diskutil eject "$DISK" || true
echo "== done. First boot: cloud-init joins Wi-Fi, activates the Nix closure baked into the image,"
echo "   runs 'ampberry provision'; a few minutes later http://ampberry.local/ answers."
