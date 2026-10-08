import { Controller } from "@hotwired/stimulus"

// The Settings tab: opens the overlay by cloning the Sheet's <template> into <body>.
// Only ever one overlay: a second tap while the first is still loading must not stack another.
export default class extends Controller {
  static targets = ["content"]
  static values = { open: false }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    if (document.querySelector('[data-controller="ruby-ui--sheet-content"]')) return
    document.body.insertAdjacentHTML("beforeend", this.contentTarget.innerHTML)
  }
}
