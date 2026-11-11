const preferences = new Set(["light", "dark", "system"])
export function initTheme(win = window, doc = document) {
  const root = doc.documentElement
  const media = win.matchMedia("(prefers-color-scheme: dark)")
  const read = () => { try { return win.localStorage.getItem("file-server-theme") } catch { return null } }
  let preference = read() || root.dataset.theme || "system"
  const apply = (next, persist = false) => {
    preference = preferences.has(next) ? next : "system"
    const dark = preference === "dark" || (preference === "system" && media.matches)
    root.dataset.theme = preference
    root.classList.toggle("dark", dark)
    doc.querySelectorAll("[data-theme-choice]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.themeChoice === preference)))
    if (persist) {
      try { win.localStorage.setItem("file-server-theme", preference) } catch {}
      try { doc.cookie = `file-server-theme=${preference}; Path=/; Max-Age=31536000; SameSite=Lax${win.location.protocol === "https:" ? "; Secure" : ""}` } catch {}
    }
  }
  apply(preference)
  doc.addEventListener("click", event => {
    const option = event.target.closest("[data-theme-choice]")
    if (option) {
      apply(option.dataset.themeChoice, true)
      option.closest("details")?.removeAttribute("open")
    }
    doc.querySelectorAll("details.theme-menu[open]").forEach(menu => { if (!menu.contains(event.target)) menu.removeAttribute("open") })
  })
  doc.addEventListener("toggle", event => { if (event.target.matches?.("details.theme-menu")) apply(preference) }, true)
  doc.addEventListener("keydown", event => {
    if (event.key === "Escape") doc.querySelectorAll("details.theme-menu[open]").forEach(menu => {
      menu.removeAttribute("open"); menu.querySelector("summary")?.focus()
    })
  })
  media.addEventListener("change", () => { if (preference === "system") apply("system") })
  win.addEventListener("storage", event => { if (event.key === "file-server-theme") apply(event.newValue || "system") })
  win.addEventListener("phx:page-loading-stop", () => apply(preference))
}
