// Run: node tests/hotkey.test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Hotkey.js"), "utf8").replace(/^\.pragma library/m, "")
const H = {}
vm.runInNewContext(src + "\nthis.H = { parseConfig, plan, tidy, choices, notice, TOGGLE, NEW_ISSUE, IDEAS }", H)
const K = H.H
const plain = v => JSON.parse(JSON.stringify(v))

// config: defaults, tidy keys, "" binds nothing, bad JSON falls back
assert.deepStrictEqual(plain(K.parseConfig("").config), { hotkey: "SUPER + SHIFT + K", newIssueHotkey: "SUPER + ALT + SHIFT + K" })
assert.deepStrictEqual(plain(K.parseConfig('{"hotkey":"super+alt + l","newIssueHotkey":""}').config), { hotkey: "SUPER + ALT + L", newIssueHotkey: "" })
assert.ok(K.parseConfig("{oops").error)

const binds = JSON.stringify([
  { modmask: 64, key: "K", description: "Keybindings" },
  { modmask: 65, key: "K", description: "Linear board" },          // ours, already there (e.g. from before)
  { modmask: 72, key: "L", description: "Something else" }
])
const want = (h, n) => [
  { setting: "hotkey", hotkey: h, description: K.TOGGLE, action: "A" },
  { setting: "newIssueHotkey", hotkey: n, description: K.NEW_ISSUE, action: "B" }
]
// ours is made again (it may run an old action, e.g. another plugin id), the free one is bound
let p = K.plan(binds, want("SUPER + SHIFT + K", "SUPER + ALT + SHIFT + K"))
assert.deepStrictEqual(plain(p.bound), ["SUPER + SHIFT + K", "SUPER + ALT + SHIFT + K"])
assert.deepStrictEqual(plain(p.lua), ['hl.unbind("SUPER + SHIFT + K")',
  'hl.bind("SUPER + SHIFT + K", A, { description = "Linear board" })',
  'hl.bind("SUPER + ALT + SHIFT + K", B, { description = "New Linear issue" })'])
// a taken key is never taken over
p = K.plan(binds, want("SUPER + ALT + L", ""))
assert.deepStrictEqual(plain(p.conflicts), [{ setting: "hotkey", hotkey: "SUPER + ALT + L", holder: "Something else" }])
assert.ok(p.lua.some(l => /hl\.unbind\("SUPER \+ SHIFT \+ K"\)/.test(l)), "old key of ours is released")
assert.strictEqual(K.notice(p.conflicts, {}).payload, JSON.stringify({ setup: "hotkey" }))
// choices: free first, taken ones say who holds them
const c = K.choices(binds, "", K.IDEAS.hotkey, K.TOGGLE)
assert.strictEqual(c[c.length - 1].holder, "Something else")
console.log("ok")
