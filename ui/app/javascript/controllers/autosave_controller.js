import { Controller } from "@hotwired/stimulus"

// Save a settings form without an Apply button: fields with
// data-action="input->autosave#changed" (or change->) save `delay` ms after the last change;
// Enter submits through the same path. POST goes to the form's action with
// Accept: application/json → { ok, error }. A saved AirPlay name also renames the brand in the
// top bar ([data-brand]) — the box is called what the receiver is called.
// Connects to data-controller="autosave" on the <form>.
export default class extends Controller {
  static targets = ["status"]
  static values = { delay: { type: Number, default: 1000 } }

  disconnect() { clearTimeout(this.timer) }

  changed() {
    clearTimeout(this.timer)
    this.show("…")
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  submit(e) { e.preventDefault(); clearTimeout(this.timer); this.save() }

  async save() {
    clearTimeout(this.timer)
    const form = this.element
    this.show("Saving…")
    try {
      const r = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      const res = await r.json()
      if (res.ok) {
        this.show("Saved", true)
        const name = form.elements["settings[name]"]
        if (name && name.value.trim()) document.querySelectorAll("[data-brand]").forEach((el) => { el.textContent = name.value.trim() })
        form.dispatchEvent(new CustomEvent("autosave:saved", { bubbles: true }))
      } else {
        this.show("✗ " + (res.error || r.status))
      }
    } catch (e) {
      this.show("✗ " + e)
    }
  }

  show(text, fade = false) {
    if (!this.hasStatusTarget) return
    clearTimeout(this.fadeTimer)
    this.statusTarget.textContent = text
    if (fade) this.fadeTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 2500)
  }
}
