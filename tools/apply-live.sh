#!/usr/bin/env bash
# Migrate the running Ampberry (HiFiBerry OS NG) to the Nix-managed AirPlay 2 stack, in place —
# no re-flash. Interactive: every destructive step asks first. Run from the Mac.
#
#   tools/apply-live.sh --harvest        # 1st time: pull pi's SSH keys + password hash into build/
#   tools/apply-live.sh                  # the migration: build on the nix-darwin linux-builder,
#                                        #   push with `system-manager switch --target-host`
#   tools/apply-live.sh --from-switch    # resume after a failed switch: skip backup/purge/Nix install
#
# Steps: preflight → backup (scp'd off the device) → stop hbos units → purge hbos → install Nix →
# copy flake to /opt/ampberry → system-manager switch → ampberry provision → install the
# cloud-init seed for Clean reboot → reboot → verify.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-ampberry}"            # systemConfigs.<id> in flake.nix = devices/<id>.json
HOST="${AMPBERRY_HOST:-pi@${DEVICE}.local}"
ALIAS="${AMPBERRY_ALIAS:-${HOST#*@}}"
SSH=(ssh -o ConnectTimeout=10 -o HostKeyAlias="$ALIAS" "$HOST")
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="build/apply-${STAMP}.log"
HARVEST=0
FROM_SWITCH=0
for a in "$@"; do
	case "$a" in
	--harvest) HARVEST=1 ;;
	--from-switch) FROM_SWITCH=1 ;;
	-h | --help) sed -n '2,12p' "$0"; exit 0 ;;
	*) echo "unknown option $a" >&2; exit 2 ;;
	esac
done
mkdir -p build
exec > >(tee -a "$LOG") 2>&1

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
confirm() { if [[ "${ASSUME_YES:-0}" == 1 ]]; then echo "$1 [auto-yes]"; return; fi; read -r -p "$1 [y/N] " ans; [[ "$ans" == y* ]] || { echo "aborted"; exit 1; }; }
remote() { "${SSH[@]}" "$@"; }

HBOS_PKGS=(hbos-full hbos-minimal hifiberry-analog-recognition hifiberry-audiocontrol hifiberry-auth
	hifiberry-bluetooth hifiberry-configurator hifiberry-dsp hifiberry-dspprofiles hifiberry-eeprom
	hifiberry-input-processor hifiberry-librespot hifiberry-mpd hifiberry-pipewire-configs hifiberry-raat
	hifiberry-sendspin hifiberry-shairport hifiberry-squeezelite hifiberry-vu-meter hifiberry-webui
	ladspa-speakereq pipewire-api pipewire pipewire-pulse pipewire-alsa wireplumber rpi-connect-lite)
HBOS_USER_UNITS=(shairport librespot mpd raat squeezelite sendspin vu-meter pipewire-api filter-chain
	wireplumber pipewire pipewire-pulse mpris-proxy analog-recognition)

# ---- harvest: device facts into build/secrets.harvested.env (gitignored) -------------------------
if [[ $HARVEST == 1 ]]; then
	say "harvesting SSH keys, password hash and network-config from $HOST"
	[[ -f secrets.env ]] || { echo "secrets.env missing (copy secrets.env.example)"; exit 1; }
	keys="$(remote 'cat ~/.ssh/authorized_keys' | grep -E '^(ssh-|ecdsa-|sk-)' || true)"
	hash="$(remote 'sudo getent shadow pi | cut -d: -f2')"
	remote 'sudo cat /boot/firmware/network-config' > build/network-config.device
	{
		grep -vE '^(SSH_AUTHORIZED_KEYS|PI_PASSWORD_HASH)=' secrets.env
		printf "SSH_AUTHORIZED_KEYS='%s'\n" "$keys"
		printf "PI_PASSWORD_HASH='%s'\n" "$hash"
	} > build/secrets.harvested.env
	chmod 600 build/secrets.harvested.env build/network-config.device
	echo "wrote build/secrets.harvested.env ($(printf '%s\n' "$keys" | grep -c . ) key(s), hash $( [[ -n $hash && $hash != '!'* && $hash != '*' ]] && echo present || echo locked)) and build/network-config.device"
	exit 0
fi

SECRETS=build/secrets.harvested.env
[[ -f $SECRETS ]] || { echo "run tools/apply-live.sh --harvest first"; exit 1; }

# ---- 1. preflight -------------------------------------------------------------------------------
say "preflight ($HOST)"
remote 'echo "kernel $(uname -r), $(uptime -p)"; echo "cloud-init $(cloud-init --version 2>&1 | head -1)"; df -h / | tail -1'
if [[ "$(remote 'ss -tnH state established "( sport = :5000 or sport = :7000 )" | wc -l')" != "0" ]]; then
	echo "AirPlay session in progress on the device."; confirm "Continue anyway (playback will stop)?"
fi
say "rendering the cloud-init seed"
nix shell nixpkgs#ruby_3_4 --command ruby tools/build-user-data.rb --out build --secrets "$SECRETS"
cp build/network-config.device build/network-config # byte-identical to the running profile (netplan/NM)

