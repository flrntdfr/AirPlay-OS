# Operations Log

A dated record of operational actions performed on the devices — updates, restarts, config
changes, fixes. Newest entries first. See [`AGENTS.md`](./AGENTS.md) for why this exists and what
belongs here.

## 2026-07-24 — Package upgrade: Ampberry

Ran `sudo apt-get update && apt-get upgrade` (non-interactive, `--force-confold` to preserve local
config edits). Pre-check: both devices idle (MPD stopped, no active player), so a safe time to
touch the stack.

**Installed (100 packages):**
- HiFiBerry stack: `hifiberry-audiocontrol` 0.7.12 → 0.8.3, `hifiberry-dsp` 1.3.11 → 1.3.12,
  `hifiberry-bluetooth` 1.0.3 → 1.0.5, `hifiberry-configurator` 2.13.14 → 2.14.4,
  `hifiberry-librespot` 0.8.0.3 → 0.8.0.6, `hifiberry-shairport` 5.0.1.3 → 5.1.0.2,
  `hifiberry-squeezelite` 2.0.0.1559 → 2.0.0.1561, `hifiberry-vu-meter` 0.1.1 → 0.1.2,
  `hbos-minimal` 0.9 → 0.11.
- ~90 Debian security/base packages (libc6, openssl, gpg, samba libs, python3.13, libav*, etc.) —
  routine, no notable issues.

**Held back by plain `upgrade`** (would require adding/removing packages, so `apt upgrade` skips
them by design): `hbos-full`, `hifiberry-webui`, `hifiberry-mpd`, `hifiberry-pipewire-configs`,
plus the kernel meta-packages (`linux-image-rpi-v8`/`rpi-2712`, headers, base) still on 6.18.33.

Simulated (`apt-get dist-upgrade -s`) what completing the upgrade would do: **removes
`ladspa-riaa`** (the RIAA phono-preamp plugin this repo's docs reference in the filter-chain
config), installs **75 new packages** — GTK4/libadwaita, ffmpeg, gstreamer, pocketsphinx (speech
recognition), `songrec` (audio fingerprinting/song-ID), plus new HiFiBerry components
(`hifiberry-auth`, `hifiberry-input-processor`, `hifiberry-sendspin`,
`hifiberry-analog-recognition`) — and bumps the kernel to 6.18.34 (needs a reboot to take effect).
That's new feature surface, not a routine bump, and it touches a package the docs call out —
**paused here and went back to the user for an explicit decision** rather than assuming "perform
upgrade" covered it. See follow-up entry once decided.

**Post-upgrade actions:** `audiocontrol`, `config-server`, `sigmatcpserver` auto-restarted via
package postinst (confirmed via `ActiveEnterTimestamp`); `pipewire-api` and `vu-meter` **user**
services were left running the old binary after upgrade — restarted manually
(`systemctl --user restart pipewire-api vu-meter`).

**Verification:** no failed units (system or user), audio at unity gain (`wpctl status` → Built-in
Audio Stereo `vol: 1.00`), AudioControl players endpoint responding normally (all idle, as
expected). No reboot required for what was actually installed (kernel packages were held back).

## 2026-07-24 — Package upgrade: HifiBerry

Same treatment as Ampberry, same session: `sudo apt-get update && apt-get upgrade` (non-interactive,
`--force-confold`). Device idle beforehand (MPD stopped).

**Installed (81 packages):** same HiFiBerry-stack bump as Ampberry (`hifiberry-audiocontrol`
0.7.13 → 0.8.3, `hifiberry-dsp` → 1.3.12, `hifiberry-bluetooth` → 1.0.5, `hifiberry-configurator`
2.13.16 → 2.14.4, `hifiberry-librespot` 0.8.0.4 → 0.8.0.6, `hifiberry-shairport` → 5.1.0.2,
`hifiberry-squeezelite` → 2.0.0.1561, `hifiberry-vu-meter` → 0.1.2, `hbos-minimal` 0.9 → 0.11) plus
~70 Debian security/base packages. No kernel packages in the list this time — this unit was already
on 6.18.34.

**Held back:** `hbos-full`, `hifiberry-webui`, `hifiberry-mpd`, `hifiberry-pipewire-configs` — same
as Ampberry, same reason. Not simulated separately; same `dist-upgrade` tradeoffs apply (see
Ampberry entry above) — decision pending with the user for both devices together.

**Issue hit:** `config-server.service` came up **failed** (`start-limit-hit`) right after the
upgrade. Journal showed the service actually started cleanly and bound to port 1081, then was
*stopped* (not crashed) — almost certainly another package's postinst restarting it again in the
same few-second window, tripping systemd's default restart-rate-limit on the next start attempt.
Fixed with `sudo systemctl reset-failed config-server && sudo systemctl start config-server`;
confirmed active and responding on :1081 afterward. Worth knowing for future multi-package
HiFiBerry-stack upgrades on either device — check `systemctl --failed` after and clear/restart
anything caught by this.

**Post-upgrade actions:** `audiocontrol`/`config-server`/`sigmatcpserver` restarted via postinst
(config-server needed the manual kick above); `pipewire-api` and `vu-meter` user services left on
old binaries, restarted manually.

**Verification:** no failed units after the fix, audio at unity gain (`vol: 1.00`), AudioControl
players endpoint responding normally, no reboot required.

## 2026-07-24 — Full stack upgrade (hbos 0.9 → 0.11) + reboot: HifiBerry

Follow-up to the held-back packages above. User (on Opus 4.8) explicitly authorized the full
upgrade **and reboots**, which covers the two things previously paused on: the `ladspa-riaa`
removal / new-package surface, and the reboot.

Ran `sudo apt-get full-upgrade` (non-interactive, `--force-confold`): **4 upgraded, 67 new, 1
removed** (72 MB). HifiBerry was already on kernel 6.18.34, so **no kernel change** here — the
reboot was a clean-state restart, not required for a kernel.

