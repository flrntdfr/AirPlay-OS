# Ampberry

AirPlay 2 speaker built on **Raspberry Pi OS Lite** with everything above the kernel declared in a
**Nix flake** ([`ampberry-v2/`](./ampberry-v2/README.md)) and applied by
[system-manager](https://github.com/numtide/system-manager). A Raspberry Pi 3B drives a HiFiBerry
DAC+/**Amp2** HAT and a custom passive speaker pair. Migrated in place from HiFiBerry OS NG on
2026-10-08 (see [`OPERATIONS.md`](./OPERATIONS.md)).

## Connect

```
ssh pi@ampberry.local        # mDNS (keys only — no passwords, no root login)
ssh pi@192.168.178.221       # Wi‑Fi IP
http://ampberry.local/       # web UI: live log + player · settings (Wi‑Fi via the hotspot only)
```

## Hardware

| Component | Details |
|-----------|---------|
| Hostname | `ampberry` (static), pretty name `Ampberry` |
| Board | Raspberry Pi 3 Model B Rev 1.2 (aarch64, ~905 MB RAM, zram swap) |
| HAT | HiFiBerry DAC+/Amp2 (`dtoverlay=hifiberry-dacplus-std`) |
| Speakers | Custom passive pair (see "Speaker build") |
| ALSA card | `hw:0` — `snd_rpi_hifiberry_dacplus` / pcm512x; mixer `Digital` (−103.5…0 dB), `Analogue` |
| Network | Wi‑Fi `wlan0` — `192.168.178.0/24`; Bluetooth off (`dtoverlay=disable-bt`); `eth0` DHCP as rescue path |
| Storage | 58 GB SD card |
| User | `pi` (passwordless sudo, SSH keys only); `ampberry`, `shairport-sync` system users (nologin) |

## Software stack

| Layer | Source |
|-------|--------|
| OS | Raspberry Pi OS Lite — Debian 13 (trixie), kernel `6.18.50+rpt-rpi-v8`, `raspi-firmware` 1.20260915 — **apt**, security auto-updates only |
| Nix | Determinate installer (multi-user daemon), store on the SD card |
| Appliance | `ampberry-v2` flake, pinned: nixpkgs 26.05 (`7c8764b`), nixpkgs-unstable (`e7439b6`, audio only), system-manager release-26.05 (`8c7a4b8`) |
| AirPlay 2 | `shairport-sync` **5.5.2** (ALSA, soxr, Avahi, metadata pipe, `ffmpeg-headless`) + `nqptp` **1.2.8** |
| Tools | `ampberry` (Ruby 3.4, stdlib only): provisioning, settings, Wi‑Fi onboarding, control API, metadata daemon, redeploy, live log |
| Web UI | Ruby on Rails 7.2 (railties/actionpack/actionview/propshaft/puma) with **RubyUI** (shadcn/ui port: Phlex 2 + Tailwind 4 + Stimulus via importmap; CSS compiled at Nix build time), user `ampberry`, port 80. Stock shadcn/RubyUI theme (no custom tokens), no gradients. **Home** = the live log full-screen (the last 100 lines on load — `/api/log?tail=100` — then streamed; lines appear one per frame, the tail follows unless you scrolled up; each line `YYYY-MM-DD HH:MM:SS tag message`, timestamp muted, errors red, warnings orange, health green) with a player bar flush at the bottom: cover thumbnail (tap → full-screen Dialog), title/artist/status, progress line, **play/pause** (sent back to the phone over DACP with the session's `dacp_id` + `active_remote`, see `lib/ampberry/remote.rb`). The bar shows only while something is playing; pausing *from the bar* keeps it (with a play button), pausing or stopping *from the phone* hides it. **Single page:** a fixed top bar spans the full width (brand left; right: **"• Live"** whose dot is the receiver's state — green ready for a sender, red bouncing while playing, orange paused, grey unknown — and **Settings**, hand cursor, active tab = subtle glow); **Settings is a pane hanging under the top bar** (RubyUI Sheet, right side, full width on the phone; appears at once, no animation) that loads `/settings` into a Turbo Frame — in this order: **AirPlay** card (name and password save 1 s after the last keystroke, the password behind an eye toggle; a saved name also renames the brand at the top left — the brand is the receiver's AirPlay name, read from the rendered `/etc/shairport-sync.conf`; then `MAC: …` (wlan0's address, small) and the running `shairport-sync` version with the **update button**: one fixed size, green "✓ up to date" / red "↑ 5.6.0 available" (or "✗ check failed") / grey "Check for updates"; hovering turns it grey and offers "Check now" or "Update now", a tap shows a spinner ("Checking…" / "Updating…"). Check = `Ampberry::Updates` compares the store‑path version with GitHub's latest release, cached in `/run/ampberry/updates.json`, refreshed daily by `ampberry-updates.timer`. Update = the `update-shairport` action, no confirmation (audio stops for the switch): the job writes `/var/lib/ampberry/shairport-update/flake.nix` — the shipped flake as a `path:` input plus the release tarball from GitHub, through `lib.withShairport` in `flake.nix` — locks it, `system-manager switch`es from it (builds shairport-sync on the Pi, minutes), refreshes the update cache; the button polls `/updates/status` and turns green when the new version runs. The pin in the flake is unchanged: the next Deploy/Redeploy from `/opt/ampberry` returns to it, the permanent fix is bumping the flake), **Restart AirPlay** row (restarts nqptp + shairport-sync + avahi), **Sound** card (max volume as a number field with its native stepper, resampling, output format — saved 1 s after a change, selects right‑aligned; a **(?)** after each label opens the help on hover or tap — CSS-only popover anchored to the row: what the ceiling does per dB and the −6 dB limit, a description of each resampling / output-format choice; the choices also carry `title`s), then **Reboot** and **Redeploy** (red) grouped: Reboot's "Yes" arms its "Now" and Redeploy's "Yes", which arms Redeploy's "Now". No Apply buttons (every save restarts the receiver for a few seconds), no help text, no group headings, no title bar and no close cross: the top bar stays undimmed above the pane and a tap anywhere outside the pane — the dimmed area, empty bar space, or the Settings tab again — closes it (no blur). Rigid stats bar at the bottom, only the part above it scrolls: **build number** (= commit count of the repo, `self.revCount`; `dev` when deployed from a dirty tree) · the flake source's Nix store path (`/opt/ampberry` → `/nix/store/…-source`); the form submits in place (Turbo), actions via fetch. `/settings` still works as a full page. Turbo Drive is off (one page, polling scripts). Wi‑Fi page only via the hotspot captive portal. No maker/user identity is stored or shown anywhere on the device. |
| Firewall | nftables ruleset generated by the flake (`nix/system/firewall.nix`) |

**Use case:** AirPlay 2 only (no Spotify Connect, Roon, LMS, MPD, Bluetooth). Deliberately **no
volume control in the UI**: the phone sets the level, capped by `volume_max_db`.

## Architecture

```
iPhone/Mac ──AirPlay 2──▶ nqptp (PTP 319/320) + shairport-sync (RTSP 7000) ──ALSA hw:0──▶ Amp2 ──▶ speakers
                                   │ metadata pipe /run/shairport-sync/metadata
                                   ▼
                        ampberry-metadata ──▶ /run/ampberry/now-playing.json + cover
                                   ▼
browser ──:80──▶ ampberry-ui (Rails, user ampberry) ──unix socket──▶ ampberry-control@ (root, allow-list)
                      ▲ backdrop: /var/log/ampberry.log  ◀── ampberry-log (journal aggregator)
```

Everything static is in the flake (packages, units, `/etc` files, firewall, sshd policy, branding).
Runtime-mutable state is outside Nix: `/etc/shairport-sync.conf` (rendered from
`/etc/ampberry/defaults.json` ⊕ `/var/lib/ampberry/settings.json`), NetworkManager profiles,
`/boot/firmware/*`.

### Security model

- `ampberry` (UI, metadata daemon) and `shairport-sync` have no shell, no password, **no sudo, no
  polkit**. Root exists only at activation time and inside the control handler.
- **Control API**: `ampberry-control.socket` → `/run/ampberry-control.sock` (`root:ampberry` 0660,
  one `ampberry-control@` process per request). JSON in, JSON out; peer uid re-checked
  (`SO_PEERCRED`); size/time limits; only allow-listed actions run — built-ins (`settings-apply`,
  `wifi-*`, `restart-airplay`, `redeploy`, `update-shairport`, `clean-reboot`) and custom entries from root-owned
  `/etc/ampberry/actions.json` (`exec` = absolute argv, never a shell, no client arguments). The
  Settings page shows them as buttons; `POST /api/actions/<id>` is the same thing.
- **SSH**: `/etc/ssh/sshd_config.d/10-ampberry.conf` — `AuthenticationMethods publickey`,
  `PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers pi`, `MaxAuthTries 3`.
- **Firewall** (policy drop; LAN `192.168.178.0/24` only): 22, 80, 7000/tcp, 319–320/udp, 5353/udp,
  32768–60999 tcp+udp (AirPlay 2 negotiated); hotspot onboarding rules on `wlan0` only; IPv6 closed
  except neighbour discovery; avahi publishes IPv4 only. Change the LAN in `flake.nix` → `network`.

## Services and ports

| Unit | Runs as | Purpose |
|------|---------|---------|
| `nqptp.service` | DynamicUser | AirPlay 2 timing (UDP 319/320) |
| `shairport-sync.service` | `shairport-sync` | AirPlay 2 receiver → `hw:0` (TCP 7000) |
| `ampberry-metadata.service` | `ampberry` | pipe → `/run/ampberry/now-playing.json` |
| `ampberry-control.socket` / `ampberry-control@.service` | root | control API |
| `ampberry-ui.service` | `ampberry` (+`CAP_NET_BIND_SERVICE`) | Rails UI on :80 |
| `ampberry-log.service` | root | journal → `/var/log/ampberry.log` (UI backdrop) |
| `ampberry-wifi-fallback.timer` | root | hotspot state machine every 3 min (`ampberry wifi ensure`) |
| `ampberry-metadata.service` (log lines) | `ampberry` | one line per AirPlay transition, tag `airplay`: `⏵ Title — Artist · <client>` (client named once per session), `⏸ Title — Artist`, `⏵ …` on resume/track change, `⏹ <client>` when the session ends; nothing for a connection that has not started playing |
| `ampberry-health.timer` | `ampberry` | on the quarter hour (`OnCalendar=*:00/15`, `AccuracySec=1s` → :00 :15 :30 :45): `cpu 3% · mem 29% · 48°C` into the journal → the live log (green; `DEGRADED` red above 80 °C / 95 % RAM) |
| `ampberry-updates.timer` | `ampberry` | daily shairport-sync release check → `/run/ampberry/updates.json` (also on demand from Settings) |
| `ampberry-firewall.service` | root | loads the nftables ruleset |
| `avahi-daemon`, `NetworkManager`, `ssh`, `nix-daemon.socket`, `unattended-upgrades` | Debian | base |

Listening (LAN only): 22/tcp, 80/tcp, 7000/tcp, 319–320/udp, 5353/udp, plus AirPlay 2 session ports.

## Key paths

| Path | Purpose |
|------|---------|
| `/opt/ampberry` | symlink into the Nix store: the flake source that produced the running system |
| `/etc/ampberry/{defaults,actions}.json`, `release` | shipped by the flake |
| `/etc/ampberry/system-path`, `system-manager-path` | closure recorded for Clean reboot |
| `/var/lib/ampberry/settings.json` | user settings (survive re-provisioning) |
| `/var/lib/ampberry/ui-secret` | Rails `SECRET_KEY_BASE` (root:ampberry 0640) |
| `/var/log/ampberry.log`, `/var/log/ampberry/*.log` | live log; per-tool logs; `redeploy.{log,json}` |
| `/run/ampberry/`, `/run/ampberry-control.sock` | now-playing state + cover; control socket |
| `/boot/firmware/{config.txt,user-data,network-config,meta-data}` | HAT overlay; cloud-init seed |
| `/etc/shairport-sync.conf` | rendered — do not edit by hand (use Settings / `ampberry settings apply`) |

## Operating it

```bash
sudo ampberry provision                     # re-run the runtime steps (idempotent)
echo '{"settings":{"volume_max_db":-9}}' | sudo ampberry settings apply
sudo ampberry action list | sudo ampberry action run restart-airplay
sudo ampberry redeploy start                # re-apply the flake from /opt/ampberry + provision (background)
sudo ampberry redeploy start --update-shairport 5.6.0   # that release on top of the flake instead (the UI's Update button)
sudo ampberry system clean-reboot           # cloud-init clean + reboot: first-boot path again
ampberry wifi status · sudo ampberry wifi hotspot on|off
tail -f /var/log/ampberry.log               # what the UI shows as backdrop (errors red, warnings accent)
sudo nft list table inet ampberry · systemctl status shairport-sync nqptp ampberry-ui
```

Deploying a change (from the Mac, in `ampberry-v2/`):
```bash
nix run github:numtide/system-manager/release-26.05 -- switch --flake .#ampberry --target-host pi@ampberry.local --sudo
```
Builds on the nix-darwin `linux-builder`, copies the closure over SSH, activates. Nothing is rsynced.
Requires `pi` in the Pi's Nix `trusted-users` (`/etc/nix/nix.custom.conf`, set at install time) —
otherwise the daemon rejects the unsigned paths.

### Automatic updates

`unattended-upgrades` — **Debian security only** (`/etc/apt/apt.conf.d/52unattended-upgrades-local`),
auto-reboot 04:00 if required. Kernel/firmware from `archive.raspberrypi.com` stay manual and
listen-tested; the appliance stack changes only through the flake.

## Agent guidelines

### Do
- Treat this as a **live audio appliance** on constrained hardware (Pi 3, ~1 GB RAM).
- Change the stack **through the flake** (`ampberry-v2/`), test locally (`tools/build-image.sh` is the
  test stage), then deploy with `system-manager … --target-host`. Keep runtime edits to the
  `ampberry` tools' domain (settings, Wi‑Fi, provisioning).
- Verify audio for real: `aplay -l`, `systemctl status shairport-sync nqptp`, `avahi-browse -rt
  _airplay._tcp`, the UI's now-playing, `amixer -c0 sget Digital` — and `tools/verify.sh`.
- Keep `ampberry-v2/README.md`, this file and `OPERATIONS.md` in sync with the device.

### Ask first
- Rebooting / Clean reboot (interrupts playback and SSH).
- `apt` changes (kernel/firmware), `config.txt` edits, changing the firewall posture or the LAN CIDR.
- Anything that gives the `ampberry` user more privilege than the control socket.

### Never
- Add volume control to the UI; raise `volume_max_db` above the listen-tested ceiling without a test.
- Install `ufw`/PipeWire/hbos packages back; use `rsync` to deploy; put secrets in the Nix store.
- Commit or log secrets (Wi‑Fi PSK, SSH keys, `pi` hash, hotspot PSK, Rails secret).
- Assume x86 binaries — this is aarch64; builds for it happen on the linux-builder or the pi-gen chroot.

## Speaker build (custom passive)

The Amp2 drives a custom passive speaker pair. Document driver model, enclosure, crossover and any
EQ notes here once known:

```
Driver(s):
Enclosure:
Crossover:
EQ notes:
```

### Volume ceiling (the 2026-10 "saturates then stops" issue)

Full-scale digital output drives the Amp2 beyond what its supply/speakers tolerate: the amp
distorts and then shuts down. There is no software bug behind it. The fix is the `volume_max_db`
setting (default **−6 dB**): AirPlay volume from the phone is scaled into
`[−volume_range_db, volume_max_db]` on the `Digital` mixer by shairport-sync. Listen-test before
raising it. History: hbos had previously hidden a −24 dB PipeWire software cut (fixed 2026-06-26),
which is why the problem only appeared afterwards.

## Open questions

- Speaker/driver details above.
- Whether to rebuild and flash the branded image (`tools/build-image.sh` → `tools/flash.sh`) onto a
  spare card as a cold standby.