if [[ $FROM_SWITCH == 0 ]]; then
# ---- 2. backup --------------------------------------------------------------------------------
say "backup"
remote "sudo tar czf /home/pi/backup-pre-nix-${STAMP}.tgz /etc/audiocontrol /etc/pipewire /etc/avahi /etc/ssh/sshd_config.d \
	/etc/apt/sources.list.d /etc/apt/apt.conf.d /boot/firmware/config.txt /boot/firmware/user-data /boot/firmware/network-config \
	/boot/firmware/meta-data /home/pi/.state /home/pi/.shairport /home/pi/.local/state/wireplumber 2>/dev/null; \
	dpkg --get-selections > /home/pi/dpkg-selections-${STAMP}.txt; apt-mark showmanual > /home/pi/apt-manual-${STAMP}.txt"
scp -q -o HostKeyAlias="$ALIAS" "$HOST:/home/pi/backup-pre-nix-${STAMP}.tgz" "$HOST:/home/pi/dpkg-selections-${STAMP}.txt" "$HOST:/home/pi/apt-manual-${STAMP}.txt" build/
ls -la build/backup-pre-nix-"${STAMP}".tgz

# ---- 3. stop hbos ---------------------------------------------------------------------------------
say "stop HiFiBerry OS user units + linger"
confirm "Stop and disable the hbos user services now (audio stops)?"
remote "systemctl --user disable --now ${HBOS_USER_UNITS[*]} 2>/dev/null || true; sudo loginctl disable-linger pi || true"

# ---- 4. purge -------------------------------------------------------------------------------------
say "purge HiFiBerry OS packages"
installed="$(remote "dpkg-query -W -f='\${Package} ' ${HBOS_PKGS[*]} 2>/dev/null" || true)"
echo "to purge: $installed"
confirm "Purge these packages, autoremove, drop the HiFiBerry apt source?"
remote "sudo DEBIAN_FRONTEND=noninteractive apt-get -y purge $installed && sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge && \
	sudo rm -f /etc/apt/sources.list.d/hifiberry.list /usr/share/keyrings/hifiberry-archive-keyring.gpg && sudo apt-get update -qq && \
	sudo DEBIAN_FRONTEND=noninteractive apt-get -y install curl ca-certificates avahi-daemon avahi-utils alsa-utils"

# ---- 5. Nix + users ----------------------------------------------------------------------------------
say "Nix (Determinate installer) and runtime users"
remote 'test -x /nix/var/nix/profiles/default/bin/nix || { curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix -o /tmp/nix-installer.sh && sudo sh /tmp/nix-installer.sh install linux --no-confirm --extra-conf "experimental-features = nix-command flakes" --extra-conf "trusted-users = root pi" && rm -f /tmp/nix-installer.sh; }; \
	grep -q "^trusted-users" /etc/nix/nix.custom.conf || { echo "trusted-users = root pi" | sudo tee -a /etc/nix/nix.custom.conf >/dev/null; sudo systemctl restart nix-daemon.service; }; \
	sudo systemctl enable --now nix-daemon.socket 2>/dev/null || true; /nix/var/nix/profiles/default/bin/nix --version'
# pi must be a trusted user: `system-manager switch --target-host` copies unsigned, locally built
# paths into the Pi's store as pi (`nix copy --to ssh://`); the daemon rejects them otherwise.
remote 'getent passwd shairport-sync >/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin --groups audio --comment "Shairport Sync" shairport-sync; \
	getent passwd ampberry >/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin --groups audio --comment "Ampberry web UI" ampberry; \
	sudo install -d -m 0750 -o root -g ampberry /var/lib/ampberry; sudo install -d -m 0755 /var/log/ampberry /etc/ampberry'

# ---- 6. (no source copy) ---------------------------------------------------------------------------
# The flake source travels inside the system closure (tmpfiles links /opt/ampberry into the store).
fi # FROM_SWITCH

# ---- 7. switch -------------------------------------------------------------------------------------
say "system-manager switch (built on the linux-builder, pushed with --target-host)"
# git-based flake reference: self is git-filtered (build/, secrets never enter the store)
nix run github:numtide/system-manager/release-26.05 -- switch --flake ".#${DEVICE}" --target-host "$HOST" --sudo
# Record what is live, for Clean reboot / Redeploy. The system-manager CLI ships inside the closure
# (environment.systemPackages), so nothing gets built on the Pi.
remote 'sm=$(readlink -f /run/system-manager/sw/bin/system-manager); echo "${sm%/bin/system-manager}" | sudo tee /etc/ampberry/system-manager-path >/dev/null; \
	readlink -f /nix/var/nix/profiles/system-manager-profiles/system-manager | sudo tee /etc/ampberry/system-path'

# ---- 8. provision + seed --------------------------------------------------------------------------------
say "ampberry provision"
remote 'sudo /run/system-manager/sw/bin/ampberry provision'
say "install the cloud-init seed for Clean reboot"
# scp on purpose: the seed carries the Wi-Fi PSK and pi's password hash, which must never enter the
# (world-readable) Nix store — this is the one transfer that does not go through Nix.
scp -q -o HostKeyAlias="$ALIAS" build/user-data build/network-config build/meta-data "$HOST:/tmp/"
remote 'sudo install -m 0644 /tmp/user-data /tmp/network-config /tmp/meta-data /boot/firmware/ && rm -f /tmp/user-data /tmp/network-config /tmp/meta-data'

# ---- 9. reboot + verify ----------------------------------------------------------------------------
say "reboot"
confirm "Reboot now (activates kernel 6.18.50 and the device-tree change)?"
remote 'sudo systemctl reboot' || true
echo "waiting for $HOST ..."
for _ in $(seq 1 60); do sleep 5; "${SSH[@]}" -o ConnectTimeout=5 true 2>/dev/null && break; done
tools/verify.sh
say "done — log: $LOG"
