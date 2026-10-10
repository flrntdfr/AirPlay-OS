#!/usr/bin/env bash
# Build the branded Ampberry image with pi-gen inside Docker (arm64 native on Apple Silicon).
# This is the local test stage: Nix is installed into the image and the flake's system closure
# is pre-built in the chroot, so a failing flake or module fails *here*, in the build log.
#
#   tools/build-image.sh            full build (~45 min first time; downloads debootstrap, builds shairport)
#   CONTINUE=1 tools/build-image.sh re-run after a failure, reusing finished stages
#   SKIP_BASE=1 tools/build-image.sh skip stage0-2 (already built in build/pi-gen/work)
#
# Output: build/pi-gen/deploy/<date>-Ampberry-lite.img.xz (+ .info, .sbom, release notes)
# Log:    build/image-build.log
set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS="${SECRETS:-secrets.env}"
[ -f "$SECRETS" ] || { echo "$SECRETS missing (copy secrets.env.example, or run tools/apply-live.sh --harvest and use SECRETS=build/secrets.harvested.env)" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running" >&2; exit 1; }
# shellcheck source=/dev/null
. "$SECRETS"

mkdir -p build
PG=build/pi-gen
if [ ! -d "$PG/.git" ]; then
	git clone --branch arm64 --depth 1 https://github.com/RPi-Distro/pi-gen.git "$PG"
fi

# 1. cloud-init seed (carries secrets; lives only under build/)
nix shell nixpkgs#ruby_3_4 --command ruby tools/build-user-data.rb --out build --secrets "$SECRETS"
[ -f build/network-config.device ] && cp build/network-config.device build/network-config # byte-identical to the running device

# 2. our stage: scripts + rendered seed + flake source
rm -rf "$PG/stage-ampberry"
cp -R pi-gen/stage-ampberry "$PG/stage-ampberry"
chmod +x "$PG"/stage-ampberry/*/*.sh "$PG"/stage-ampberry/prerun.sh
mkdir -p "$PG/stage-ampberry/02-cloud-init/files" "$PG/stage-ampberry/03-flake/files/ampberry"
cp build/user-data build/network-config build/meta-data "$PG/stage-ampberry/02-cloud-init/files/"
# the flake source exactly as Nix sees it (git-filtered: no build/, no secrets, no .git)
SRC="$(nix flake metadata --json . | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
rm -rf "$PG/stage-ampberry/03-flake/files/ampberry"
cp -R "$SRC/" "$PG/stage-ampberry/03-flake/files/ampberry" # the flake = the repo repo
chmod -R u+w "$PG/stage-ampberry/03-flake/files/ampberry"

# 3. config: committed part + secrets
{
	cat pi-gen/config
	echo "FIRST_USER_PASS=\"${PI_FIRST_USER_PASS:-ampberry}\""   # locked for SSH (PUBKEY_ONLY_SSH), console only
	echo "PUBKEY_SSH_FIRST_USER=\"${SSH_AUTHORIZED_KEYS}\""
} > "$PG/config"

# 4. only export an image after our stage
touch "$PG/stage2/SKIP_IMAGES"
if [ "${SKIP_BASE:-0}" = "1" ]; then touch "$PG"/stage{0,1,2}/SKIP; else rm -f "$PG"/stage{0,1,2}/SKIP; fi

# 5. build
echo "building image (log: build/image-build.log) ..."
(
	cd "$PG"
	PRESERVE_CONTAINER=1 CONTINUE="${CONTINUE:-0}" ./build-docker.sh
) 2>&1 | tee build/image-build.log
echo
ls -la "$PG/deploy/" 2>/dev/null || echo "no deploy output — check build/image-build.log"