- **Upgraded:** `hbos-full` 0.9 → 0.11, `hifiberry-webui` 0.19.11 → 0.20.3, `hifiberry-mpd`
  0.24.8.3 → 0.24.13.1, `hifiberry-pipewire-configs` 1.0.7 → 1.0.10.
- **New HiFiBerry components (hbos 0.11):** `hifiberry-auth` 0.1.2, `hifiberry-input-processor`
  1.3.1, `hifiberry-sendspin` 0.1.1, `hifiberry-analog-recognition` 0.2.3 (adds an "analog" +
  "sendspin" player; brings in GTK4/libadwaita, ffmpeg, gstreamer, pocketsphinx, `songrec` as
  deps — ~67 new packages total).
- **Removed:** `ladspa-riaa` (RIAA phono-preamp LADSPA plugin). This was a **coordinated** change:
  the new `hifiberry-pipewire-configs` 1.0.10 also **dropped `90-riaa.conf`** from
  `/etc/pipewire/pipewire.conf.d/`, so nothing references the plugin anymore. The Speaker EQ
  (`90-speakereq.conf` / `speakereq2x2.so`) — the filter actually in the streaming path — is
  untouched and remained the default sink throughout. Upstream has evidently retired the built-in
  RIAA filter chain. **Note:** the `ladspa-riaa` package is in `rc` state and its
  `/usr/lib/ladspa/riaa.so` was left orphaned on disk (harmless — unreferenced); not purged.

**RIAA docs impact:** both device docs describe a `90-riaa.conf` RIAA phono-preamp filter that no
longer exists after this upgrade. Docs updated to reflect removal.

**Reboot:** `systemctl reboot` at 14:56:45, SSH back ~44 s later. Post-reboot verification: kernel
6.18.34, all system + user services active, **no failed units**, `filter-chain` active with
`speakereq2x2` as default sink, **unity gain 1.00** intact, WebUI HTTP 200, AudioControl serving 7
players (`analog`, `lms`, `mpd`, `raat`, `sendspin`, `shairport`, `spotify`).
`analog-recognition.service` cleanly **skips via `exec-condition`** (no analog-input hardware on a
line-out DAC+) — inactive by design, not a failure.

## 2026-07-24 — Full stack upgrade (hbos 0.9 → 0.11) + kernel + reboot: Ampberry

Same operation as HifiBerry above, on Ampberry (Pi 3 / Wi-Fi). `sudo apt-get full-upgrade`
(non-interactive, `--force-confold`): **10 upgraded, 75 new, 1 removed** (149 MB — larger than
HifiBerry because this device *also* got the **kernel bump 6.18.33 → 6.18.34** + firmware, which
HifiBerry was already past).

- **Upgraded / new / removed:** identical set to HifiBerry — `hbos-full` 0.9 → 0.11,
  `hifiberry-webui` 0.19.11 → 0.20.3, `hifiberry-mpd` → 0.24.13.1, `hifiberry-pipewire-configs`
  1.0.6 → 1.0.10; new `hifiberry-auth` / `-input-processor` / `-sendspin` / `-analog-recognition`
  (+ GTK4/ffmpeg/gstreamer/pocketsphinx/songrec deps); `ladspa-riaa` removed with `90-riaa.conf`
  dropped by the new configs package (Speaker EQ untouched). `riaa.so` left orphaned (`rc` state).
- **Kernel:** `linux-image-rpi-v8` / `-2712` 6.18.33 → 6.18.34 unpacked and staged; running kernel
  switched on reboot (see below).

