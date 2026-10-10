import { Controller } from "@hotwired/stimulus"

// The open Settings pane (cloned out of the Sheet's <template>). Closes on a tap/click anywhere
// outside the pane — the dimmed backdrop below the top bar, or the bar itself — and on Escape.
// Listeners are attached directly (capture phase) rather than relying on Stimulus action
// resolution for content that arrives later through the Turbo Frame; iOS Safari also does not
// always turn a tap on a plain <div> into a click, hence touchend as well.
export default class extends Controller {
  connect() {
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    this.onTap = (e) => {
      if (e.target === this.backdrop) { e.preventDefault(); this.close() }
    }
    // the top bar is not covered by the backdrop: a tap there closes the pane too — except on a
    // link (it navigates) and on the Settings tab itself (sheet_controller.js toggles the pane;
    // its opening click is still bubbling when this listener is attached)
    this.onBarTap = (e) => {
      if (!e.target.closest('a, [data-controller="ruby-ui--sheet"]')) this.close()
    }
    this.bar = document.querySelector("body > header")
    document.addEventListener("keydown", this.onKey)
    this.element.addEventListener("click", this.onTap, true)
    this.element.addEventListener("touchend", this.onTap, true)
    if (this.bar) this.bar.addEventListener("click", this.onBarTap)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.element.removeEventListener("click", this.onTap, true)
    this.element.removeEventListener("touchend", this.onTap, true)
    if (this.bar) this.bar.removeEventListener("click", this.onBarTap)
    document.body.classList.remove("overflow-hidden")
  }

  get backdrop() { return this.element.firstElementChild }

  close() {
    this.element.remove()
  }
}
