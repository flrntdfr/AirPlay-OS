// The live appliance log (/var/log/ampberry.log). On the home page it is the page: scrollable
// history, following the tail unless you scrolled up. Elsewhere it is a passive backdrop that
// keeps streaming. Polls /api/log?from=<offset>; the server returns only the new bytes plus the
// redeploy state.
(function () {
  const el = document.getElementById("log-backdrop");
  if (!el) return;
  const url = el.dataset.url;
  const home = document.body.classList.contains("player");
  const MAX_LINES = home ? 2000 : 300;
  // Lines are "HH:MM:SS tag  message". Errors show in red, warnings in the warning colour.
  const ERR = /✗|\b(error|fail(ed|ure|s)?|refused|denied|time[d ]?out|unreachable|cannot|not found|rejected|panic|segfault|under-voltage|out of memory|i\/o error)\b/i;
  const WARN = /\b(warn(ing)?|retry(ing)?|throttl\w*|disconnect\w*|lost|invalid user)\b/i;
  let offset = 0, lines = [], hot = false, lastRedeploy = null;

  const atBottom = () => !home || el.scrollHeight - el.scrollTop - el.clientHeight < 24;

  function render(follow) {
    el.replaceChildren(...lines.map((l) => {
      const s = document.createElement("span");
      s.textContent = l;
      if (ERR.test(l)) s.className = "err"; else if (WARN.test(l)) s.className = "warn";
      return s;
    }));
    if (follow) el.scrollTop = el.scrollHeight;
  }

  function append(chunk) {
    if (!chunk) return;
    const follow = atBottom();
    const parts = chunk.split("\n");
    if (lines.length && !lines[lines.length - 1].endsWith("\n")) lines[lines.length - 1] += parts.shift();
    for (const p of parts) if (p !== "" || parts.indexOf(p) < parts.length - 1) lines.push(p);
    if (lines.length > MAX_LINES) lines = lines.slice(-MAX_LINES);
    render(follow);
  }

  async function poll() {
    try {
      const r = await fetch(url + "?from=" + offset, { cache: "no-store" });
      if (!r.ok) return;
      const d = await r.json();
      if (d.from < offset) { lines = []; el.replaceChildren(); } // log rotated: start over
      offset = d.to;
      append(d.chunk);
      const state = d.redeploy && d.redeploy.state;
      const running = state === "running" || state === "starting";
      hot = running;
      document.body.classList.toggle("redeploying", running);
      if (lastRedeploy && (lastRedeploy === "running" || lastRedeploy === "starting") && !running) {
        append("\n" + (state === "done" ? "✓ redeploy finished" : "✗ redeploy " + state + (d.redeploy.error ? ": " + d.redeploy.error : "")) + "\n");
      }
      lastRedeploy = state;
    } catch (e) { /* UI restarting (a redeploy restarts it): keep what we have */ }
  }

  poll();
  setInterval(poll, 2000);
  setInterval(() => { if (hot) poll(); }, 700);
})();
