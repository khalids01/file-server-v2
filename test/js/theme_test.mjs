import test from "node:test"
import assert from "node:assert/strict"
import {initTheme} from "../../assets/js/theme.mjs"
function browser({stored = null, cookie = "system", osDark = false, unavailable = false} = {}) {
  const events = {}, listeners = {}, storage = new Map(stored ? [["file-server-theme", stored]] : [])
  const media = {matches: osDark, addEventListener: (_name, fn) => { media.change = fn }}
  const root = {dataset: {theme: cookie}, classList: {toggle: (_name, value) => { root.dark = value }}}
  const menu = {removeAttribute: name => { menu.removed = name }, contains: () => true}
  const option = mode => ({dataset: {themeChoice: mode}, setAttribute: (name, value) => { options[mode][name] = value }, closest: selector => selector === "details" ? menu : options[mode]})
  const options = Object.fromEntries(["light", "dark", "system"].map(mode => [mode, option(mode)]))
  const doc = {documentElement: root, cookie: "", querySelectorAll: selector => selector === "[data-theme-choice]" ? Object.values(options) : [], addEventListener: (name, fn) => { events[name] = fn }}
  const win = {location: {protocol: "https:"}, matchMedia: () => media, localStorage: {getItem: key => {if (unavailable) throw Error("blocked"); return storage.get(key)}, setItem: (key, value) => {if (unavailable) throw Error("blocked"); storage.set(key, value)}}, addEventListener: (name, fn) => {listeners[name] = fn}}
  initTheme(win, doc)
  return {root, doc, options, storage, media, listeners, click: mode => events.click({target: options[mode]}), menu}
}
test("dark selection persists, reflects pressed state and closes the menu", () => {
  const env = browser()
  env.click("dark")
  assert.equal(env.root.dark, true)
  assert.equal(env.storage.get("file-server-theme"), "dark")
  assert.match(env.doc.cookie, /file-server-theme=dark;.*Secure/)
  assert.equal(env.options.dark["aria-pressed"], "true")
  assert.equal(env.options.light["aria-pressed"], "false")
  assert.equal(env.menu.removed, "open")
})
test("system follows OS changes while an explicit light selection does not", () => {
  const env = browser({osDark: true})
  assert.equal(env.root.dark, true)
  env.media.matches = false; env.media.change()
  assert.equal(env.root.dark, false)
  env.click("light"); env.media.matches = true; env.media.change()
  assert.equal(env.root.dark, false)
})
test("storage events and LiveView navigation keep controls synchronized", () => {
  const env = browser({stored: "light"})
  env.listeners.storage({key: "file-server-theme", newValue: "dark"})
  env.options.dark["aria-pressed"] = "false"
  env.listeners["phx:page-loading-stop"]()
  assert.equal(env.root.dark, true)
  assert.equal(env.options.dark["aria-pressed"], "true")
})
test("blocked storage falls back to server cookie and still allows theme changes", () => {
  const env = browser({cookie: "dark", unavailable: true})
  assert.equal(env.root.dark, true)
  env.click("light")
  assert.equal(env.root.dark, false)
  assert.match(env.doc.cookie, /file-server-theme=light/)
})
