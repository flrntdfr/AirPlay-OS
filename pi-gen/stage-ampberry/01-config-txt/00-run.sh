#!/bin/bash -e
# HiFiBerry Amp2 device tree + Bluetooth off, exactly the lines Ampberry::System::ensure_config_txt
# maintains at runtime (keep both lists in sync).
CONFIG="${ROOTFS_DIR}/boot/firmware/config.txt"

# the onboard audio must not claim the ALSA card index
sed -i 's/^\s*dtparam=audio=on\s*$/#dtparam=audio=on   # disabled by ampberry: the HiFiBerry HAT is the audio device/' "${CONFIG}"

missing=()
for line in 'dtparam=audio=off' 'dtoverlay=hifiberry-dacplus-std' 'dtparam=i2c_arm=on' 'dtoverlay=disable-bt'; do
	grep -qxF "${line}" "${CONFIG}" || missing+=("${line}")
done

if [ "${#missing[@]}" -gt 0 ]; then
	# append under a trailing [all] section unless the file already ends in one
	last_section="$(grep -E '^\s*\[' "${CONFIG}" | tail -1 || true)"
	{
		echo
		[ "${last_section}" = "[all]" ] || echo "[all]"
		echo "# Ampberry v2 (HiFiBerry Amp2, Bluetooth off)"
		printf '%s\n' "${missing[@]}"
	} >> "${CONFIG}"
fi
log "config.txt: added ${#missing[@]} line(s)"
