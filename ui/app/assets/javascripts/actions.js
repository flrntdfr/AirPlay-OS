// Settings page: any element with data-action-id → POST /api/actions/<id> (the control API) and
// show the result in #action-output. Confirmations are shadcn AlertDialogs (their action button
// carries the same attribute and dismisses itself), so no window.confirm here.
(function () {
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  let busy = false;

  document.addEventListener("click", async (ev) => {
    const btn = ev.target.closest("[data-action-id]");
    if (!btn || busy) return;
    // the output lives inside the Settings frame, which is loaded on demand
    const out = document.getElementById("action-output");
    if (!out) return;
    const id = btn.dataset.actionId;
    busy = true;
    out.hidden = false;
    out.textContent = "Running " + id + "…";
    try {
      const r = await fetch("/api/actions/" + id, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token || "" },
        body: JSON.stringify({ params: {} })
      });
      const res = await r.json();
      out.textContent = res.ok
        ? ("✓ " + id + "\n" + (res.result && res.result.output ? res.result.output : JSON.stringify(res.result, null, 2)))
        : ("✗ " + id + ": " + res.error + (res.output ? "\n" + res.output : ""));
      if (res.ok && id === "reboot") waitForReturn(out);
    } catch (e) {
      out.textContent = "✗ " + id + ": " + e;
    } finally {
      busy = false;
    }
  });

  function waitForReturn(out) {
    out.textContent += "\n\nRebooting… this page reloads when Ampberry is back.";
    const started = Date.now();
    const timer = setInterval(async () => {
      if (Date.now() - started < 20000) return; // give it time to actually go down
      try {
        const r = await fetch("/health", { cache: "no-store" });
        if (r.ok) { clearInterval(timer); location.reload(); }
      } catch (e) { /* still down */ }
    }, 3000);
  }
})();
