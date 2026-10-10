# AirPlay OS

[![build](https://github.com/flrntdfr/AirPlay-OS/actions/workflows/release.yml/badge.svg)](https://github.com/flrntdfr/AirPlay-OS/actions/workflows/release.yml)
[![architecture](https://img.shields.io/badge/architecture-aarch64_passing-brightgreen?logo=arm)](./flake.nix)

[AirPlay OS](./) is a lightweight<sup>*</sup> linux distribution for Arm of  [AirPlay as Flake](./flake.nix).

<sup>*</sup> < 1 GB

## Installation

You already have an appliance connected to the network, use the skill:

``` txt
[Claude skill]
```

If you prefer to flash the device:

```
# Fetch the latest version (v1)
wget -O /tmp/airplay-os.img.xz https://github.com/flrntdfr/AirPlay-OS/releases/download/v1/airplay-os.img.xz

# Flash to drive
dd /tmp/airplay-os.img.xz /dev/to/your/sd/card
```

Then consult [connect to the network](./docs/NETWORK.md).

## Development

Consult [development](./docs/DEVELOPMENT.md)