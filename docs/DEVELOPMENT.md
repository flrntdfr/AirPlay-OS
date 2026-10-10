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
docker run airplay-os tests --remote airplay-os.lan
```

### Deploy

```
docker run airplay-os deploy --version 1.1.0 airplay-os.lan
```
