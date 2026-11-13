export const applicationSlug = name => name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60).replace(/-$/, "")
export const Dialog = {
  mounted() {
    this.opener = document.activeElement
    this.el.showModal()
    this.onCancel = event => { event.preventDefault(); this.pushEvent("close_dialog", {}) }
    this.onClick = event => { if (event.target === this.el) { const r = this.el.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) this.pushEvent("close_dialog", {}) } }
    this.el.addEventListener("cancel", this.onCancel)
    this.el.addEventListener("click", this.onClick)
    this.onInput = event => {
      if (event.target.name !== "application[name]") return
      const slug = this.el.querySelector('[name="application[slug]"]')
      if (!slug) return
      if (!slug.value || slug.value === this.lastSlug) {
        this.lastSlug = applicationSlug(event.target.value)
        slug.value = this.lastSlug
        slug.dispatchEvent(new Event("input", {bubbles: true}))
      }
    }
    this.el.addEventListener("input", this.onInput)
  },
  destroyed() { this.el.removeEventListener("input", this.onInput); this.el.removeEventListener("cancel", this.onCancel); this.el.removeEventListener("click", this.onClick); this.opener?.focus() }
}
export const Select = {
  mounted() {
    this.trigger = () => this.el.querySelector("[data-select-trigger]")
    this.list = () => this.el.querySelector("[role=listbox]")
    this.options = () => [...this.el.querySelectorAll("[data-select-option]")]
    this.close = (focus = false) => { this.list().hidden = true; this.trigger().setAttribute("aria-expanded", "false"); if (focus) this.trigger().focus() }
    this.open = () => { this.list().hidden = false; this.trigger().setAttribute("aria-expanded", "true"); (this.options().find(o => o.getAttribute("aria-selected") === "true") || this.options()[0])?.focus() }
    this.onClick = event => {
      if (event.target.closest("[data-select-trigger]")) { if (this.list().hidden) this.open(); else this.close(true) }
      const option = event.target.closest("[data-select-option]")
      if (option) {
        const input = this.el.querySelector("[data-select-value]")
        input.value = option.dataset.selectOption
        this.el.querySelector("[data-select-label]").textContent = option.textContent.trim()
        this.options().forEach(o => o.setAttribute("aria-selected", String(o === option)))
        input.dispatchEvent(new Event("input", {bubbles: true}))
        input.dispatchEvent(new Event("change", {bubbles: true}))
        this.close(true)
      }
    }
    this.onKey = event => {
      if (event.key === "Escape") { this.close(true); event.stopPropagation(); return }
      if (event.key === "Tab") { this.close(); return }
      if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
        event.preventDefault()
        if (this.list().hidden) { this.open(); return }
        const options = this.options(), current = options.indexOf(document.activeElement)
        const next = event.key === "Home" ? 0 : event.key === "End" ? options.length - 1 : (current + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length
        options[next]?.focus()
      }
    }
    this.outside = event => { if (!this.el.contains(event.target)) this.close() }
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.outside)
  },
  updated() { this.close() },
  destroyed() { this.el.removeEventListener("click", this.onClick); this.el.removeEventListener("keydown", this.onKey); document.removeEventListener("click", this.outside) }
}
