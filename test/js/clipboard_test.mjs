import test from "node:test"
import assert from "node:assert/strict"
import {Clipboard} from "../../assets/js/clipboard.mjs"

function setup(path, writeText) {
  const handlers = {}, status = {textContent: "Copy private link"}
  Object.defineProperty(globalThis, "navigator", {value: {clipboard: {writeText}}, configurable: true})
  globalThis.window = {location: {origin: "https://files.example.test"}}
  const hook = {el: {dataset: {downloadPath: path}, querySelector: () => status, addEventListener: (k,f) => {handlers[k] = f}, removeEventListener: k => {delete handlers[k]}}}
  Clipboard.mounted.call(hook)
  return {handlers, status, hook}
}
const path = "/files/11111111-1111-4111-8111-111111111111/download"
test("copies an absolute private URL with sign-in feedback and removes its listener", async () => {
  const copied = [], {handlers,status,hook} = setup(path, async value => copied.push(value))
  await handlers.click()
  assert.deepEqual(copied, ["https://files.example.test" + path])
  assert.equal(status.textContent, "Copied · sign-in required")
  Clipboard.destroyed.call(hook)
  assert.deepEqual(handlers, {})
})
test("clipboard denial gives an honest download fallback", async () => {
  const {handlers,status} = setup(path, async () => {throw new Error("denied")})
  await handlers.click()
  assert.match(status.textContent, /Could not copy/)
})
test("external and malformed URLs never reach the clipboard", async () => {
  for (const invalid of ["https://evil.example/file", "//evil.example/path", "/files/secret/../../download", "javascript:alert(1)"]) {
    const {handlers,status} = setup(invalid, async () => assert.fail("unsafe URL copied"))
    await handlers.click()
    assert.match(status.textContent, /Could not copy/)
  }
})
