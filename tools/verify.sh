#!/usr/bin/env bash
# Post-deploy verification of an AirPlay OS device over SSH. Read-only. Exit 1 if anything
# essential is off. The device tells us what it is (/etc/airplay-os/device.json).
#   DEVICE=hifiberry tools/verify.sh        # default: ampberry; AIRPLAY_OS_HOST overrides the ssh target
set -uo pipefail
DEVICE="${DEVICE:-ampberry}"
HOST="${AIRPLAY_OS_HOST:-pi@${DEVICE}.local}"
ALIAS="${AIRPLAY_OS_ALIAS:-${HOST#*@}}"
SSH=(ssh -o ConnectTimeout=10 -o HostKeyAlias="$ALIAS" "$HOST")
fail=0
check() { if "${SSH[@]}" "$2" >/dev/null 2>&1; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fail=1; fi; }

echo "== AirPlay OS verification ($HOST)"
dev="$("${SSH[@]}" 'cat /etc/airplay-os/device.json 2>/dev/null' || echo '{}')"
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print("" if v is None else (str(v).lower() if isinstance(v,bool) else v))' "$dev" "$1"; }
id="$(field id)"; pretty="$(field pretty_name)"; wifi="$(field wifi)"; overlay="$(field overlay)"; iface="$(field primary_interface)"
[[ "$id" == "$DEVICE" ]] && echo "  device $id ($pretty) · ${iface}" || { echo "  FAIL device.json says '${id:-?}', expected '$DEVICE'"; fail=1; }
"${SSH[@]}" 'echo "  kernel $(uname -r) · up $(uptime -p | sed s/up\ //) · mem used $(free -m | awk "/Mem/{print \$3}") MB · nix store $(du -sh /nix/store 2>/dev/null | cut -f1)"'
units=(airplay-os-firewall nqptp shairport-sync airplay-os-metadata airplay-os-control.socket airplay-os-ui airplay-os-health.timer airplay-os-updates.timer avahi-daemon ssh)
[[ "$wifi" == true ]] && units+=(airplay-os-wifi-fallback.timer)
for u in "${units[@]}"; do
	check "unit $u active" "systemctl is-active --quiet $u"
done
[[ "$wifi" == true ]] || check "no Wi-Fi fallback timer on an Ethernet-only device" '! systemctl list-unit-files airplay-os-wifi-fallback.timer --no-legend 2>/dev/null | grep -q .'
check "no failed units" '[ -z "$(systemctl --failed --no-legend)" ]'
check "no HiFiBerry packages left" '[ "$(dpkg -l | grep -c -E "hifiberry|hbos")" = 0 ]'
check "shairport-sync 5.5.2 with AirPlay 2 + metadata" 'readlink -f /run/system-manager/sw/bin/shairport-sync | grep -q -- -5.5.2 && /run/system-manager/sw/bin/shairport-sync -V 2>&1 | grep -qi airplay2 && /run/system-manager/sw/bin/shairport-sync -V 2>&1 | grep -qi metadata'
check "nqptp 1.2.8" '/run/system-manager/sw/bin/nqptp -V 2>&1 | grep -q 1.2.8'
check "nftables ruleset loaded (table inet airplay-os)" 'sudo nft list table inet airplay-os'
check "sshd: password auth off, root login off" 'sudo sshd -T | grep -q "^passwordauthentication no" && sudo sshd -T | grep -q "^permitrootlogin no"'
check "airplay-os user has no shell and no sudo" '[ "$(getent passwd airplay-os | cut -d: -f7)" = /usr/sbin/nologin ] && ! sudo -l -U airplay-os 2>/dev/null | grep -q "may run"'
check "control socket root:airplay-os 0660" '[ "$(stat -c %U:%G:%a /run/airplay-os-control.sock)" = root:airplay-os:660 ]'
check "web UI renders /settings" 'curl -fsS -o /dev/null http://localhost/settings'
check "web UI answers /health" 'curl -fsS http://localhost/health | grep -q "\"ok\":true"'
check "now-playing snapshot present" 'test -s /run/airplay-os/now-playing.json'
check "mDNS: _airplay._tcp announced as $pretty" "timeout 8 avahi-browse -rt _airplay._tcp 2>/dev/null | grep -q '$pretty'"
check "HAT on hw:0" 'aplay -l | grep -q snd_rpi_hifiberry'
if [[ -n "$overlay" ]]; then
	check "config.txt: $overlay overlay" "grep -q '^dtoverlay=$overlay' /boot/firmware/config.txt"
else
	check "config.txt: no HAT overlay line (EEPROM detection)" '! grep -q "^dtoverlay=hifiberry" /boot/firmware/config.txt'
fi
check "config.txt: bluetooth off" 'grep -q "^dtoverlay=disable-bt" /boot/firmware/config.txt'
[[ "$wifi" == true ]] || check "config.txt: wifi off" 'grep -q "^dtoverlay=disable-wifi" /boot/firmware/config.txt'
echo "  listening:"
"${SSH[@]}" 'sudo ss -ltnup 2>/dev/null | awk "NR>1{print \"    \" \$1, \$5, \$7}" | sed -E "s/users:\(\(\"([^\"]+)\".*/\1/" | sort -u'
if [[ $fail == 0 ]]; then echo "== all checks passed"; else echo "== some checks FAILED"; exit 1; fi
