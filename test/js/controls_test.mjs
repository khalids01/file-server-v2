import test from "node:test"
import assert from "node:assert/strict"
import {Select, Dialog, applicationSlug} from "../../assets/js/controls.mjs"

test("custom select supports keyboard focus, serializes the chosen value and cleans up", () => {
  const handlers = {}, globalHandlers = {}, attrs = {}, changes = []
  const trigger = {setAttribute: (k, v) => {attrs[k] = v}, focus: () => {globalThis.document.activeElement = trigger}}
  const list = {hidden: true}, input = {value: "read", dispatchEvent: e => changes.push(e.type)}, label = {}
  globalThis.document = {activeElement: trigger, addEventListener: (k, f) => {globalHandlers[k] = f}, removeEventListener: k => {delete globalHandlers[k]}}
  const options = ["read", "write"].map(value => ({
    dataset: {selectOption: value}, textContent: value,
    selected: String(value === "read"),
    getAttribute() {return this.selected}, setAttribute(_, v) {this.selected = v},
    focus() {document.activeElement = this}, closest: q => q === "[data-select-option]" ? options.find(o => o.dataset.selectOption === value) : null
  }))
  const selectors = {"[data-select-trigger]": trigger, "[role=listbox]": list, "[data-select-value]": input, "[data-select-label]": label}
  const hook = {el: {querySelector: q => selectors[q], querySelectorAll: () => options, contains: () => false, addEventListener: (k, f) => {handlers[k] = f}, removeEventListener: k => {delete handlers[k]}}}
  Select.mounted.call(hook)
  handlers.keydown({key: "ArrowDown", preventDefault() {}})
  assert.equal(list.hidden, false)
  assert.equal(document.activeElement, options[0])
  handlers.keydown({key: "End", preventDefault() {}})
  assert.equal(document.activeElement, options[1])
  handlers.click({target: options[1]})
  assert.equal(input.value, "write")
  assert.deepEqual(changes, ["input", "change"])
  assert.equal(attrs["aria-expanded"], "false")
  assert.equal(document.activeElement, trigger)
  hook.open()
  handlers.keydown({key: "Escape", stopPropagation() {}})
  assert.equal(list.hidden, true)
  Select.destroyed.call(hook)
  assert.deepEqual(globalHandlers, {})
})

test("dialog opens modally, Escape requests server close and restores focus", () => {
  const events = {}, pushed = []
  let focused = false, opened = false
  globalThis.document = {activeElement: {focus: () => {focused = true}}}
  const hook = {el: {showModal: () => {opened = true}, addEventListener: (k, f) => {events[k] = f}, removeEventListener: k => {delete events[k]}}, pushEvent: (...args) => pushed.push(args)}
  Dialog.mounted.call(hook)
  assert.equal(opened, true)
  events.cancel({preventDefault() {}})
  assert.deepEqual(pushed, [["close_dialog", {}]])
  Dialog.destroyed.call(hook)
  assert.equal(focused, true)
  assert.deepEqual(events, {})
})

test("application slugs are URL-safe and bounded", () => {
  assert.equal(applicationSlug("  My Café Website! "), "my-cafe-website")
  assert.equal(applicationSlug("A".repeat(90)).length, 60)
})
