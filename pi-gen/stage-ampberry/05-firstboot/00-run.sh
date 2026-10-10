#!/bin/bash -e
# First boot without a cloud-init seed of our own (the public, secret-free image): a oneshot
# unit activates the system closure baked by 04-nix and runs `ampberry provision`, once. The
# Raspberry Pi Imager's customization (user, SSH key, Wi-Fi, hostname) keeps working, because it
# writes its own cloud-init user-data and we no longer need that file. A personal image rendered
# with a seed (tools/build-image.sh with SECRETS) activates from cloud-init's runcmd instead; the
# script below is idempotent, so both can be present.
install -d -m 755 "${ROOTFS_DIR}/usr/local/sbin" "${ROOTFS_DIR}/etc/systemd/system" "${ROOTFS_DIR}/etc/ampberry"

cat > "${ROOTFS_DIR}/usr/local/sbin/airplay-os-firstboot" <<'EOF'
#!/bin/sh
# AirPlay OS first boot: activate the pre-built system closure, provision, mark done.
set -eu
export PATH=/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
marker=/var/lib/ampberry/activated
[ -e "$marker" ] && exit 0
if [ ! -e /run/system-manager/sw/bin/ampberry ]; then
	sm="$(cat /etc/ampberry/system-manager-path)"
	"$sm/bin/system-manager" switch --store-path "$(cat /etc/ampberry/system-path)"
fi
# the onboarding hotspot needs a passphrase; a public image ships a known default (change it in
# Settings or /etc/ampberry/secrets.json)
[ -s /etc/ampberry/secrets.json ] || { umask 077; printf '{"setup_psk": "airplay-os"}\n' > /etc/ampberry/secrets.json; }
/run/system-manager/sw/bin/ampberry provision || true
install -d -m 0750 -o root -g ampberry /var/lib/ampberry
touch "$marker"
EOF
chmod 0755 "${ROOTFS_DIR}/usr/local/sbin/airplay-os-firstboot"

cat > "${ROOTFS_DIR}/etc/systemd/system/airplay-os-firstboot.service" <<'EOF'
[Unit]
Description=AirPlay OS first boot (activate the baked system, provision)
ConditionPathExists=!/var/lib/ampberry/activated
After=nix-daemon.socket network.target NetworkManager.service
Wants=nix-daemon.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/airplay-os-firstboot
TimeoutStartSec=30min

[Install]
WantedBy=multi-user.target
EOF

on_chroot <<'EOF'
systemctl enable airplay-os-firstboot.service
EOF
log "first-boot activation unit installed"
