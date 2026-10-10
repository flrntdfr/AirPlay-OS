import { Controller } from "@hotwired/stimulus"

// Arming chain for the confirm rows of an actions table (Reboot, then Redeploy):
// the first "Ok" box enables its own button and the next row's box; that box enables its button.
// Unticking a box disarms everything after it.
// Connects to data-controller="arm" on the table; rows contribute box/button targets in order.
export default class extends Controller {
  static targets = ["box", "button"]

  connect() { this.toggle() }

  toggle() {
    let armed = true
    this.boxTargets.forEach((box, i) => {
      box.disabled = !armed
      if (!armed) box.checked = false
      const on = armed && box.checked
      const button = this.buttonTargets[i]
      if (button) button.disabled = !on
      armed = on
    })
  }
}
