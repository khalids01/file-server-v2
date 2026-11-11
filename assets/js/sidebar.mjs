export const Sidebar = {
  mounted() {
    this.media = window.matchMedia("(min-width: 1024px)")
    try { this.collapsed = window.localStorage.getItem("file-server-sidebar") === "collapsed" } catch { this.collapsed = false }
    this.mobileOpen = false
    this.apply = () => {
      this.el.dataset.sidebarCollapsed = String(this.collapsed)
      this.el.dataset.sidebarOpen = String(this.mobileOpen)
      const visible = this.media.matches || this.mobileOpen
      const sidebar = this.el.querySelector("#workspace-sidebar")
      if (sidebar) sidebar.inert = !visible
      const toggle = this.el.querySelector("[data-sidebar-toggle]")
      toggle?.setAttribute("aria-expanded", String(this.media.matches ? !this.collapsed : this.mobileOpen))
      toggle?.setAttribute("aria-label", this.media.matches ? (this.collapsed ? "Expand sidebar" : "Collapse sidebar") : (this.mobileOpen ? "Close sidebar" : "Open sidebar"))
    }
    this.onClick = event => {
      if (event.target.closest("[data-sidebar-toggle]")) {
        if (this.media.matches) {
          this.collapsed = !this.collapsed
          try { window.localStorage.setItem("file-server-sidebar", this.collapsed ? "collapsed" : "expanded") } catch {}
        } else this.mobileOpen = !this.mobileOpen
        this.apply()
      } else if (event.target.closest("[data-sidebar-close], #workspace-sidebar a")) {
        this.mobileOpen = false
        this.apply()
      }
    }
    this.onKey = event => {
      if (event.key === "Escape" && this.mobileOpen) {
        this.mobileOpen = false
        this.apply()
        this.el.querySelector("[data-sidebar-toggle]")?.focus()
      }
    }
    this.onChange = () => { this.mobileOpen = false; this.apply() }
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("keydown", this.onKey)
    this.media.addEventListener("change", this.onChange)
    this.apply()
  },
  updated() { this.apply() },
  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("keydown", this.onKey)
    this.media.removeEventListener("change", this.onChange)
  }
}
