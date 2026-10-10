#!/bin/bash -e
# Branding baked into the image. Only files no Debian package owns are touched, so
# unattended-upgrades never meets a modified conffile (that would hold packages back):
#   /etc/airplay-os-release      image-level provenance (the flake adds its own fields at activation)
#   /etc/machine-info          pretty hostname, chassis, deployment
#   /etc/update-motd.d/10-airplay-os   dynamic MOTD (pam_motd runs update-motd.d on Debian)
#   /etc/issue.d/airplay-os.issue      console login banner (agetty reads /etc/issue.d)

PI_GEN_COMMIT="$(git -C "${BASE_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

install -d -m 755 "${ROOTFS_DIR}/etc/airplay-os" "${ROOTFS_DIR}/etc/update-motd.d" "${ROOTFS_DIR}/etc/issue.d"

cat > "${ROOTFS_DIR}/etc/airplay-os-release" <<EOF
NAME="AirPlay OS"
PRETTY_NAME="AirPlay OS — AirPlay 2 receiver"
VERSION="${AIRPLAY_OS_VERSION:-dev}"
DEVICE="${AIRPLAY_OS_DEVICE:-ampberry}"
IMAGE_NAME="${IMG_NAME}${IMG_SUFFIX:--lite}"
IMAGE_DATE="${IMG_DATE}"
BASE="Raspberry Pi OS Lite (${RELEASE}), pi-gen ${PI_GEN_COMMIT}"
MANAGED_BY="Nix flake via system-manager (/opt/airplay-os)"
EOF

cat > "${ROOTFS_DIR}/etc/machine-info" <<EOF
PRETTY_HOSTNAME=AirPlay OS
CHASSIS=embedded
DEPLOYMENT=production
ICON_NAME=audio-speakers
EOF

cat > "${ROOTFS_DIR}/etc/update-motd.d/10-airplay-os" <<'EOF'
#!/bin/sh
# AirPlay OS MOTD (image level; the flake's own MOTD replaces it at activation).
. /etc/airplay-os-release 2>/dev/null
ip4=$(ip -4 -o addr show dev wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
printf '\n  %s %s\n' "${PRETTY_NAME:-AirPlay OS}" "${VERSION:-}"
printf '  web ui   http://ampberry.local/%s\n' "${ip4:+   (${ip4})}"
printf '  manage   sudo airplay-os help · flake /opt/airplay-os · image %s %s\n\n' "${IMAGE_NAME:-}" "${IMAGE_DATE:-}"
EOF
chmod 755 "${ROOTFS_DIR}/etc/update-motd.d/10-airplay-os"

cat > "${ROOTFS_DIR}/etc/issue.d/airplay-os.issue" <<'EOF'
AirPlay OS — AirPlay 2 receiver · web ui: http://ampberry.local/
EOF
