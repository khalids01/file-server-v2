import test from "node:test"
import assert from "node:assert/strict"
import {Sidebar} from "../../assets/js/sidebar.mjs"

function setup({desktop = true, saved = null, blocked = false} = {}) {
  const events = {}, attributes = {}, storage = new Map([["file-server-sidebar", saved]])
  const media = {matches: desktop, addEventListener: (_, fn) => {media.change = fn}, removeEventListener: () => {media.removed = true}}
  const panel = {}, toggle = {setAttribute: (key, value) => {attributes[key] = value}, focus: () => {toggle.focused = true}}
  globalThis.window = {
    matchMedia: () => media,
    localStorage: {
      getItem: key => {if (blocked) throw Error("blocked"); return storage.get(key)},
      setItem: (key, value) => {if (blocked) throw Error("blocked"); storage.set(key, value)}
    }
  }
  const hook = {el: {
    dataset: {},
    querySelector: selector => selector === "#app-sidebar" ? panel : toggle,
    addEventListener: (key, fn) => {events[key] = fn},
    removeEventListener: key => {delete events[key]}
  }}
  Sidebar.mounted.call(hook)
  const click = selector => events.click({target: {closest: query => query === selector ? {} : null}})
  return {hook, events, attributes, storage, media, panel, toggle, click}
}

test("desktop collapse persists and is restored after LiveView patches", () => {
  const a = setup()
  a.click("[data-sidebar-toggle]")
  assert.equal(a.hook.el.dataset.sidebarCollapsed, "true")
  assert.equal(a.attributes["aria-expanded"], "false")
  assert.equal(a.attributes["aria-label"], "Expand sidebar")
  assert.equal(a.storage.get("file-server-sidebar"), "collapsed")
  a.hook.el.dataset.sidebarCollapsed = "false"
  Sidebar.updated.call(a.hook)
  assert.equal(a.hook.el.dataset.sidebarCollapsed, "true")
  assert.equal(a.panel.inert, false)
  const b = setup({saved: "collapsed"})
  assert.equal(b.hook.el.dataset.sidebarCollapsed, "true")
})

test("mobile drawer closes on navigation, backdrop, Escape and viewport changes", () => {
  const a = setup({desktop: false})
  assert.equal(a.panel.inert, true)
  a.click("[data-sidebar-toggle]")
  assert.equal(a.panel.inert, false)
  assert.equal(a.attributes["aria-expanded"], "true")
  a.events.keydown({key: "Escape"})
  assert.equal(a.panel.inert, true)
  assert.equal(a.toggle.focused, true)
  for (const action of ["link", "backdrop"]) {
    a.click("[data-sidebar-toggle]")
    a.click("[data-sidebar-close], #app-sidebar a")
    assert.equal(a.hook.el.dataset.sidebarOpen, "false", action)
  }
  a.click("[data-sidebar-toggle]")
  a.media.matches = true
  a.media.change()
  assert.equal(a.hook.el.dataset.sidebarOpen, "false")
  assert.equal(a.panel.inert, false)
})

test("blocked storage permits toggling and listeners are removed when destroyed", () => {
  const a = setup({blocked: true})
  a.click("[data-sidebar-toggle]")
  assert.equal(a.hook.el.dataset.sidebarCollapsed, "true")
  Sidebar.destroyed.call(a.hook)
  assert.deepEqual(a.events, {})
  assert.equal(a.media.removed, true)
})
