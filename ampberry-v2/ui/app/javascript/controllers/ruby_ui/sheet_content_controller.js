import { Controller } from "@hotwired/stimulus"

// The open Settings panel (cloned out of the Sheet's <template>). Closes on the cross
// ([data-close-sheet] inside the frame), on a tap/click on the dimmed backdrop, and on Escape.
// Listeners are attached directly to the wrapper (capture phase) rather than relying on Stimulus
// action resolution for content that arrives later through the Turbo Frame; iOS Safari also
// does not always turn a tap on a plain <div> into a click, hence touchend as well.
export default class extends Controller {
  connect() {
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    this.onTap = (e) => {
      const t = e.target
      if (t === this.backdrop || (t.closest && t.closest("[data-close-sheet]"))) {
        e.preventDefault()
        this.close()
      }
    }
    document.addEventListener("keydown", this.onKey)
    this.element.addEventListener("click", this.onTap, true)
    this.element.addEventListener("touchend", this.onTap, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.element.removeEventListener("click", this.onTap, true)
    this.element.removeEventListener("touchend", this.onTap, true)
    document.body.classList.remove("overflow-hidden")
  }

  get backdrop() { return this.element.firstElementChild }

  close() {
    this.element.remove()
  }
}
