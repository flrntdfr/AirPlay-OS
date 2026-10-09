// Player bar: poll the snapshot the metadata daemon writes, update the DOM, extrapolate progress,
// and send play/pause back to the sender (POST /player/toggle → DACP).
(function () {
  const el = document.getElementById("player");
  if (!el) return;
  const url = el.dataset.nowPlayingUrl, toggleUrl = el.dataset.toggleUrl, csrf = el.dataset.csrf, coverBase = el.dataset.coverBase;
  const $ = (id) => document.getElementById(id);
  let snap = null, snapAt = 0, pending = false, holdUntil = 0, pausedByUs = false, coverFile = $("cover").getAttribute("src");

  function renderCover() {
    const file = snap.cover_file ? coverBase + snap.cover_file : null;
    if (file === coverFile) return;
    coverFile = file;
    for (const id of ["cover", "cover-full"]) { if (file) $(id).src = file; else $(id).removeAttribute("src"); }
    el.classList.toggle("has-cover", !!file);
  }

  function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

  function render() {
    if (!snap) return;
    el.classList.toggle("active", !!snap.active);
    el.classList.toggle("idle", !snap.active);
    el.classList.toggle("playing", !!snap.playing);
    // The bar shows while something plays. Paused from here → it stays, offering play. Paused or
    // stopped from the source → it hides.
    if (snap.playing || !snap.active) pausedByUs = false;
    const visible = !!snap.active && (!!snap.playing || pausedByUs);
    el.classList.toggle("shown", visible);
    document.body.classList.toggle("has-player", visible);
    $("title").textContent = snap.active ? (snap.title || "…") : (document.title.replace(/ ·.*/, "") || "Ampberry");
    $("artist").textContent = [snap.artist, snap.album].filter(Boolean).join(" · ");
    $("status").textContent = snap.active
      ? (snap.playing ? "Playing" : "Paused") + (snap.client ? " · from " + snap.client : "")
      : "Ready for AirPlay";
    $("toggle").disabled = !snap.active;
    // the dot in the top bar: green ready, red (bouncing) playing, orange paused, grey unknown
    const dot = $("live-dot");
    if (dot) dot.className = "live-dot " + (snap.stale ? "unknown" : !snap.active ? "ready" : snap.playing ? "playing" : "paused");
    renderCover();
    tick();
  }

  function tick() {
    if (!snap || !snap.duration_s || snap.position_s == null) { $("bar").style.width = "0"; return; }
    const elapsed = snap.playing ? (Date.now() - snapAt) / 1000 : 0;
    const pos = Math.min(snap.duration_s, snap.position_s + elapsed);
    $("bar").style.width = (100 * pos / snap.duration_s).toFixed(2) + "%";
    $("progress").title = fmt(pos) + " / " + fmt(snap.duration_s);
  }

  async function poll() {
    try {
      const r = await fetch(url, { cache: "no-store" });
      if (!r.ok) return;
      const fresh = await r.json();
      // right after a toggle the sender's state arrives with a small delay: keep our optimistic state
      if (Date.now() < holdUntil && snap) fresh.playing = snap.playing;
      snap = fresh; snapAt = Date.now(); render();
    } catch (e) { /* offline or restarting: keep the last state */ }
  }

  $("toggle").addEventListener("click", async () => {
    if (pending || !snap || !snap.active) return;
    pending = true;
    const was = snap.playing;
    pausedByUs = !!was; // pausing from the bar keeps the bar; the next resume clears the flag
    // keep our state until the sender has reported the change (a pause takes it a moment longer)
    snap.playing = !was; snapAt = Date.now(); holdUntil = Date.now() + (was ? 5000 : 2500); render();
    try {
      const r = await fetch(toggleUrl, { method: "POST", headers: { "X-CSRF-Token": csrf, "Accept": "application/json" } });
      const res = await r.json();
      if (!res.ok) { snap.playing = was; pausedByUs = false; holdUntil = 0; render(); $("status").textContent = "✗ " + res.error; }
    } catch (e) {
      snap.playing = was; pausedByUs = false; holdUntil = 0; render(); $("status").textContent = "✗ " + e;
    } finally { pending = false; }
  });

  poll();
  setInterval(poll, 1000);
  setInterval(tick, 500);
})();
