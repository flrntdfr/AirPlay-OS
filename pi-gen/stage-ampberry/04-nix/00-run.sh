#!/bin/bash -e
# Install Nix into the image and pre-build the Ampberry system closure, so first boot only
# activates (no compiling on the Pi 3). Runs inside pi-gen's arm64 chroot (native on Apple
# Silicon). Activation itself needs a running systemd, so it is done at first boot by
# cloud-init's runcmd (see cloud-init/user-data.tmpl): system-manager switch --store-path.
#
# Determinate nix-installer with --init none: multi-user layout (build users, /nix, nix.conf)
# without a daemon — the daemon unit is wired up below for the real boot.


# users the systemd units run as (created here so activation at first boot has them)
on_chroot <<'EOF'
getent group shairport-sync >/dev/null || groupadd -r shairport-sync
getent passwd shairport-sync >/dev/null || useradd -r -M -g shairport-sync -G audio -s /usr/sbin/nologin -c 'Shairport Sync' shairport-sync
getent group ampberry >/dev/null || groupadd -r ampberry
getent passwd ampberry >/dev/null || useradd -r -M -g ampberry -G audio -s /usr/sbin/nologin -c 'Ampberry web UI' ampberry
install -d -m 0750 -o root -g ampberry /var/lib/ampberry
install -d -m 0755 /var/log/ampberry
EOF

# Nix (no daemon in the chroot; sandbox off because user namespaces are unavailable here)
on_chroot <<'EOF'
set -e
if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
	curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix -o /tmp/nix-installer.sh
	sh /tmp/nix-installer.sh install linux --init none --no-confirm \
		--extra-conf "sandbox = false" \
		--extra-conf "experimental-features = nix-command flakes" \
		--extra-conf "trusted-users = root pi"
	rm -f /tmp/nix-installer.sh
fi
EOF

# Build the system closure + the system-manager CLI, keep them as GC roots, record their paths
on_chroot <<EOF
set -e
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
export PATH=/nix/var/nix/profiles/default/bin:\$PATH
export NIX_REMOTE=
install -d /nix/var/nix/gcroots /etc/ampberry
nix build --no-link --print-out-paths "path:/usr/local/src/ampberry#systemConfigs.ampberry" > /etc/ampberry/system-path
# the system-manager CLI is part of the closure (environment.systemPackages): record it from there
sw=\$(nix-store -qR "\$(cat /etc/ampberry/system-path)" | grep -- '-system-manager-path\$' | head -1)
sm=\$(readlink -f "\$sw/bin/system-manager"); echo "\${sm%/bin/system-manager}" > /etc/ampberry/system-manager-path
ln -sfn "\$(cat /etc/ampberry/system-manager-path)" /nix/var/nix/gcroots/ampberry-system-manager
ln -sfn "\$(cat /etc/ampberry/system-path)" /nix/var/nix/gcroots/ampberry-system
nix-collect-garbage -d >/dev/null
nix store optimise 2>/dev/null || true
echo "system closure: \$(cat /etc/ampberry/system-path)"
du -sh /nix/store
EOF

# Daemon for the real boot: use the units shipped by the installed Nix profile.
on_chroot <<'EOF'
set -e
P=/nix/var/nix/profiles/default
for u in nix-daemon.service nix-daemon.socket; do
	[ -e "$P/lib/systemd/system/$u" ] && ln -sfn "$P/lib/systemd/system/$u" "/etc/systemd/system/$u"
done
systemctl enable nix-daemon.socket
EOF

log "nix + ampberry system closure baked into the image"
