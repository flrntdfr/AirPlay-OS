# shairport-sync for the Ampberry appliance: AirPlay 2 only, ALSA + soxr + Avahi, metadata pipe.
# Based on nixpkgs-unstable's expression (5.5.2); nixpkgs passes --with-metadata but not
# --with-metadata-pipe, and enables every audio backend — both are changed here, which is why
# this derivation is built by our Linux builder instead of being fetched from the cache.
{ unstable, lib }:

(unstable.shairport-sync.override {
  enableAirplay2 = true;
  # AirPlay 2 needs ffmpeg for ALAC/AAC decoding; the headless variant keeps GTK/GStreamer/SDL
  # out of the appliance closure.
  ffmpeg = unstable.ffmpeg-headless;
  enableAlsa = true;
  enableSoxr = true;
  enableAvahi = true;
  enableMetadata = true;
  # unused on an appliance with one DAC
  enablePulse = false;
  enablePipewire = false;
  enableJack = false;
  enableSoundio = false;
  enableAo = false;
  enableSndio = false;
  enableStdout = false;
  enablePipe = false;
  enableMqttClient = false;
  enableMpris = false;
  enableDbus = false;
  enableConvolution = false;
  enableTinySVCmDNS = false;
  enableLibdaemon = false;
}).overrideAttrs
  (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "--with-metadata-pipe" ];
    meta = (old.meta or { }) // {
      description = "Shairport Sync 5.5.2 — Ampberry build (AirPlay 2, ALSA, soxr, Avahi, metadata pipe)";
      platforms = lib.platforms.linux;
    };
  })
