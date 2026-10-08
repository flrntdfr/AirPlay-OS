#!/bin/bash -e
# Branding baked into the image. Only files no Debian package owns are touched, so
# unattended-upgrades never meets a modified conffile (that would hold packages back):
#   /etc/ampberry-release      image-level provenance (the flake adds its own fields at activation)
#   /etc/machine-info          pretty hostname, chassis, deployment
#   /etc/update-motd.d/10-ampberry   dynamic MOTD (pam_motd runs update-motd.d on Debian)
#   /etc/issue.d/ampberry.issue      console login banner (agetty reads /etc/issue.d)

PI_GEN_COMMIT="$(git -C "${BASE_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

install -d -m 755 "${ROOTFS_DIR}/etc/ampberry" "${ROOTFS_DIR}/etc/update-motd.d" "${ROOTFS_DIR}/etc/issue.d"

cat > "${ROOTFS_DIR}/etc/ampberry-release" <<EOF
NAME="Ampberry"
PRETTY_NAME="Ampberry — AirPlay 2 speaker"
IMAGE_NAME="${IMG_NAME}${IMG_SUFFIX:--lite}"
IMAGE_DATE="${IMG_DATE}"
BASE="Raspberry Pi OS Lite (${RELEASE}), pi-gen ${PI_GEN_COMMIT}"
MANAGED_BY="Nix flake via system-manager (/opt/ampberry)"
EOF

cat > "${ROOTFS_DIR}/etc/machine-info" <<EOF
PRETTY_HOSTNAME=Ampberry
CHASSIS=embedded
DEPLOYMENT=production
ICON_NAME=audio-speakers
EOF

cat > "${ROOTFS_DIR}/etc/update-motd.d/10-ampberry" <<'EOF'
#!/bin/sh
# Ampberry MOTD — minimal on purpose.
. /etc/ampberry-release 2>/dev/null
ip4=$(ip -4 -o addr show dev wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
printf '\n  %s\n' "${PRETTY_NAME:-Ampberry}"
printf '  web ui   http://ampberry.local/%s\n' "${ip4:+   (${ip4})}"
printf '  manage   sudo ampberry help · flake /opt/ampberry · image %s %s\n\n' "${IMAGE_NAME:-}" "${IMAGE_DATE:-}"
EOF
chmod 755 "${ROOTFS_DIR}/etc/update-motd.d/10-ampberry"

cat > "${ROOTFS_DIR}/etc/issue.d/ampberry.issue" <<'EOF'
Ampberry — AirPlay 2 speaker · web ui: http://ampberry.local/
EOF
