# AirPlay OS
> Stream AirPlay to Raspberries.

## Introduction

[AirPlay OS](./) is a lightweight linux distribution

- rpi-image-gen (optional)
- nix (optional)
- Ruby (optional) and ruby on rails
- Driver for HifiBerry, tested on Amp and Hifiberry HAT

## Setup

[Claude skill]

### Flash the SD Card

- Use the Raspberry pi imager and this URL — every commit on `main` becomes a release `vN`
  ([releases](https://github.com/flrntdfr/AirPlay-OS/releases)); right-click its `link`, copy, and
  paste it in the Imager (Use custom). The Imager's customization (user, SSH key, Wi‑Fi,
  hostname) applies as usual; the image activates itself on first boot.
- If using wireless AirPlay:
  - Connect to the wifi named "Bonjour" (only advertised 1h after boot stop unless connected to wifi)
  - open https://ampberry.local and setup wifi
- 

## Development

### Build

```sh
cp secrets.env.example secrets.env
docker build airplay-os
```

**Configuration**

```env
# secrets.env

# == System ==
TIMEZONE="Europe/Paris"

# == WIFI==
WIFI_SSID="Wifi de la maison"
WIFI_PSK="******************" # Connect directly to network on boot…
WIFI_COUNTRY="FR"
# SETUP_PSK="bonjour" # … or Start in setup mode on http://airplay.local

# == user ==
SSH_AUTHORIZED_KEYS="ssh-ed25519 AAAA... you@host"
PI_PASSWORD_HASH="" # getent shadow pi | cut -d: -f2
```

### Test

```
# Test locally in Docker
docker run airplay-os tests --local

# Test remotely on the Raspberry
docker run airplay-os tests --remote ampberry.lan
```

### Deploy

```
docker run airplay-os deploy --version 1.1.0 ampberry.lan
```

## Devices

One definition per device in [`devices/`](./devices/) (`<id>.json`: hostname, HAT, radios, LAN,
defaults) and one record of what is installed (`<Id>.md`). Everything done to a device is logged in
[`OPERATIONS.md`](./OPERATIONS.md).

| Device | Hardware | Status |
|---|---|---|
| [Ampberry](./devices/Ampberry.md) | Pi 3B + HiFiBerry Amp2, Wi‑Fi | AirPlay OS build 40 (`v34` tagged at build 34) |
| [HifiBerry](./devices/HifiBerry.md) | Pi 4B + HiFiBerry DAC+, Ethernet | AirPlay OS build 40 (since 2026-10-10, build 38) |

## What works today (Nix)

The Docker commands above are the goal; today the OS is built and deployed with Nix from the
repo root (see [`docs/architecture.md`](./docs/architecture.md)):

```sh
# test (Mac)
nix shell nixpkgs#ruby_3_4 --command ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
nix build .#ampberry-ui                     # renders every page of the web UI as a check

# deploy a device (builds on the nix-darwin linux-builder, pushes the closure over SSH)
nix run github:numtide/system-manager/release-26.05 -- switch --flake .#ampberry --target-host pi@ampberry.local --sudo
DEVICE=ampberry tools/verify.sh

# migrate a box that still runs HiFiBerry OS NG (interactive)
DEVICE=hifiberry AMPBERRY_HOST=pi@HifiBerry.local tools/apply-live.sh
```