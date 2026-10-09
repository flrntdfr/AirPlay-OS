// The player in the top bar: poll the snapshot the metadata daemon writes, update title/artist
// and the play/pause button, keep the "• Live" dot current, and send play/pause back to the
// sender (POST /player/toggle → DACP).
(function () {
  const el = document.getElementById("player");
  if (!el) return;
  const url = el.dataset.nowPlayingUrl, toggleUrl = el.dataset.toggleUrl, csrf = el.dataset.csrf;
  const $ = (id) => document.getElementById(id);
  let snap = null, pending = false, holdUntil = 0, pausedByUs = false;

  function render() {
    if (!snap) return;
    el.classList.toggle("playing", !!snap.playing);
    // Shown while something plays. Paused from here → it stays, offering play. Paused or
    // stopped from the source → it hides.
    if (snap.playing || !snap.active) pausedByUs = false;
    el.classList.toggle("shown", !!snap.active && (!!snap.playing || pausedByUs));
    $("title").textContent = snap.active ? (snap.title || snap.client || "…") : "";
    $("artist").textContent = snap.active && snap.artist ? " · " + snap.artist : "";
    $("toggle").disabled = !snap.active;
    // the dot in the top bar: green ready, red (bouncing) playing, orange paused, grey unknown
    const dot = $("live-dot");
    if (dot) dot.className = "live-dot " + (snap.stale ? "unknown" : !snap.active ? "ready" : snap.playing ? "playing" : "paused");
  }

  async function poll() {
    try {
      const r = await fetch(url, { cache: "no-store" });
      if (!r.ok) return;
      const fresh = await r.json();
      // right after a toggle the sender's state arrives with a small delay: keep our optimistic state
      if (Date.now() < holdUntil && snap) fresh.playing = snap.playing;
      snap = fresh; render();
    } catch (e) { /* offline or restarting: keep the last state */ }
  }

  $("toggle").addEventListener("click", async () => {
    if (pending || !snap || !snap.active) return;
    pending = true;
    const was = snap.playing;
    pausedByUs = !!was; // pausing from the bar keeps the bar; the next resume clears the flag
    // keep our state until the sender has reported the change (a pause takes it a moment longer)
    snap.playing = !was; holdUntil = Date.now() + (was ? 5000 : 2500); render();
    try {
      const r = await fetch(toggleUrl, { method: "POST", headers: { "X-CSRF-Token": csrf, "Accept": "application/json" } });
      const res = await r.json();
      if (!res.ok) { snap.playing = was; pausedByUs = false; holdUntil = 0; render(); $("artist").textContent = " · ✗ " + res.error; }
    } catch (e) {
      snap.playing = was; pausedByUs = false; holdUntil = 0; render(); $("artist").textContent = " · ✗ " + e;
    } finally { pending = false; }
  });

  poll();
  setInterval(poll, 1000);
})();
