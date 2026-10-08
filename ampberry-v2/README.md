# Ampberry v2 — AirPlay 2 speaker on Raspberry Pi OS, managed with Nix

**Ampberry** is a Raspberry Pi 3B + HiFiBerry Amp2 powered speaker, by Florent Dufour. This
directory turns the officially supported base — Raspberry Pi OS Lite (apt-managed kernel and
firmware) — into an AirPlay 2 appliance with everything above the kernel declared in a **Nix flake**
and applied by [system-manager](https://github.com/numtide/system-manager).

```
Raspberry Pi OS Lite (apt: kernel, raspi-firmware, NetworkManager, avahi, cloud-init)
└─ Nix + system-manager  ←  flake.nix (this directory, shipped on the device at /opt/ampberry)
   ├─ shairport-sync 5.5.2 (AirPlay 2, ALSA, soxr, metadata pipe) + nqptp 1.2.8
   ├─ nftables firewall: policy drop, LAN-only (nix/system/firewall.nix)
   ├─ sshd: keys only, no root, one user
   ├─ ampberry-tools (Ruby, stdlib only): what the flake cannot express at runtime
   │    settings → /etc/shairport-sync.conf · Wi-Fi onboarding hotspot · metadata daemon ·
   │    control API (root side) · provisioning · redeploy
   └─ ampberry-ui (Ruby on Rails, minimal; shadcn/ui via RubyUI = Phlex + Tailwind 4 + Stimulus):
        home = live log + player bar (play/pause → DACP back to the phone, lib/ampberry/remote.rb)
        · settings (AirPlay + grouped actions + flake revision) · Wi-Fi onboarding (captive only) · API
```

## Security model

- `ampberry` (web UI, metadata daemon) and `shairport-sync` are system users: `nologin`, no
  password, **no sudo, no polkit**. Root exists only at build/activation time and inside the
  socket-activated **control handler**.
- Control API: `ampberry-control.socket` (`/run/ampberry-control.sock`, `root:ampberry` 0660,
  one process per request) → `ampberry control handle`. One JSON request in, one JSON out. The
  peer uid is re-checked (`SO_PEERCRED`), requests are size/time-limited, and only allow-listed
  actions run: built-ins (`settings-apply`, `wifi-*`, `restart-airplay`, `redeploy`,
  `clean-reboot`) plus custom entries in root-owned `/etc/ampberry/actions.json` (`exec` is an
  absolute argv — never a shell, never client arguments). The UI shows them as buttons; the same
  thing is `POST /api/actions/<id>`.
- SSH: `AuthenticationMethods publickey`, `PasswordAuthentication no`, `PermitRootLogin no`,
  `AllowUsers pi` (`/etc/ssh/sshd_config.d/10-ampberry.conf`, from the flake).
- Firewall (nftables, from the flake): from the LAN only — 22, 80, 7000/tcp, 319–320/udp, 5353/udp,
  32768–60999 (AirPlay 2 negotiated); hotspot onboarding on `wlan0` only; IPv6 closed except NDP;
  avahi publishes IPv4 only.
- Updates: `unattended-upgrades` for Debian security only; the stack changes only through the flake.

## Layout

| Path | What |
|---|---|
| `flake.nix`, `nix/` | packages (`shairport-sync.nix`, `ampberry-tools.nix`, `ampberry-ui.nix`) and the system-manager modules (`system/ampberry.nix`, `firewall.nix`, `branding.nix`) |
| `lib/ampberry*.rb`, `bin/ampberry`, `test/` | Ruby tools + minitest suite (`ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].each { require File.expand_path(_1) }'`) |
| `ui/` | Rails app: Phlex views/components (`app/views/**/*.rb`, `app/components/`), RubyUI components generated into `app/components/ruby_ui/` (shadcn's copy-in model), Stimulus controllers via importmap (`app/javascript/`), Tailwind 4 source `app/assets/tailwind/application.css` (theme + the log/player layer) — compiled by the Nix build into `app/assets/builds/tailwind.css`, never committed. `Gemfile.lock` is locked to the `ruby` platform (+ `gemset.nix` via bundix) so native gems build from source in Nix |
| `etc/ampberry/` | `defaults.json` (settings defaults), `actions.json` (custom actions) |
| `cloud-init/` | `user-data.tmpl`, `network-config.tmpl`, `config.txt.fragment` |
| `pi-gen/` | branded image: `config` + `stage-ampberry/` (branding, config.txt, cloud-init seed, flake copy, Nix + pre-built closure) |
| `tools/` | `build-user-data.rb`, `build-image.sh` (local test stage), `apply-live.sh` (in-place migration), `verify.sh` |
| `secrets.env` | Wi-Fi, SSH keys, hotspot PSK, pi password hash — **never committed** (see `secrets.env.example`) |

## Workflows

**Develop & test (Mac):**
```bash
nix shell nixpkgs#ruby_3_4 --command ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
nix build path:$PWD#ampberry-tools    # runs the suite in the sandbox
nix build path:$PWD#ampberry-ui       # bundlerEnv + Tailwind compile + renders every page (smoke test)
```
UI work: `cd ui && bundle install` (gems go to the gitignored `vendor/bundle`), add RubyUI components
with `bin/rails g ruby_ui:component <Name>` (pick ones without CDN JS dependencies — see the gem's
`dependencies.yml`), compile CSS locally with `nix shell nixpkgs#tailwindcss_4 --command tailwindcss
-i app/assets/tailwind/application.css -o app/assets/builds/tailwind.css`, preview with Puma
(`.claude/launch.json` has a ready config pointing at a fake now-playing dir). After touching
`Gemfile`: `bundle lock` (never `--update`: it pulls precompiled platform gems that bundix cannot
build), keep `PLATFORMS` to `ruby`, then `bundix -l`.
Building for the Pi (`aarch64-linux`) needs the nix-darwin `linux-builder` (enabled in `~/nix-config`).

**Local test stage — build the branded image all the way through Nix (Docker, ~45 min):**
```bash
tools/build-image.sh          # → build/pi-gen/deploy/<date>-Ampberry-lite.img.xz
```
pi-gen installs Nix into the chroot and pre-builds the system closure, so a broken flake fails
here, in `build/image-build.log`, before it ever reaches a device.

**Migrate the live device in place (no flash):**
```bash
tools/apply-live.sh --harvest    # once: pi's SSH keys, password hash, network-config → build/
tools/apply-live.sh              # backup → purge hbos → Nix → switch → provision → seed → reboot → verify
tools/apply-live.sh --from-switch  # resume after a failed switch (skips backup/purge/Nix install)
```
The Nix install step sets `trusted-users = root pi` (`/etc/nix/nix.custom.conf`): `--target-host`
copies locally built, unsigned paths into the Pi's store as `pi`, and the daemon refuses them from
an untrusted user ("lacks a signature by a trusted key"). `pi` already has passwordless sudo, so
this grants nothing new.

**Change something later:** edit, test, then push from the Mac — the only deploy path:
```bash
nix run github:numtide/system-manager/release-26.05 -- switch --flake .#ampberry --target-host pi@ampberry.local --sudo
```
The closure is built on the nix-darwin `linux-builder`, copied to the Pi's store over SSH and
activated there. The flake source travels inside the closure (`/opt/ampberry` is a tmpfiles symlink
into the store), so **Redeploy** in Settings (or `sudo ampberry redeploy start`) re-applies exactly
the running source + `ampberry provision` in a transient systemd unit (the system-manager CLI is in
the closure too — `/run/system-manager/sw/bin/system-manager` — so the Pi never compiles it), and the live appliance log
(`/var/log/ampberry.log`, `GET /api/log`) streams as the backdrop of every UI page. Nothing is
rsynced; the cloud-init seed (secrets) is the one file set that never goes through Nix (scp).

**Clean reboot** (Settings): `cloud-init clean --logs` + reboot → first-boot path again from the
seed in `/boot/firmware`: packages, users, activate the recorded closure, `ampberry provision`.
Settings in `/var/lib/ampberry/settings.json` survive unless "reset settings" is ticked.

## Build number

`/etc/ampberry/release` carries `BUILD` = the number of commits in the repo (`self.revCount`), shown
in the Settings overlay as `build N · <rev>`; it is the human-sized handle for "what is running" and
for bumping to / rolling back to a version (`git checkout <commit>` → `system-manager switch`).
Nix only knows the count for a **clean** checkout — deploying with uncommitted changes shows
`build dev` (and `<rev>-dirty`). Commit first if you want a number.

## Settings

`/etc/ampberry/defaults.json` ⊕ `/var/lib/ampberry/settings.json` → `/etc/shairport-sync.conf`.
Editable: `name`, `password`, `interpolation`, `output_format`, `volume_max_db` (default **−6 dB**:
the Amp2 clips and shuts down above it with this supply), `volume_range_db`. There is deliberately
no volume slider: AirPlay volume comes from the phone and is capped by `volume_max_db`.

## Rollback

`tools/apply-live.sh` leaves `build/backup-pre-nix-<stamp>.tgz` + `dpkg --get-selections` and
`apt-mark showmanual` lists. HiFiBerry OS can be reinstalled with its upstream two-liners and
`apt install hbos-full`; Nix is removed with the Determinate installer's `uninstall`. The hardware
path (`config.txt` overlay) is unchanged either way.
