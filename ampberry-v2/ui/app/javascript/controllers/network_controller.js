import { Controller } from "@hotwired/stimulus"

// The Network card: a switch per interface (POST /api/actions/network-set, refused by the
// control side when it would lock the user out) and "Connect" for a Wi‑Fi network
// (POST /api/actions/wifi-connect). After either, the Settings frame reloads so the rows show
// what NetworkManager now reports.
// Connects to data-controller="network"; targets: status, ssid, psk; values: set-url, connect-url
export default class extends Controller {
  static targets = ["status", "ssid", "psk"]
  static values = { setUrl: String, connectUrl: String }

  async toggle(e) {
    const input = e.currentTarget, iface = input.dataset.iface, enabled = input.checked
    input.disabled = true
    this.say((enabled ? "Switching on " : "Switching off ") + iface + "…")
    const res = await this.post(this.setUrlValue, { iface, enabled })
    if (res.ok) { this.say("Done"); this.reload() }
    else { input.checked = !enabled; input.disabled = false; this.say("✗ " + res.error) }
  }

  async connect(e) {
    e.preventDefault()
    const ssid = this.ssidTarget.value.trim(), psk = this.pskTarget.value
    if (!ssid) { this.say("Enter the network's name"); return }
    this.say("Joining " + ssid + "… (up to a minute)")
    const res = await this.post(this.connectUrlValue, { ssid, psk })
    if (res.ok) { this.say("Joined " + ssid); this.reload() }
    else this.say("✗ " + res.error)
  }

  async post(url, params) {
    try {
      const r = await fetch(url, {
        method: "POST",
        headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ params })
      })
      return await r.json()
    } catch (err) {
      return { ok: false, error: String(err) }
    }
  }

  say(text) { if (this.hasStatusTarget) this.statusTarget.textContent = text }

  // NetworkManager needs a moment to settle before the rows are worth re-reading
  reload() { setTimeout(() => document.getElementById("settings")?.reload(), 1500) }
}
