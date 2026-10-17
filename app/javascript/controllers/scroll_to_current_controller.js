import { Controller } from "@hotwired/stimulus"

// Scrolls a horizontally overflowing row so its aria-current item is in view.
export default class extends Controller {
  connect() {
    const current = this.element.querySelector("[aria-current]")
    if (!current) return

    const overflow = current.offsetLeft + current.offsetWidth - this.element.clientWidth
    if (overflow > 0) this.element.scrollLeft = overflow + 16
  }
}
