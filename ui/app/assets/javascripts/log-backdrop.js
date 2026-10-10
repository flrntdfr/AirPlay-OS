// The live appliance log (/var/log/ampberry.log). On the home page it is the page: scrollable
// history, following the tail unless you scrolled up. Elsewhere it is a passive backdrop that
// keeps streaming. First request: the last 100 lines (/api/log?tail=100); afterwards it polls
// /api/log?from=<offset> for the new bytes plus the redeploy state. Lines are added one by one,
// a few per frame, so history and new entries alike appear line by line.
(function () {
  const el = document.getElementById("log-backdrop");
  if (!el) return;
  const url = el.dataset.url;
  const home = document.body.classList.contains("player");
  const MAX_LINES = home ? 2000 : 300;
  const TAIL = 100;
  const LINE_EVERY_MS = 16; // one line per frame
  // Lines are "YYYY-MM-DD HH:MM:SS tag  message" (older files: "HH:MM:SS tag  message"). Errors
  // show in red, warnings in the warning colour, the health line in green; the timestamp muted.
  const ERR = /✗|\b(error|fail(ed|ure|s)?|refused|denied|time[d ]?out|unreachable|cannot|not found|rejected|panic|segfault|under-voltage|out of memory|i\/o error|degraded)\b/i;
  const WARN = /\b(warn(ing)?|retry(ing)?|throttl\w*|disconnect\w*|lost|invalid user)\b/i;
  const LINE = /^((?:\d{4}-\d\d-\d\d )?\d\d:\d\d:\d\d) (\S+)\s/;
  let offset = null, partial = "", queue = [], draining = false, hot = false, lastRedeploy = null;
  // follow the tail until the reader scrolls up; scrolling back to the bottom resumes following
  let follow = true;
  el.addEventListener("scroll", () => { follow = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }, { passive: true });

  function spanFor(l) {
    const s = document.createElement("span");
    const m = l.match(LINE);
    if (m) {
      const ts = document.createElement("span");
      ts.className = "ts";
      ts.textContent = m[1];
      s.append(ts, l.slice(m[1].length));
    } else {
      s.textContent = l;
    }
    const tag = m ? m[2] : "";
    if (ERR.test(l)) s.className = "err"; else if (WARN.test(l)) s.className = "warn"; else if (tag === "health") s.className = "ok";
    return s;
  }

  // one line per frame (more when the browser throttled the timer, e.g. a background tab, so
  // the queue never falls behind), the tail kept in view unless the reader scrolled up
  let lastTick = 0;
  function drain() {
    if (!queue.length) { draining = false; lastTick = 0; return; }
    draining = true;
    const now = Date.now();
    const n = lastTick ? Math.max(1, Math.round((now - lastTick) / LINE_EVERY_MS)) : 1;
    lastTick = now;
    for (let i = 0; i < n && queue.length; i++) el.append(spanFor(queue.shift()));
    while (el.childElementCount > MAX_LINES) el.firstElementChild.remove();
    if (follow) el.scrollTop = el.scrollHeight;
    setTimeout(drain, LINE_EVERY_MS);
  }

  function append(chunk) {
    if (!chunk) return;
    const parts = (partial + chunk).split("\n");
    partial = parts.pop(); // bytes after the last newline: an unfinished line, kept for the next poll
    queue.push(...parts);
    if (!draining) drain();
  }

  async function poll() {
    try {
      const r = await fetch(url + (offset === null ? "?tail=" + TAIL : "?from=" + offset), { cache: "no-store" });
      if (!r.ok) return;
      const d = await r.json();
      if (offset !== null && d.from < offset) { queue = []; partial = ""; el.replaceChildren(); } // log rotated: start over
      offset = d.to;
      append(d.chunk);
      const state = d.redeploy && d.redeploy.state;
      const running = state === "running" || state === "starting";
      hot = running;
      document.body.classList.toggle("redeploying", running);
      if (lastRedeploy && (lastRedeploy === "running" || lastRedeploy === "starting") && !running) {
        const job = d.redeploy.kind === "update-shairport" ? "shairport-sync update" : "redeploy";
        append((state === "done" ? "✓ " + job + " finished" : "✗ " + job + " " + state + (d.redeploy.error ? ": " + d.redeploy.error : "")) + "\n");
      }
      lastRedeploy = state;
    } catch (e) { /* UI restarting (a redeploy restarts it): keep what we have */ }
  }

  poll();
  setInterval(poll, 2000);
  setInterval(() => { if (hot) poll(); }, 700);
})();
