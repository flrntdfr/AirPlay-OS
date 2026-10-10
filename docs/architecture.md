# AirPlay OS — architecture

Raspberry Pi OS Lite keeps the officially supported base (apt-managed kernel and firmware,
NetworkManager, avahi, cloud-init). Everything above the kernel is declared in the Nix flake at the
root of this repo and applied with [system-manager](https://github.com/numtide/system-manager):
packages, systemd units, `/etc` files, the firewall, the sshd policy, branding. One system per
device — `systemConfigs.<id>` built from `devices/<id>.json`.

```
iPhone/Mac ──AirPlay 2──▶ nqptp (PTP 319/320) + shairport-sync (RTSP 7000) ──ALSA hw:0──▶ HiFiBerry HAT
                                   │ metadata pipe /run/shairport-sync/metadata
                                   ▼
                        ampberry-metadata ──▶ /run/ampberry/now-playing.json (+ ⏵ ⏸ ⏹ lines in the journal)
                                   ▼
browser ──:80──▶ ampberry-ui (Rails, user ampberry) ──unix socket──▶ ampberry-control@ (root, allow-list)
                      ▲ home page: /var/log/ampberry.log  ◀── ampberry-log (journal aggregator)
```

Runtime-mutable state stays outside Nix: `/etc/shairport-sync.conf` (rendered from
`/etc/ampberry/defaults.json` ⊕ `/var/lib/ampberry/settings.json`), NetworkManager profiles,
`/boot/firmware/*`.

## Repo layout

| Path | What |
|---|---|
| `flake.nix`, `flake.lock` | inputs: nixpkgs 26.05, nixpkgs-unstable (shairport-sync 5.5.2 + nqptp 1.2.8 only), system-manager release-26.05. Outputs: `systemConfigs.<id>`, `packages`, `lib.withShairport`, `devices` |
| `devices/<id>.json` | the device definition: `id`, `hostname`, `pretty_name`, `description`, `board`, `hat`, `overlay` (null = HAT EEPROM announces it), `wifi`, `bluetooth`, `primary_interface`, `address`, `network` (LAN CIDRs, Wi‑Fi interface, hotspot subnet), `defaults` (shairport-sync settings). Shipped to the box as `/etc/ampberry/device.json` and `/etc/ampberry/defaults.json` |
| `devices/<Id>.md` | the installation record: hardware, network, what runs, which build since when |
| `nix/system/ampberry.nix` | the system-manager module: packages, units, `/etc`, tmpfiles (`/opt/ampberry` → the flake source in the store) |
| `nix/system/firewall.nix` | nftables ruleset generated from the device's LAN; hotspot rules only for Wi‑Fi devices |
| `nix/system/branding.nix` | `/etc/ampberry/release` (NAME, DEVICE, FLAKE_VERSION, BUILD), issue, MOTD |
| `nix/packages/` | `shairport-sync.nix` (AirPlay 2 + metadata pipe, overridable release), `ampberry-tools.nix`, `ampberry-ui.nix` (bundlerEnv, Tailwind compiled at build, every page rendered as a check) |
| `lib/ampberry/*.rb`, `bin/ampberry`, `test/` | the Ruby tools (stdlib only) — see below; minitest suite |
| `ui/` | the Rails web UI (RubyUI = Phlex + Tailwind 4 + Stimulus) |
| `etc/ampberry/actions.json` | custom allow-listed actions (root-owned on the device) |
| `cloud-init/`, `pi-gen/`, `tools/build-image.sh`, `tools/flash.sh` | first-boot seed and the branded image build (Docker) |
| `tools/apply-live.sh` | in-place migration of a box running HiFiBerry OS NG (`DEVICE=<id>`) |
| `tools/verify.sh` | post-deploy checks (`DEVICE=<id>`), reads the device definition from the box |

## The tools (`ampberry`)

Ruby 3.4, stdlib only, for what the flake cannot express at runtime: `provision` (config.txt from
the device definition, users/dirs, avahi IPv4, hostname, sshd reload, settings → conf, leftover
cleanup, Wi‑Fi check), `settings` (render `/etc/shairport-sync.conf`, restart the receiver),
`wifi` (status, onboarding hotspot state machine, join), `network` (the two interfaces), `control`
(the socket-activated handler), `metadata` (pipe → snapshot + status lines), `log` (journal →
`/var/log/ampberry.log`), `health` (quarter-hourly line), `updates` (shairport-sync release check),
`redeploy` (re-apply the flake from `/opt/ampberry`, or a newer shairport-sync release on top of it).

## Security model

- `ampberry` (UI, metadata daemon) and `shairport-sync` have no shell, no password, **no sudo, no
  polkit**. Root exists only at activation time and inside the control handler.
- **Control API**: `ampberry-control.socket` → `/run/ampberry-control.sock` (`root:ampberry` 0660,
  one `ampberry-control@` process per request). JSON in, JSON out; peer uid re-checked
  (`SO_PEERCRED`); size/time limits; only allow-listed actions run — built-ins (`settings-*`,
  `wifi-*`, `network-status`, `network-set`, `restart-airplay`, `redeploy`, `update-shairport`,
  `clean-reboot`) and custom entries from root-owned `/etc/ampberry/actions.json` (`exec` =
  absolute argv, never a shell, no client arguments). `POST /api/actions/<id>` is the same thing.
  A refused action answers `ok:false` and the handler still exits 0.
- **SSH**: `/etc/ssh/sshd_config.d/10-ampberry.conf` — `AuthenticationMethods publickey`,
  `PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers pi`, `MaxAuthTries 3`.
- **Firewall** (policy drop; the device's LAN only): 22, 80, 7000/tcp, 319–320/udp, 5353/udp,
  32768–60999 tcp+udp (AirPlay 2 negotiated); hotspot onboarding rules on the Wi‑Fi interface for
  Wi‑Fi devices; IPv6 closed except neighbour discovery; avahi publishes IPv4 only.

## Services

| Unit | Runs as | Purpose |
|------|---------|---------|
| `nqptp.service` | DynamicUser | AirPlay 2 timing (UDP 319/320) |
| `shairport-sync.service` | `shairport-sync` | AirPlay 2 receiver → `hw:0` (TCP 7000); start limit 20/min (settings saves restart it) |
| `ampberry-metadata.service` | `ampberry` | pipe → `/run/ampberry/now-playing.json`; one journal line per transition, tag `airplay`: `⏵ Title — Artist · <client>`, `⏸ …`, `⏹ <client>` |
| `ampberry-control.socket` / `ampberry-control@.service` | root | control API |
| `ampberry-ui.service` | `ampberry` (+`CAP_NET_BIND_SERVICE`) | Rails UI on :80 |
| `ampberry-log.service` | root | journal → `/var/log/ampberry.log` (the home page) |
| `ampberry-wifi-fallback.timer` | root | Wi‑Fi devices only: hotspot state machine every 3 min |
| `ampberry-health.timer` | `ampberry` | :00 :15 :30 :45 — `cpu 3% · mem 29% · 48°C` into the log (green; `DEGRADED` above 80 °C / 95 % RAM) |
| `ampberry-updates.timer` | `ampberry` | daily shairport-sync release check → `/run/ampberry/updates.json` |
| `ampberry-firewall.service` | root | loads the nftables ruleset |
| `avahi-daemon`, `NetworkManager`, `ssh`, `nix-daemon.socket`, `unattended-upgrades` | Debian | base |

## Key paths on a device

| Path | Purpose |
|------|---------|
| `/opt/ampberry` | symlink into the Nix store: the flake source that produced the running system |
| `/etc/ampberry/{device,defaults,actions}.json`, `release` | shipped by the flake |
| `/etc/ampberry/system-path`, `system-manager-path` | closure recorded for Clean reboot / Redeploy |
| `/var/lib/ampberry/settings.json` | user settings (survive re-provisioning) |
| `/var/lib/ampberry/shairport-update/` | the generated flake of the last on-device shairport-sync update |
| `/var/log/ampberry.log`, `/var/log/ampberry/*` | live log; per-tool logs; `redeploy.{log,json}` |
| `/run/ampberry/`, `/run/ampberry-control.sock` | now-playing state, update cache; control socket |
| `/etc/shairport-sync.conf` | rendered — never edited by hand |

## The web UI

Ruby on Rails 7.2 (railties/actionpack/actionview/propshaft/puma) with RubyUI (shadcn/ui port:
Phlex 2 + Tailwind 4 + Stimulus via importmap; CSS compiled at Nix build time), stock theme, no
gradients, one page:

- **Top bar** (fixed): the brand = the receiver's AirPlay name (follows a rename); the **player**
  while something plays — a round play/pause button (DACP back to the sender) and "Title · Artist";
  **"• Live"** whose dot is the receiver's state (green ready, red bouncing while playing, orange
  paused); **Settings**.
- **Home** = the live log full screen: the last 100 lines on load, then streamed, one line per
  frame; `YYYY-MM-DD HH:MM:SS tag message`, timestamp muted, errors red, warnings orange, health green.
- **Settings pane** under the bar (no title, no cross; a tap outside closes it), rigid stats bar at
  the bottom (`vN` — the build number, which the `vN` tags are cut from — over the flake's store path): **AirPlay** (name and password save 1 s after typing; MAC;
  the shairport-sync version with the **update badge** — green up to date / red release available /
  grey unchecked; hover offers Check now / Update now; the update builds the release on the Pi on
  top of the flake, ~10 min, a Redeploy reverts), **Restart AirPlay**, **Sound** (max volume,
  resampling, output format, saved 1 s after a change, (?) help popovers), **Network** (Wi‑Fi and
  Ethernet rows with state and leased address, a switch each that can never lock the user out, join
  a Wi‑Fi network), **Reboot** and **Redeploy** armed by chained "Yes" boxes.
- No volume control, no artwork, no maker identity anywhere on the device.

## Releases (CI)

`.github/workflows/release.yml`, on every push to `main`: the Ruby suite on ubuntu, then on an
arm64 runner (`ubuntu-24.04-arm`): the flake built natively (`ampberry-tools`, `ampberry-ui`,
both `systemConfigs`), the image built with pi-gen in Docker (`GENERIC=1 tools/build-image.sh`),
and release **`vN`** (N = commit count = the build number the device shows) with one asset,
`airplay-os.img.xz`, and one line, `link`, to paste into Raspberry Pi Imager. The generic
image carries no secrets: no Wi‑Fi, no SSH key, no seed of ours; `airplay-os-firstboot.service`
(pi-gen stage `05-firstboot`) activates the baked `ampberry` system and provisions it on first
boot, the Raspberry Pi Imager's own customization applies, the onboarding hotspot's default
passphrase is `airplay-os`. A personal image (`tools/build-image.sh` with `secrets.env`) bakes
the cloud-init seed instead.

## Deploying

From the repo root, on the Mac (builds on the nix-darwin `linux-builder`, copies the closure over
SSH, activates — nothing is rsynced; the Pi's Nix needs `trusted-users = root pi`):

```bash
nix run github:numtide/system-manager/release-26.05 -- switch --flake .#<id> --target-host pi@<host> --sudo
DEVICE=<id> tools/verify.sh
```

The build number is the commit count (`self.revCount`), so deploy from a clean checkout. On the
device, `sudo ampberry redeploy start` re-applies `/opt/ampberry`; the Settings pane's Redeploy
and Clean reboot do the same without the Mac.
