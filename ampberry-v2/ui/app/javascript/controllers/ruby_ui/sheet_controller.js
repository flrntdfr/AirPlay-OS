import { Controller } from "@hotwired/stimulus"

// The Settings tab: opens the pane by cloning the Sheet's <template> into <body>; a tap while
// it is open closes it. Only ever one pane, never a second one stacked on top.
export default class extends Controller {
  static targets = ["content"]
  static values = { open: false }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    const open = document.querySelector('[data-controller="ruby-ui--sheet-content"]')
    if (open) { open.remove(); return }
    document.body.insertAdjacentHTML("beforeend", this.contentTarget.innerHTML)
  }
}
