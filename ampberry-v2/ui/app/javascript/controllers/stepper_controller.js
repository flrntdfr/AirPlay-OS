import { Controller } from "@hotwired/stimulus"

// A −/+ stepper around a number input (honours its min / max / step).
// Connects to data-controller="stepper"
export default class extends Controller {
  static targets = ["input"]

  down() { this.step(-1) }
  up() { this.step(1) }

  step(direction) {
    const i = this.inputTarget
    const step = parseFloat(i.step) || 1
    const min = i.min === "" ? -Infinity : parseFloat(i.min)
    const max = i.max === "" ? Infinity : parseFloat(i.max)
    const current = i.value === "" ? 0 : parseFloat(i.value)
    const next = Math.min(max, Math.max(min, current + direction * step))
    i.value = Number.isInteger(step) ? String(Math.round(next)) : String(next)
    i.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
