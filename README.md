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

# Flash to drive
dd /tmp/airplay-os.img.xz /dev/to/your/sd/card
```

Then consult [connect to the network](./docs/NETWORK.md).

## Development

Consult [development](./docs/DEVELOPMENT.md).

## Credits

- raspberry-pi-imag
- Cloud-init
- Ruby API and CLI
- Ruby on Rails
- shadcn-ui
- Nix Flake
- Github action

---

<sup>*</sup> < 1 GB