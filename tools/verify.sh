#!/usr/bin/env bash
# Post-deploy verification of an AirPlay OS device over SSH. Read-only. Exit 1 if anything
# essential is off. The device tells us what it is (/etc/ampberry/device.json).
#   DEVICE=hifiberry tools/verify.sh        # default: ampberry; AMPBERRY_HOST overrides the ssh target
set -uo pipefail
DEVICE="${DEVICE:-ampberry}"
HOST="${AMPBERRY_HOST:-pi@${DEVICE}.local}"
ALIAS="${AMPBERRY_ALIAS:-${HOST#*@}}"
SSH=(ssh -o ConnectTimeout=10 -o HostKeyAlias="$ALIAS" "$HOST")
fail=0
check() { if "${SSH[@]}" "$2" >/dev/null 2>&1; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fail=1; fi; }

echo "== AirPlay OS verification ($HOST)"
dev="$("${SSH[@]}" 'cat /etc/ampberry/device.json 2>/dev/null' || echo '{}')"
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print("" if v is None else (str(v).lower() if isinstance(v,bool) else v))' "$dev" "$1"; }
id="$(field id)"; pretty="$(field pretty_name)"; wifi="$(field wifi)"; overlay="$(field overlay)"; iface="$(field primary_interface)"
[[ "$id" == "$DEVICE" ]] && echo "  device $id ($pretty) · ${iface}" || { echo "  FAIL device.json says '${id:-?}', expected '$DEVICE'"; fail=1; }
"${SSH[@]}" 'echo "  kernel $(uname -r) · up $(uptime -p | sed s/up\ //) · mem used $(free -m | awk "/Mem/{print \$3}") MB · nix store $(du -sh /nix/store 2>/dev/null | cut -f1)"'
units=(ampberry-firewall nqptp shairport-sync ampberry-metadata ampberry-control.socket ampberry-ui ampberry-health.timer ampberry-updates.timer avahi-daemon ssh)
[[ "$wifi" == true ]] && units+=(ampberry-wifi-fallback.timer)
for u in "${units[@]}"; do
	check "unit $u active" "systemctl is-active --quiet $u"
done
[[ "$wifi" == true ]] || check "no Wi-Fi fallback timer on an Ethernet-only device" '! systemctl list-unit-files ampberry-wifi-fallback.timer --no-legend 2>/dev/null | grep -q .'
check "no failed units" '[ -z "$(systemctl --failed --no-legend)" ]'
check "no HiFiBerry packages left" '[ "$(dpkg -l | grep -c -E "hifiberry|hbos")" = 0 ]'
check "shairport-sync 5.5.2 with AirPlay 2 + metadata" 'readlink -f /run/system-manager/sw/bin/shairport-sync | grep -q -- -5.5.2 && /run/system-manager/sw/bin/shairport-sync -V 2>&1 | grep -qi airplay2 && /run/system-manager/sw/bin/shairport-sync -V 2>&1 | grep -qi metadata'
check "nqptp 1.2.8" '/run/system-manager/sw/bin/nqptp -V 2>&1 | grep -q 1.2.8'
check "nftables ruleset loaded (table inet ampberry)" 'sudo nft list table inet ampberry'
check "sshd: password auth off, root login off" 'sudo sshd -T | grep -q "^passwordauthentication no" && sudo sshd -T | grep -q "^permitrootlogin no"'
check "ampberry user has no shell and no sudo" '[ "$(getent passwd ampberry | cut -d: -f7)" = /usr/sbin/nologin ] && ! sudo -l -U ampberry 2>/dev/null | grep -q "may run"'
check "control socket root:ampberry 0660" '[ "$(stat -c %U:%G:%a /run/ampberry-control.sock)" = root:ampberry:660 ]'
check "web UI renders /settings" 'curl -fsS -o /dev/null http://localhost/settings'
check "web UI answers /health" 'curl -fsS http://localhost/health | grep -q "\"ok\":true"'
check "now-playing snapshot present" 'test -s /run/ampberry/now-playing.json'
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
