import { Controller } from "@hotwired/stimulus"

// The update button in the AirPlay card (see Views::Settings::Show#version_line).
//   state ok / error / unknown → a tap checks:  POST /updates/check → { up_to_date, latest, error }
//   state available            → a tap updates: POST /api/actions/update-shairport (the job runs
//                                in the background), then GET /updates/status every few seconds
//                                until job.state leaves running; done → the fresh status.
// While busy the button shows a spinner and "Checking…" / "Updating…" at the same size.
// Connects to data-controller="updates"; values: check-url, status-url, apply-url, state,
// latest, tones (state → classes), labels (state → [rest, hover]).
export default class extends Controller {
  static targets = ["button", "spinner", "rest", "hover"]
  static values = { checkUrl: String, statusUrl: String, applyUrl: String, state: String, latest: String, tones: Object, labels: Object }

  connect() {
    this.state = this.stateValue
    this.latest = this.latestValue
    this.resume()
  }

  disconnect() { clearTimeout(this.timer) }

  // the pane was (re)opened while an update is running: pick it up
  async resume() {
    try {
      const s = await (await fetch(this.statusUrlValue, { cache: "no-store" })).json()
      if (s.job && s.job.kind === "update-shairport" && (s.job.state === "starting" || s.job.state === "running")) this.watch()
    } catch (e) { /* offline: keep the rendered state */ }
  }

  tap() {
    if (this.busy) return
    if (this.state === "available") this.update(); else this.check()
  }

  async check() {
    this.setBusy("Checking…")
    try {
      const r = await fetch(this.checkUrlValue, { method: "POST", headers: this.headers })
      this.apply(await r.json())
    } catch (e) {
      this.apply({ error: String(e) })
    }
  }

  async update() {
    this.setBusy("Updating…")
    try {
      const r = await fetch(this.applyUrlValue, { method: "POST", headers: this.headers })
      const res = await r.json()
      if (!res.ok) { this.show("error", "✗ " + (res.error || r.status), res.error); return }
      this.watch()
    } catch (e) {
      this.show("error", "✗ " + e, String(e))
    }
  }

  watch() {
    this.setBusy("Updating…")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.poll(), 3000)
  }

  async poll() {
    try {
      const s = await (await fetch(this.statusUrlValue, { cache: "no-store" })).json()
      const st = s.job && s.job.state
      if (st === "starting" || st === "running") { this.timer = setTimeout(() => this.poll(), 3000); return }
      if (st === "done") this.apply(s)
      else this.show("error", "✗ update " + (st || "failed"), s.job && s.job.error)
    } catch (e) {
      this.timer = setTimeout(() => this.poll(), 3000) // the UI may restart during the switch
    }
  }

  apply(s) {
    if (s.error) this.show("error", "✗ check failed", s.error)
    else if (s.up_to_date) this.show("ok")
    else if (s.latest) { this.latest = s.latest; this.show("available") }
    else this.show("unknown")
  }

  setBusy(text) {
    this.busy = true
    this.paint("busy")
    this.restTarget.textContent = text
    this.hoverTarget.textContent = text
    this.spinnerTarget.classList.remove("hidden")
    this.buttonTarget.disabled = true
  }

  show(state, rest, title) {
    this.busy = false
    this.state = state
    this.paint(state)
    const [atRest, onHover] = this.labelsValue[state] || this.labelsValue.unknown
    this.restTarget.textContent = rest || atRest.replace("%s", this.latest)
    this.hoverTarget.textContent = onHover
    this.spinnerTarget.classList.add("hidden")
    this.buttonTarget.disabled = false
    this.buttonTarget.title = title || ""
  }

  paint(state) {
    const b = this.buttonTarget
    b.className = b.dataset.base + " " + (this.tonesValue[state] || "")
  }

  get headers() {
    return { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
  }
}
