import { Controller } from "@hotwired/stimulus"

// "Check for updates" in the AirPlay card: POST /updates/check, then rewrite the status badge.
// The daily timer (ampberry-updates) does the same on its own.
// Connects to data-controller="updates"; targets: badge, link; value: url
export default class extends Controller {
  static targets = ["badge", "link"]
  static values = { url: String }

  async check(e) {
    e.preventDefault()
    this.linkTarget.textContent = "Checking…"
    try {
      const r = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      this.render(await r.json())
    } catch (err) {
      this.render({ error: String(err) })
    } finally {
      this.linkTarget.textContent = "Check for updates"
    }
  }

  render(s) {
    const b = this.badgeTarget
    b.className = b.dataset.base
    if (s.error) { b.textContent = "✗ check failed"; b.classList.add(...b.dataset.warn.split(" ")) }
    else if (s.up_to_date) { b.textContent = "✓ up to date"; b.classList.add(...b.dataset.ok.split(" ")) }
    else if (s.latest) { b.textContent = "↑ " + s.latest + " available"; b.classList.add(...b.dataset.warn.split(" ")) }
    else { b.textContent = "not checked yet" }
  }
}