**Reboot (required — kernel):** `systemctl reboot` at 15:03:06, SSH back ~74 s later (Wi-Fi + Pi 3
reassociation, a bit slower than HifiBerry's Ethernet). Post-reboot verification: **running kernel
now 6.18.34**, all system + user services active, **no failed units**, `filter-chain` active with
`speakereq2x2` default sink, **unity gain 1.00** intact (the historically-sensitive control on this
device — see "Volume / loudness gotcha"), WebUI HTTP 200, AudioControl serving the same 7 players.
`analog-recognition` self-skips via `exec-condition` (Amp2 has no analog-input ADC either).

**Verification method:** confirmed via ALSA/PipeWire routing + node gain (`wpctl`) + AudioControl
API rather than playing a live test tone — a tone here would drive the Amp2 → speakers directly and
risk a loud surprise in the room. Routing/gain/API all consistent with clean unity-gain output.

### Net result — both devices
Both Ampberry and HifiBerry now on: `hbos-full` 0.11, `hifiberry-audiocontrol` 0.8.3,
`hifiberry-webui` 0.20.3, `hifiberry-mpd` 0.24.13.1, kernel 6.18.34, fully patched Debian. All
HiFiBerry-stack + Debian updates that were pending at the start of the session are now applied.
Nothing left held back.

## 2026-10-08 — Full stack upgrade (hbos 0.11 → 0.14) + kernel staged: Ampberry

Triggered while troubleshooting "volume saturates and the sound stops" (software gain chain verified
clean: DAC node 1.00, Speaker EQ flat, `Digital` ≤ 0 dB; the cut-out is amp headroom — a
`volume_max_db` ceiling is the fix, not more software). Ran `apt-get full-upgrade`
(non-interactive, `--force-confold`) as a detached `systemd-run` unit so an SSH drop could not kill dpkg.

**Upgraded (161 packages):** `hbos-full`/`hbos-minimal` 0.11 → **0.14**, `hifiberry-audiocontrol`
0.8.3 → **0.21.0**, `hifiberry-webui` 0.20.3 → 0.27.0, `hifiberry-configurator` 2.14.4 → 2.18.0,
`hifiberry-shairport` 1:5.1.0.2 → 1:5.5.0.1, `hifiberry-librespot` 0.8.0.6 → 0.8.0.15,
`hifiberry-mpd` 0.24.13.1 → 0.24.13.6, `hifiberry-dsp` 1.3.12 → 1.5.5, `hifiberry-bluetooth`
1.0.5 → 1.0.8, `ladspa-speakereq` 1.1 → 1.2, `pipewire-api` 2.1.3 → 2.2.0, kernel
`linux-image-rpi-v8` 6.18.34 → **6.18.50** (new package names, hence `full-upgrade`),
`raspi-firmware` 1.20260521 → 1.20260915, ~120 Debian/RPi base packages.

**Issue hit:** the first run aborted on `hifiberry-audiocontrol_0.21.0.deb`: dpkg had to
deconfigure `hifiberry-bluetooth` 1.0.5 and its `prerm` does not accept the `deconfigure`
argument (upstream packaging bug, still present in 1.0.8). 158 packages were left unconfigured.
Resume: `apt-get -y -f full-upgrade` — by then `hifiberry-bluetooth` 1.0.8 was unpacked, so the
`Breaks: hifiberry-bluetooth (<< 1.0.6)` no longer required deconfiguring it. Second run `EXIT=0`.

**Post-upgrade state:** all system/user units active, no failed units, sink at unity (1.00), DAC on
`hw:0`, WebUI 200. Running kernel still 6.18.34; **6.18.50 staged, reboot pending**. Conffile
leftovers to review: `/etc/audiocontrol/{audiocontrol.json,players.d/librespot.json,players.d/shairport.json}.dpkg-dist`.
Also observed (pre-existing): `ble-provisioning.service` restarts every 30 s forever (its
`ExecStartPre` exits 1 when a network is present) and the journal is volatile (`Storage=volatile`
from a vendor drop-in). Backup: `/home/pi/backup-pre-hbos014-2026-10-08.tgz`.

**Decision taken the same day:** Ampberry will be rebuilt in place as a Nix-managed, AirPlay-2-only
appliance (see `ampberry-v2/README.md`); this upgrade leaves the hbos install consistent as the
fallback until the switch-over, which gets its own entry.

## 2026-10-08 — Ampberry rebuilt in place as a Nix-managed AirPlay 2 appliance (Ampberry v2)

Same evening as the hbos 0.14 upgrade; approved sequence run non-interactively from the Mac
(`ampberry-v2/tools/apply-live.sh`, `ASSUME_YES=1`, console log `ampberry-v2/build/apply-console.log`).
No flash: Raspberry Pi OS Lite stays as the base, everything above the kernel now comes from the
`ampberry-v2/` flake applied with system-manager. Design and security model: `ampberry-v2/README.md`,
new `Ampberry.md`.

**Preflight:** kernel 6.18.34 (6.18.50 staged from the earlier upgrade), uptime 4 h 55, 48 GB free.
**Harvested first** (`--harvest`, into gitignored `build/`): `pi`'s `authorized_keys` (2 keys), the
`pi` password hash, the live `network-config` (SSID + 64-hex PSK) — so the cloud-init seed reproduces
the current access exactly.

**Backup:** `build/backup-pre-nix-20261008-231116.tgz` (configs, `/boot/firmware/*`,
`dpkg --get-selections`, `apt-mark showmanual`, `hifiberry.list`), kept on the Mac.

**Removed from the device:** all hbos user units stopped/disabled, `loginctl disable-linger pi`;
`apt-get purge` of the HiFiBerry stack — `hbos-full`/`hbos-minimal` 0.14, `hifiberry-audiocontrol`
0.21.0, `hifiberry-webui` 0.27.0, `hifiberry-configurator` 2.18.0, `hifiberry-shairport` 1:5.5.0.1,
`hifiberry-librespot` 0.8.0.15, `hifiberry-mpd` 0.24.13.6, `hifiberry-dsp` 1.5.5,
`hifiberry-bluetooth` 1.0.8, `hifiberry-raat`, `-squeezelite`, `-sendspin`, `-vu-meter`,
`-analog-recognition`, `-input-processor`, `-auth`, `-pipewire-configs`, `ladspa-speakereq`,
`roomeq`, `pipewire`/`pipewire-pulse`/`wireplumber` 1.4.2, `pipewire-api` 2.2.0, `nginx`,
`rpi-connect-lite` — plus autoremove of their dependency tree (GTK/Mesa/X11/numpy…): **345 packages
removed, 51 purged with conffiles, ~1.15 GB freed**. HiFiBerry apt source + keyring dropped.
Kept from Debian: kernel/firmware, NetworkManager, avahi-daemon (+ `avahi-utils`, `alsa-utils`,
`curl` installed), cloud-init, ssh, unattended-upgrades.

**Added:** Determinate Nix **3.23.1** (Nix 2.35.2, multi-user daemon, store on the SD card); system
users `ampberry` and `shairport-sync` (nologin, no sudo); then `system-manager switch --flake
.#ampberry --target-host pi@192.168.178.221 --sudo` from the Mac (closure built on the nix-darwin
`linux-builder`, copied over SSH): shairport-sync **5.5.2** (AirPlay 2, `--with-metadata-pipe`),
nqptp **1.2.8**, `ampberry` Ruby tools 0.2.0, Rails 7.2 UI on :80, nftables LAN-only firewall,
keys-only sshd drop-in, branding. Then `sudo ampberry provision` (config.txt, users/dirs, UI secret,
avahi IPv4-only, sshd reload, hostname, settings → `/etc/shairport-sync.conf` with
`volume_max_db = -6`, leftovers cleanup), the cloud-init seed scp'd to `/boot/firmware`, reboot
into kernel **6.18.50**.

**Issue hit:** the first `system-manager switch --target-host` failed while copying the closure —
`cannot add path '…-ampberry.nft' because it lacks a signature by a trusted key`. The fresh
Determinate Nix had `trusted-users = root` only, and `nix copy --to ssh://pi@…` adds unsigned,
Mac-built paths as `pi`. Fix: `trusted-users = root pi` in `/etc/nix/nix.custom.conf` + restart
`nix-daemon` (now set by the installer `--extra-conf` in `apply-live.sh`, the cloud-init seed and
the pi-gen stage), then resumed with the new `tools/apply-live.sh --from-switch`.

**Issues hit on the first activation (fixed in the flake, re-switched the same evening):**
- the script's follow-up `nix build github:numtide/system-manager` *on the Pi* started compiling
  the Rust CLI from source (our closure pins system-manager to our nixpkgs, so the upstream hash
  isn't in any cache the Pi trusts) — killed; the CLI now ships inside the closure
  (`environment.systemPackages`, `/run/system-manager/sw/bin/system-manager`) and the recorded
  paths are derived from the live system. The dead `--build-on-device` mode was removed.
- `ampberry-wifi-fallback` failed with `nmcli: No such file or directory`: system-manager gives
  units a Nix-only PATH. The Ruby-tool units (`ampberry-control@`, `ampberry-log`,
  `ampberry-wifi-fallback`) now get `path = [ "/usr" ]` → `/usr/bin:/usr/sbin`.
- `ampberry-ui` failed at `CREDENTIALS` because `/var/lib/ampberry/ui-secret` is only created by
  `ampberry provision`, which runs after the switch. The unit now creates it itself
  (`ExecStartPre=+…` as root) so it no longer depends on provisioning order.
- system-manager 1.1 keeps its profile at `/nix/var/nix/profiles/system-manager-profiles/system-manager`
  (not `…/profiles/system-manager`); `redeploy.rb` and the script now look there first.
- Observed, harmless: shairport-sync started with the hbos leftover `/etc/shairport-sync.conf`
  (name "HiFiBerry", no ceiling) until provision rendered the new one.

**Found by `verify.sh` after the reboot, fixed with a fourth (plain) switch:**
- `/settings` returned 500: `Log` wrote its `[INFO]` lines to stdout, and in the socket-activated
  control handler stdout *is* the client socket, so the UI's JSON reply was prefixed with a log
  line. `Log` now writes to stderr (journal); test added.
- the live log only ever contained its own start line: the aggregator's `journalctl -u … + _TRANSPORT=kernel`
  is invalid (`"+" can only be used between terms`), so the child exited every 2 s. It now follows
  the whole journal as JSON and selects in Ruby; tests updated.
- the "shairport-sync 5.5.2" check grepped `-V`, but upstream's 5.5.2 tag still reports `5.5.1-…`;
  the check now uses the store path (`…-shairport-sync-5.5.2`, built from `refs/tags/5.5.2`).
- cosmetic: activation logged "error reloading" for the template `ampberry-control@.service`;
  `restartIfChanged = false` (instances always spawn from the new unit file).

**Verification (2026-10-08 23:41, kernel 6.18.50, 4th generation live):** `tools/verify.sh` — **all 23
checks passed**: all units active, no failed units, 0 HiFiBerry packages, shairport-sync 5.5.2
AirPlay2+metadata, nqptp 1.2.8, nftables table loaded, sshd keys-only/no root, `ampberry` nologin +
no sudo, control socket `root:ampberry 0660`, `/settings` 200 + `/health` ok, now-playing snapshot,
`_airplay._tcp` "Ampberry" announced on 192.168.178.221, HAT on `hw:0`, overlay + BT-off in
`config.txt`. Rendered conf: `service_type = "airplay2"`, `volume_max_db = -6.0`, metadata pipe.
Listening: 22, 80, 7000/tcp, 319–320, 5353/udp. RAM used ~255 MB (hbos: ~450 MB), Nix store 1.4 GB,
48 GB free. Live log streaming (ssh/airplay/kernel/control tags). **Listen-test by Florent pending**
(AirPlay 2 from iPhone; confirm no cut-out at phone max = −6 dB on `Digital`). Rollback: generations
1–3 in `/nix/var/nix/profiles/system-manager-profiles/`, hbos backup tarball on the Mac.

**23:49 — seed from `secrets.env` + UI tweak (generation 5).** Florent put the Wi‑Fi passphrase in
`ampberry-v2/secrets.env`; checked on the Pi that `wpa_passphrase` derives it to the live 64‑hex key
(match), re-harvested (SSH keys + `pi` hash still from the device), rendered and installed
`/boot/firmware/{user-data,network-config,meta-data}` (`cloud-init schema`: valid). No live network
change — the running NM profile is the same network. UI: the log backdrop now colours error lines
red (`--danger`) and warnings in the accent colour (keyword match in `log-backdrop.js`). Deployed
with a plain `system-manager switch`; `verify.sh` all green.

## 2026-10-09 — Ampberry web UI rebuilt on RubyUI (shadcn/ui for Rails); actions trimmed

Decisions (Florent): log backdrop on every page, Wi‑Fi tab removed from the nav (`/setup` stays
for the hotspot captive flow), Settings actions reduced to **Maintenance: Restart AirPlay ·
Re‑announce on the network** and **System: Redeploy · Reboot** (Clean reboot / reset-settings /
security-updates no longer in the UI — `sudo ampberry action run clean-reboot`,
`sudo unattended-upgrade -v`; `security-updates` removed from `actions.json`), UI stack = RubyUI.

**Changed in `ampberry-v2/ui`:** gems `phlex-rails` 2.4, `ruby_ui` 1.6, `tailwind_merge`,
`importmap-rails`, `stimulus-rails` (no Node anywhere: Tailwind 4 compiled by the Nix build with
nixpkgs `tailwindcss_4`, Stimulus pinned from the gem). Views are Phlex (`app/views/**/*.rb`),
RubyUI components generated into `app/components/ruby_ui/` (Button, Card, Input, Badge, Alert,
Switch, Separator, Typography, Collapsible, NativeSelect, AlertDialog, Form — none with CDN JS),
`Components::{Nav,Flash,ActionRow}`. Confirmations are AlertDialogs; the control call is made by
`actions.js` from `data-action-id`. Dark mode follows the phone (`.dark` toggled from
`prefers-color-scheme`). The bridge now rescues every control-side error (a page never 500s).
`ampberry-ui.nix` gained a build phase (Tailwind) and a check phase that renders `/`, `/settings`,
`/setup`, `/health`, `/api/actions`, `/api/log` through Rack at build time.

**Issue hit:** `bundle lock --update` pulled precompiled platform gems (`nokogiri-1.19.4-arm64-darwin`
…), and the Nix build of the `ruby`-platform gem then failed (`mini_portile2` missing). Fix: lock
restricted to the `ruby` platform (`bundle lock --remove-platform …`), `bundix -l` again. Also my
first Tailwind build step doubled the path (`--cwd ui` + `ui/…`).

**Deployed** with `system-manager switch --target-host` (generation 5, 01:00): `ampberry-ui` active
after ~14 s, pages on the Pi 3: `/` 0.18 s, `/settings` ~0.9–1.3 s, `/setup` 0.9 s, `/health`
0.04 s; Settings talks to the control socket and lists the four actions. `tools/verify.sh` — all
checks passed. RAM used 272 MB. Verified locally first in the browser at phone width (fake
now‑playing snapshot + generated cover via `.claude/launch.json`): player stage, settings form,
Collapsible "Advanced…", Reboot AlertDialog, Wi‑Fi page.

**Second pass (same night, Florent's review on the phone):** minimal high-contrast black/white
tokens, no gradients (log mask removed), no transitions; **home screen = the log**, full-screen and
scrollable back in time (follows the tail unless scrolled up; 2000 lines kept), player bar flush at
the bottom with a cover thumbnail that opens the artwork full-screen in a RubyUI `Dialog`
(native `<dialog>`), and a **play/pause** button: new `Ampberry::Remote` sends DACP commands to the
sender (`avahi-browse _dacp._tcp` → `iTunes_Ctrl_<dacp_id>`, `GET /ctrl-int/1/playpause` with the
`Active-Remote` token); the metadata parser now records `daid`/`acre`; the UI unit got Debian's
PATH for `avahi-browse`. Settings: −/+ stepper (Stimulus `stepper_controller`) for max volume, the
flake revision + `/opt/ampberry` store path shown at the bottom, log passive behind it. The maker
name/homepage were removed from the device (`/etc/ampberry/release`, motd, issue, pi-gen stage,
UI footer gone) per "don't show/store the user". Aggregator: drops our own
`<timestamp> [LEVEL] tool:` prefix and the Wi‑Fi tool's JSON fragments. Tests: 66 runs green
(remote + aggregator cases added). Deployed with `system-manager switch`, see below.

**Third pass — single page:** player bar hidden while idle (`#player.idle`, log padding follows);
header full-width on desktop; active tab without underline, subtle `text-shadow` glow; **Settings
became an overlay**: `turbo-rails` 2.0.23 added (Frames only — `Turbo.session.drive = false`, no
streams/ActionCable), RubyUI `Sheet` in the nav lazy-loads `/settings` into
`<turbo-frame id="settings">`; `SettingsController` renders without layout for frame requests
(`turbo_frame_request?`) and the view wraps itself in the frame so `redirect_to settings_path`
after Apply re-renders in place with the flash. All RubyUI open/close animations disabled
(`[data-state] { animation: none }`). Lock gotcha again: `bundle lock` silently dropped the `ruby`
platform — re-added with `--add-platform ruby` before `bundix`.

**Fourth pass:** the Settings overlay got a pinned title bar at the top and a pinned stats bar at
the bottom (sticky header/footer inside the scrolling frame). **Build number** introduced:
`BUILD` in `/etc/ampberry/release` = commit count (`self.revCount`), shown as `build N · <rev> ·
<store path>` and in the motd; `dev` while the tree is dirty (as it is tonight — everything since
the initial commit is uncommitted, so the device shows `build dev · 9c987fd-dirty`).

**Fifth pass (Florent's review, same night):** nav never flies on macOS (document overscroll
disabled on the home screen, the log and the panel are contained scroll areas); Settings overlay
is a rigid column (title bar with a close cross, scrolling middle, stats bar); frame loads
`eager` with a spinner (the lazy frame sometimes never fired after the Sheet cloned it); click
outside closes; no blur behind the panel (`backdrop-blur-sm` removed from our copy of
`sheet_content.rb`). Actions: **Restart AirPlay now also restarts avahi** (restart + re-announce
merged; `restart-avahi` removed from `actions.json`); System order Reboot (normal) → Redeploy (red,
`danger: true`), both armed by an "I really mean it" checkbox (`arm_controller`) instead of a
dialog. All help text removed from Settings. Theme back to **stock** shadcn/RubyUI tokens (my
black/white overrides and border tweaks deleted; stock animations back). Tests 66 green.
Then: the stock top-right close removed from our copy of `sheet_content.rb` (one cross, left of
the title), backdrop made explicitly tappable (`cursor-pointer` + a `touchend` fallback and
Escape in `sheet_content_controller.js` — iOS Safari does not always turn a tap on a plain div
into a click). Verified with real clicks at tablet width; deployed, `verify.sh` green.
Then: group headings removed — one actions card (Restart AirPlay, Reboot, Redeploy), label left,
control right, gap fills (wraps right-aligned on a narrow phone). Deployed, `verify.sh` green.
Then the final sequence: AirPlay card (name, password) · Sound card (max volume, resampling,
output format; the Advanced collapsible is gone) · Restart AirPlay alone · Reboot + Redeploy
grouped; the arming checkbox reads "Ok". Two forms, each with its own Apply (settings-apply merges
partial settings). Deployed, `verify.sh` green.
Player bar rule: visible while playing; paused from the bar → stays with a play button
(`pausedByUs` flag in `player.js`, cleared on resume); paused/stopped from the source → hidden;
our optimistic state is held 5 s after a pause (the sender reports it within ~1 s).
Florent got stuck in the overlay on the phone: closing now goes through direct `click`/`touchend`
listeners on the panel wrapper (capture phase) for the backdrop and `[data-close-sheet]` (the
cross) instead of Stimulus action resolution on frame-loaded content, and the opener refuses to
stack a second overlay when "Settings" is tapped again while the first is loading (that was a way
to get "stuck": closing one left another). Actions laid out as a table so the Ok boxes and the
buttons sit in straight columns. Action label "Redeploy the stack" → "Redeploy now".

**Root cause of the stuck overlay (found from the device, not the phone):** the Pi's importmap had
no `controllers/ruby_ui/sheet_content_controller` — the RubyUI Sheet generator writes two
controllers and only `sheet_controller.js` had been `git add -N`'d; the flake source is
git-filtered, so the controller that owns `close()` never shipped (the Mac preview had the file
on disk, hence "works here"). All the Safari theories were wrong. Fix: both files tracked
(`checkbox_group_controller.js` too), and the `ampberry-ui` Nix check now fails when a page
references a Stimulus controller that is not pinned in the importmap — the local/deployed source
divergence can no longer reach the device silently. `ampberry-v2/result` gitignored.

**Builds 3–11 (00:00–01:00):** label/style iterations from Florent's review, one commit each:
"Redeploy" label, Apply/Restart as the quiet outline-in-light/secondary-in-dark style, no group
headings, Yes → Yes → Now arming chain, stats bar without the store path, no overscroll bounce.

**Build 12 (02:20):** Settings without Apply buttons — name saves as you type (0.8 s debounce),
password gets an eye toggle and a "+" to save, Sound saves 1 s after a change (`autosave_controller`,
`SettingsController#update` answers JSON for it); tooltips on the sound settings, selects
right-aligned one per line; Restart card moved above Sound; AirPlay card shows the running
shairport-sync version (from the store path — the binary's `-V` says 5.5.1 for 5.5.2) with an
up-to-date badge and "Check for updates" (`Ampberry::Updates`, GitHub releases API, cached in
`/run/ampberry/updates.json`, `ampberry-updates.timer` daily). New `ampberry-health.timer`: every
minute `Ampberry::Health` logs `ok · 48°C · cpu 3% · mem 29%` (thermal zone, /proc/stat delta,
MemAvailable) → shown green in the live log, `DEGRADED` red; log timestamps in the muted colour.
Tests 73 green. Build 13: timestamp span kept inline (the block rule had hit it).

**Build 14:** minimal AirPlay status lines in the live log — `⏵ Title — Artist · <client>` (client
once per session), `⏸ Title — Artist`, `⏵ …` on resume / track change, `⏹ <client>` on session
end; no line for a bare connection or for metadata arriving before `pbeg` (a pause line only after
playing). Tagged `airplay` (was `track`). Tests 75 green.

**23:47 — committed and tagged.** Everything above committed as `decdbb0` on `main`, tagged
**`v1`** (192 files; secrets/build artefacts verified ignored, staged diff scanned). Redeployed
from the clean tree: the device now reports **`build 2 · decdbb0`** (`BUILD="2"` in
`/etc/ampberry/release`, generation 15), `verify.sh` all checks passed. From here on every
commit is a build number; a dirty tree deploys as `dev`.

## 2026-10-09 — Ampberry: build 16 — log tail + dates, quarter-hour health, Settings pane, "• Live"

Florent's fix list, one build. **Log:** the page now loads only the last 100 lines
(`GET /api/log?tail=100`, a backwards line scan over at most 64 KB) and streams from there; lines
are appended one per frame (more when a background tab throttles the timer, so the queue never
lags) and the tail follows unless the reader scrolled up — the old whole-file first request and
full re-render on every poll are gone. Lines carry the **date** now: `YYYY-MM-DD HH:MM:SS tag
message` (`LogAggregator#format_line`; the UI accepts both formats, so the existing file needs
no rewrite). **Health:** `ampberry-health.timer` runs on the clock — `OnCalendar=*-*-* *:00/15:00`,
`AccuracySec=1s` — instead of every minute from boot. **Top bar / Settings:** the bar is fixed
(`h-12`, hand cursor on the tabs); the Settings pane hangs **under** it (`top-12`, as does the dimmed
backdrop, so the bar is never dimmed), appears at once (slide/fade classes removed from
`SheetContent`), has no title bar and no close cross — a tap on the dimmed area, on empty bar space
or on the Settings tab again closes it (`sheet_content_controller.js` listens on the bar;
`sheet_controller#open` toggles). Found in the preview: the opening click was still bubbling when
the bar listener attached and closed the pane immediately → the trigger is excluded from the bar
rule. Stats bar keeps the build number and shows the flake's store path instead of the revision.
**"• Live"** replaces "Now playing": the dot is green when ready for a sender, red and bouncing
while playing, orange when paused, grey when the snapshot is stale (server-rendered from
`now-playing.json`, kept current by `player.js`). **Sound tooltips:** full descriptions on the
setting, on each −/+ button (what moving the ceiling does, ≈ ±11–12 % loudness per dB, the −6 dB
limit) and on every resampling / output-format choice (`<option title>`). Tests 75 green,
`nix build .#ampberry-ui` green (renders every page, controllers pinned).

**18:18 — deployed** as `a6103c7` from a clean detached worktree (the working tree held Florent's
uncommitted README/Dockerfile draft, which would have made the build `dev`): device reports
**`build 16 · a6103c7`**, `ampberry-health.timer` next run 18:30:00 exactly, log lines dated,
`/api/log?tail=2` returns the last two lines, the Live dot renders `ready`, the Settings footer
reads `build 16 · /nix/store/…-source/ampberry-v2`, `verify.sh` all checks passed. Not
listen-tested (no AirPlay session at the time).

**Build 18 (18:32):** health line reordered to `ok · cpu 24% · mem 31% · 44.0°C` (`Health.line`,
`136026b`; 17 was the docs commit). Deployed the same way, `verify.sh` all checks passed.

**Build 20 (18:38):** Sound card — the −/+ buttons are gone (the number field's native stepper
stays; `stepper_controller.js` deleted), and each setting's label gets a **(?)** that shows the
help on hover or tap: a CSS-only popover (`group/help`, `group-hover`/`group-focus-within`),
anchored to the row so it never leaves the pane (the first cut, anchored to the (?), clipped at
the phone's right edge in the preview). `3274051`, three tooltips served, `verify.sh` all
checks passed.

**Build 22 (18:44):** password saves 1 s after the last keystroke like the other fields (the "+"
button is gone); the brand at the top left is now the receiver's AirPlay name
(`AmpberryBridge.airplay_name` parses the world-readable `/etc/shairport-sync.conf` — the settings
store is root-only and a control-socket call per page load would log an action each time), and a
saved rename updates it in place (`autosave_controller.js` → `[data-brand]`). Checked in the
preview with a mocked POST; on the device the brand renders `Ampberry` from the live conf.
`387860f`, `verify.sh` all checks passed.

**Build 24 (18:47):** health line without the `ok` prefix — `cpu 0% · mem 31% · 43.5°C`
(`DEGRADED · …` only when unwell). `647bf3b`, all checks passed.

**Build 25 (19:02) — the Update button + on-device shairport-sync update; MAC label.** The update
badge and "Check for updates" link became one fixed-size button (green "✓ up to date", red
"↑ x.y.z available" / "✗ check failed", grey "Check for updates"; hover → grey "Check now" /
"Update now"; spinner + "Checking…" / "Updating…" while busy; `updates_controller.js`,
`GET /updates/status`). "Update now" runs the new allow-listed action `update-shairport`
(no confirmation): the Redeploy job in update mode writes
`/var/lib/ampberry/shairport-update/flake.nix` — the shipped flake as a `path:…?dir=ampberry-v2`
input plus `github:mikebrady/shairport-sync/<tag>` — calling the new `lib.withShairport` output
of `flake.nix` (`shairport-sync.nix` takes `shairportSrc`/`shairportVersion`; `build` and
`FLAKE_VERSION` are passed through from `/etc/ampberry/release` because a `path:` input has no
git metadata), `nix flake lock`s it, `system-manager switch`es from it, then
`systemctl start ampberry-updates.service` refreshes the cache; the button polls until the job
is done. The flake pin is untouched: Deploy/Redeploy from `/opt/ampberry` returns to it. AirPlay
card also shows `MAC: b8:27:eb:…` (wlan0, from /sys). Tests 78 green. `716664f`.

**First on-device run (19:05) failed in two seconds:** `"\xE2" from ASCII-8BIT to UTF-8` — the
job streams tool output with `Encoding.default_internal` set and `nix flake lock` printed "…";
the plain Redeploy had the same latent bug. Also found: a burst of Settings saves (each restarts
shairport-sync) had tripped the unit's start limit (5 per 5 min) at 18:50 — one
`ampberry-control@` instance failed with "start of the service was attempted too often"
(cleared with `reset-failed`; the receiver had already recovered).

**Build 26 (19:08):** streamed output tagged UTF-8 (test with "…" in the fake nix output);
`shairport-sync` `StartLimitIntervalSec=60`/`StartLimitBurst=20` (crash-loop protection only) and
`systemctl reset-failed shairport-sync` before the settings/restart-airplay restarts. `397727c`.
**Second on-device run (19:08–19:17): success.** `ampberry redeploy start --update-shairport
5.5.2 5.5.2` (same release, to prove the path): lock 2 s, nixpkgs/system-manager sources and the
build toolchain pulled from the caches, **shairport-sync 5.5.2 compiled on the Pi 3**, switch,
cache refresh — 569 s in all, memory stayed under 300 MB used. Afterwards `BUILD="26"` kept,
`/run/system-manager/sw/bin/shairport-sync` → the new store path, `updates.json` up to date,
nqptp / shairport-sync / UI active, `verify.sh` all checks passed. Not listen-tested after the
switch. Expect ~10 min and a short audio gap when a real release ships; a Redeploy reverts.
Side effect: the Nix store grew 1.5 G → 3.2 G (nixpkgs sources + the build toolchain, not GC
roots); `sudo nix-collect-garbage` would reclaim it — left as is.

**Build 28 (19:29):** the update control styled as the badge again (tinted pill with ring; the
two hover labels share one grid cell so the width never changes). All checks passed.

**Build 29 (19:36):** the **player moved into the top bar** — a round play/pause button and one
truncated "Title · Artist" line between the brand and the tabs, visible only while playing (or
paused from the bar); the bottom bar, artwork Dialog, progress line and status text are gone
(`Components::Nav#player`, `player.js` slimmed; `Views::Player::Index` renders nothing — the log
is the page). Checked in the preview with the playing fixture and a mocked pause; on the device
the bar serves the player markup, `verify.sh` all checks passed. Not exercised with a live
AirPlay session yet.

## 2026-10-10 — Ampberry: build 31 — "stuck on Checking…" report

Florent reported the update badge staying on "Checking…" after a tap, even once the pointer
left. Could not reproduce: a real session + CSRF token from the Pi itself answers
`POST /updates/check` in 0.3 s (GitHub resolves IPv4-only from the Pi, 0.25 s), the flow completes
in Chrome (preview) and in real WebKit (iOS Simulator, iPhone Air, Safari — both the green
"Check now" path and the red "Update now" path). The Pi's UI journal shows no check request that
failed. Build 31 makes the badge robust anyway: the check/update POSTs abort after 20 s, so a
request the server never answers (UI restarting mid-deploy, network gone) ends in "✗ check
failed" instead of a permanent "Checking…". `verify.sh` all checks passed. Simulator finding:
a 0.1 s "tap" does not register as a click in WebKit, a plain tap does — testing artefact, not a
UI bug. Also seen: ⏸ renders as an emoji on iOS (⏵ as a glyph) — cosmetic, left for later.

**Build 33 (16:33) — Network card.** Below Sound: a **Wi‑Fi** and an **Ethernet** row, each with
its state in a word (connected / no cable / off / disconnected…), the leased IPv4 address small
underneath (the SSID on the Wi‑Fi line) and a **switch**. The switch is only usable when switching
off cannot lock the user out — the other interface must be connected with an address
(`Ampberry::Network.may_disable?`, and the root-side `network-set` action refuses it again).
Wi‑Fi off = `nmcli radio wifi off` (NetworkManager keeps it across reboots); Ethernet off =
`nmcli device set eth0 autoconnect no` + `device disconnect` (forgotten at the next reboot, so a
cable always works again after one). Below the rows: Wi‑Fi network + password + **Connect**
(the existing `wifi-connect` action). Status is read in the UI process — `nmcli` answers any
user, nothing privileged, nothing logged; `network-status` exists on the control side too.
`network_controller.js` reloads the Settings frame after a switch or a connect. 5 tests (83
green). On the device: rows read `Wi‑Fi connected 192.168.178.221 · Pass the Juice` and
`Ethernet no cable`; via the API: eth0 off → `GENERAL.AUTOCONNECT:no`, Wi‑Fi off refused with
"Wi‑Fi is the only way in — connect the other interface first", eth0 on → autoconnect yes again;
shairport-sync untouched. Not yet tried with a cable plugged in.

**Build 34:** the refusal above left an `ampberry-control@` instance "failed" (the handler
exited 1 whenever the answer was `ok:false` — same thing the 18:50 settings-apply failure had
shown) → `respond` exits 0 (the request was answered; the error is the client's), and
`CollectMode=inactive-or-failed` moved from [Service] (ignored, "Unknown key") to [Unit] so
instances that do fail are collected. Deployed 16:41: the same refused switch now leaves no
failed unit, no "Unknown key" warning in the journal, `verify.sh` all checks passed.
**Tagged `v34`** (build 34, `95d580f`); `v35` waits for Florent's confirmation.

## 2026-10-10 — repo → "AirPlay OS": flake at the root, devices as definitions + records

Florent: treat the project as an OS for Raspberry Pis and deploy it on HifiBerry too; the `.md`
files just track installations and versions. Done in two commits (`dc0e493`, `7488d26`):

- `ampberry-v2/*` moved to the repo root (`git mv`, history kept); the old root README (the
  "Infrastructure as Context" framing) removed, Florent's "AirPlay OS" README draft is the README
  (with a Devices table and a "what works today (Nix)" section added); `AGENTS.md` rewritten;
  `docs/architecture.md` holds the technical reference that used to live in `Ampberry.md`.
- **Devices** = `devices/<id>.json` (id, hostname, pretty name, board, HAT, overlay, radios,
  primary interface, address, LAN, shairport-sync defaults) + `devices/<Id>.md` installation
  records. The flake reads the JSON (`systemConfigs.<id>`, `lib.withShairport { device }`,
  `devices` output) and ships it as `/etc/ampberry/device.json` + `defaults.json`; the Ruby tools
  read it back (`Ampberry.device`): config.txt lines (overlay or none, `disable-bt`,
  `disable-wifi`), pretty hostname, the Wi‑Fi provisioning step, the redeploy flake attribute;
  the Wi‑Fi fallback timer, the captive dnsmasq conf and the hotspot firewall rules exist only for
  `"wifi": true`; branding (release file now has `DEVICE=`), MOTD interface and URL per device.
  `etc/ampberry/defaults.json` is gone (generated from the device).
- `devices/hifiberry.json`: Pi 4B + DAC+, `"wifi": false`, `volume_max_db` 0 dB, overlay
  `hifiberry-dacplus-std` — **the old HifiBerry.md claimed EEPROM auto-detection; the box's
  config.txt says `dtoverlay=hifiberry-dacplus-std`** (hbos wrote it). Record corrected.
- Tools: `DEVICE=<id>` for `verify.sh` (reads device.json from the box: per-device unit, overlay
  and radio checks, mDNS name) and `apply-live.sh` (`.#<id>`, host alias, tolerant of a missing
  network-config); `build-user-data.rb --device <id>` (hostname / pretty name from the
  definition, no Wi‑Fi section and no Wi‑Fi secrets required for an Ethernet-only box);
  `build-image.sh` copies the repo root. Test `device_test.rb` (86 green; run with four seeds).
- **Build 36 failed** on the Linux builder: the tools package runs the suite in the sandbox,
  where `devices/` was not part of the filtered source and a test had left an Ethernet-only
  `device.json` behind for the others (random order). Both fixed. **Build 37 (17:25)** deployed:
  `DEVICE="ampberry"`, `/opt/ampberry` → the store copy of the repo root, `device.json` on the
  box, Wi‑Fi timer active, hotspot rules present, Settings footer `build 37 · /nix/store/…-source`,
  `DEVICE=ampberry tools/verify.sh` all checks passed. Nothing on HifiBerry touched: its
  migration purges the whole hbos stack and waits for Florent's go.

<!-- New entries go above this line -->
