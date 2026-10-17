import { Controller } from "@hotwired/stimulus"

// Switches between panels; the chosen tab is remembered per browser.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { storageKey: String }

  connect() {
    let saved
    try { saved = localStorage.getItem(this.storageKeyValue) } catch {}
    this.show(this.tabTargets.find((tab) => tab.dataset.tab === saved) ? saved : this.tabTargets[0].dataset.tab)
  }

  select(event) {
    const name = event.currentTarget.dataset.tab
    this.show(name)
    try { localStorage.setItem(this.storageKeyValue, name) } catch {}
  }

  show(name) {
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", tab.dataset.tab === name))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.tab !== name })
  }
}
