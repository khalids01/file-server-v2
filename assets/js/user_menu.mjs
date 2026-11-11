export function initUserMenus(win = window, doc = document) {
  const menus = () => doc.querySelectorAll("details[data-user-menu][open]")
  doc.addEventListener("error", event => {
    if (event.target.matches?.("img[data-user-avatar]")) event.target.remove()
  }, true)
  doc.addEventListener("click", event => {
    menus().forEach(menu => {
      if (!menu.contains(event.target) || event.target.closest("a")) menu.removeAttribute("open")
    })
  })
  doc.addEventListener("keydown", event => {
    if (event.key !== "Escape") return
    menus().forEach(menu => {
      menu.removeAttribute("open")
      menu.querySelector("summary")?.focus()
    })
  })
  win.addEventListener("phx:page-loading-start", () => menus().forEach(menu => menu.removeAttribute("open")))
}
