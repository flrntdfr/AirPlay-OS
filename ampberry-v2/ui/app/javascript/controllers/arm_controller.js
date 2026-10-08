import { Controller } from "@hotwired/stimulus"

// "I really mean it": the button stays disabled until the box is ticked.
// Connects to data-controller="arm"
export default class extends Controller {
  static targets = ["box", "button"]

  connect() { this.toggle() }

  toggle() {
    this.buttonTarget.disabled = !this.boxTarget.checked
  }
}
