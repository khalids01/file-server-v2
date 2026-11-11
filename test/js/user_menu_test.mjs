import test from "node:test"
import assert from "node:assert/strict"
import {initUserMenus} from "../../assets/js/user_menu.mjs"

function setup() {
  const events = {}, navigation = {}
  let open = true, focused = false
  const inside = {closest: () => null}, link = {closest: () => ({})}
  const menu = {
    contains: target => target === inside || target === link,
    removeAttribute: name => { if (name === "open") open = false },
    querySelector: () => ({focus: () => { focused = true }})
  }
  initUserMenus({addEventListener: (name, fn) => { navigation[name] = fn }}, {
    addEventListener: (name, fn) => { events[name] = fn },
    querySelectorAll: () => open ? [menu] : []
  })
  return {events, navigation, inside, link, isOpen: () => open, focused: () => focused}
}

test("account menu stays open inside, closes on links or outside clicks", () => {
  const a = setup()
  a.events.click({target: a.inside})
  assert.equal(a.isOpen(), true)
  a.events.click({target: a.link})
  assert.equal(a.isOpen(), false)
  const b = setup()
  b.events.click({target: {}})
  assert.equal(b.isOpen(), false)
})

test("Escape restores focus and LiveView navigation closes the menu", () => {
  const a = setup()
  a.events.keydown({key: "Escape"})
  assert.equal(a.isOpen(), false)
  assert.equal(a.focused(), true)
  const b = setup()
  b.navigation["phx:page-loading-start"]()
  assert.equal(b.isOpen(), false)
})

test("failed avatars reveal the initial without changing other images", () => {
  const a = setup()
  let removed = false
  a.events.error({target: {matches: () => true, remove: () => { removed = true }}})
  assert.equal(removed, true)
  a.events.error({target: {matches: () => false, remove: () => assert.fail("unrelated image")}})
})
