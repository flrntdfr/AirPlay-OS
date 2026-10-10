# AirPlay OS

[![arm | aarch64](https://img.shields.io/github/actions/workflow/status/flrntdfr/AirPlay-OS/release.yml?logo=arm&label=aarch64)](https://github.com/flrntdfr/AirPlay-OS/actions/workflows/release.yml)

[AirPlay OS](./) is a lightweight<sup>*</sup> linux distribution of  [AirPlay as Flake](./flake.nix) on Raspberry Pi.

## Installation

You already have an appliance connected to the network, use the skill:

``` txt
Claude skill
```

If you prefer to flash the device:

```bash
# Fetch the latest version
wget -O /tmp/airplay-os.img.xz https://github.com/flrntdfr/AirPlay-OS/releases/latest/download/airplay-os.img.xz

# Flash to drive: macOS (/dev/diskN, see `diskutil list`) or Linux (/dev/sdX or /dev/mmcblkN, see `lsblk`)
tools/flash.sh /dev/<your-sd-card> /tmp/airplay-os.img.xz
```

Then refer to [connect to the network](./docs/NETWORK.md).

## Development

Refer to [development](./docs/DEVELOPMENT.md).

## Architecture

```
               iPhone · Mac                               browser
                    │ AirPlay 2                              │ http :80
 ───────────────────┼────────────────────────────────────────┼──────────────────
                    ▼                                        ▼
  ┌─ receiver ────────────────────────┐    ┌─ web ui ──────────────────────────┐
  │ nqptp             udp 319 · 320   │    │ airplay-os-ui  Rails · Phlex · TW4│
  │ shairport-sync    tcp 7000        │    │ airplay-os · no shell · no sudo   │
  └───┬───────────────────────────────┘    └─────────────────┬─────────────────┘
      │ metadata pipe                                        │ unix socket · JSON
      ▼                                                      ▼
  ┌─ metadata ────────────────────────┐    ┌─ control@ ────────────────────────┐
  │ now-playing.json                  │    │ root · SO_PEERCRED · allow-list   │
  │ play · pause · stop  →  journal   │    │ settings · wifi · network         │
  │ one line per transition           │    │ restart · redeploy · reboot       │
  └───────────────────────────────────┘    └───────────────────────────────────┘
  ┌─ timers ──────────────────────────┐    ┌─ log ─────────────────────────────┐
  │ health    :00 :15 :30 :45         │    │ journal ─▶ /var/log/airplay-os.log│
  │ updates   daily                   │    │ 100 lines on load · then streamed │
  │ wifi      every 3 min             │    │ errors red · warnings orange      │
  └───────────────────────────────────┘    └───────────────────────────────────┘

 ┌────────────────────────┬────────────────────────────────────────────────────┐
 │ airplay-os             │ provision · settings · wifi · network · control    │
 │ ruby 3.4 · stdlib      │ metadata · log · health · updates · redeploy       │
 ├────────────────────────┼────────────────────────────────────────────────────┤
 │ nix flake              │ packages · units · /etc · firewall · branding      │
 │ system-manager         │ /opt/airplay-os → /nix/store · systemConfigs.<id>  │
 ├────────────────────────┼────────────────────────────────────────────────────┤
 │ state                  │ /var/lib/airplay-os/settings.json                  │
 │ outside nix            │ /etc/shairport-sync.conf (rendered) · NM profiles  │
 ├────────────────────────┼────────────────────────────────────────────────────┤
 │ raspberry pi os lite   │ kernel · firmware · apt · NetworkManager · avahi   │
 │ debian base            │ sshd · cloud-init first boot · unattended-upgrades │
 ├────────────────────────┼────────────────────────────────────────────────────┤
 │ hardware               │ raspberry pi · HiFiBerry HAT · ALSA hw:0           │
 └────────────────────────┴────────────────────────────────────────────────────┘
```

---

<sup>*</sup> < 800 MB.