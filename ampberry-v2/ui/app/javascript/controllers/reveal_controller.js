import { Controller } from "@hotwired/stimulus"

// Eye toggle on a password field: shows/hides the characters.
// Connects to data-controller="reveal"; targets: input, on (eye), off (eye-off)
export default class extends Controller {
  static targets = ["input", "on", "off"]

  toggle() {
    const shown = this.inputTarget.type === "text"
    this.inputTarget.type = shown ? "password" : "text"
    this.onTarget.classList.toggle("hidden", !shown)
    this.offTarget.classList.toggle("hidden", shown)
  }
}
