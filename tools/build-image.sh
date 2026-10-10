#!/usr/bin/env bash
# Build the AirPlay OS image with pi-gen inside Docker (arm64 native: Apple Silicon or an arm64
# CI runner). Nix is installed into the image and the flake's system closure is pre-built in the
# chroot, so a failing flake or module fails *here*, in the build log.
#
#   GENERIC=1 tools/build-image.sh   public image: no secrets, no seed of ours — first boot activates
#                                    the baked system by itself; the Raspberry Pi Imager's own
#                                    customization (user, SSH key, Wi‑Fi) applies. This is what CI
#                                    releases.
#   tools/build-image.sh             personal image: the cloud-init seed rendered from secrets.env
#                                    (Wi‑Fi, SSH keys, hotspot PSK, pi's password hash) is baked in
#   CONTINUE=1 …                     re-run after a failure, reusing finished stages
#   SKIP_BASE=1 …                    skip stage0-2 (already built in build/pi-gen/work)
#   AIRPLAY_OS_VERSION=v40 …         stamped into /etc/ampberry-release (CI passes the build number)
#
# Output: build/pi-gen/deploy/<date>-airplay-os-lite.img.xz (+ .info, .sbom)
# Log:    build/image-build.log
set -euo pipefail
cd "$(dirname "$0")/.."

GENERIC="${GENERIC:-0}"
SECRETS="${SECRETS:-secrets.env}"
DEVICE="${DEVICE:-ampberry}"
VERSION="${AIRPLAY_OS_VERSION:-v$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running" >&2; exit 1; }
if [ "$GENERIC" != 1 ]; then
	[ -f "$SECRETS" ] || { echo "$SECRETS missing (copy secrets.env.example, or GENERIC=1 for the public image)" >&2; exit 1; }
	# shellcheck source=/dev/null
	. "$SECRETS"
fi

mkdir -p build
PG=build/pi-gen
if [ ! -d "$PG/.git" ]; then
	git clone --branch arm64 --depth 1 https://github.com/RPi-Distro/pi-gen.git "$PG"
fi

# 1. our stage: scripts, the flake source, and (personal image) the rendered seed
rm -rf "$PG/stage-ampberry"
cp -R pi-gen/stage-ampberry "$PG/stage-ampberry"
chmod +x "$PG"/stage-ampberry/*/*.sh "$PG"/stage-ampberry/prerun.sh
mkdir -p "$PG/stage-ampberry/02-cloud-init/files" "$PG/stage-ampberry/03-flake/files"
if [ "$GENERIC" != 1 ]; then
	nix shell nixpkgs#ruby_3_4 --command ruby tools/build-user-data.rb --device "$DEVICE" --out build --secrets "$SECRETS"
	[ -s build/network-config.device ] && cp build/network-config.device build/network-config # byte-identical to the running device
	cp build/user-data build/network-config build/meta-data "$PG/stage-ampberry/02-cloud-init/files/"
fi
# the flake source exactly as Nix sees it (git-filtered: no build/, no secrets, no .git).
# `nix flake prefetch` always yields the store copy; `metadata` has no "path" with lazy trees.
SRC="$(nix flake prefetch --json . | python3 -c 'import json,sys; print(json.load(sys.stdin)["storePath"])')"
[ -f "$SRC/flake.nix" ] || { echo "could not get the flake's store copy ($SRC)" >&2; exit 1; }
rm -rf "$PG/stage-ampberry/03-flake/files/ampberry"
cp -R "$SRC/" "$PG/stage-ampberry/03-flake/files/ampberry" # the flake = the repo root
chmod -R u+w "$PG/stage-ampberry/03-flake/files/ampberry"

# 2. config: committed part + build-specific lines
{
	cat pi-gen/config
	echo "AIRPLAY_OS_VERSION=\"${VERSION}\""
	echo "AIRPLAY_OS_DEVICE=\"${DEVICE}\""
	if [ "$GENERIC" = 1 ]; then
		# console-only default password (the sshd policy in the flake never accepts passwords);
		# the Raspberry Pi Imager sets the real credentials
		echo 'FIRST_USER_PASS="airplay-os"'
		echo 'PUBKEY_ONLY_SSH=0'
	else
		echo "FIRST_USER_PASS=\"${PI_FIRST_USER_PASS:-ampberry}\""   # locked for SSH (PUBKEY_ONLY_SSH), console only
		echo 'PUBKEY_ONLY_SSH=1'
		echo "PUBKEY_SSH_FIRST_USER=\"${SSH_AUTHORIZED_KEYS}\""
	fi
} > "$PG/config"

# 3. only export an image after our stage
touch "$PG/stage2/SKIP_IMAGES"
if [ "${SKIP_BASE:-0}" = "1" ]; then touch "$PG"/stage{0,1,2}/SKIP; else rm -f "$PG"/stage{0,1,2}/SKIP; fi

# 4. build
echo "building image $VERSION ($([ "$GENERIC" = 1 ] && echo generic || echo personal), device $DEVICE; log: build/image-build.log) ..."
(
	cd "$PG"
	PRESERVE_CONTAINER=1 CONTINUE="${CONTINUE:-0}" ./build-docker.sh
) 2>&1 | tee build/image-build.log
echo
ls -la "$PG/deploy/" 2>/dev/null || echo "no deploy output — check build/image-build.log"
