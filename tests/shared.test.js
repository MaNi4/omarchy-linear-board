// Run: node tests/shared.test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Shared.js"), "utf8").replace(/^\.pragma library/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(src, sandbox)
const S = sandbox.module.exports
const plain = v => JSON.parse(JSON.stringify(v))

const rule = { id: "r1", title: "Audit", teamId: "t1", every: "month" }
const config = { teamId: "t1", projectId: "p1", assignee: "me", hidden: { t1: ["s1"] }, desktopNotify: true, sort: "manual",
  group: "priority", timeComments: false, projectCodes: { p1: "WEB" }, recurring: [rule], layout: "list" }

// only the shared keys go to the folder; team, project and assignee stay here
const file = JSON.parse(S.serialize(config))
assert.strictEqual(file.version, 1)
assert.strictEqual(file.teamId, undefined)
assert.strictEqual(file.projectId, undefined)
assert.strictEqual(file.assignee, undefined)
assert.deepStrictEqual(file.recurring, [rule])
assert.strictEqual(file.layout, "list")
assert.strictEqual(file.timeComments, false)

// reading it back
assert.deepStrictEqual(plain(S.parse("").data), {})
assert.ok(S.parse("{oops").error)
assert.ok(S.parse("[1]").error)
const back = S.parse(S.serialize(config)).data
assert.deepStrictEqual(plain(back), plain(S.pick(config)))
// broken values are left out, not taken
assert.deepStrictEqual(plain(S.parse('{"layout":"grid","recurring":[{"id":"x"}],"sort":5,"doneWindow":"forever"}').data), { recurring: [] })
assert.strictEqual(S.parse('{"doneWindow":"all"}').data.doneWindow, "all")

// applying keeps the local team and project
const other = { teamId: "t9", projectId: "", assignee: "", hidden: {}, desktopNotify: true, sort: "manual", group: "none",
  timeComments: true, projectCodes: {}, recurring: [], layout: "board" }
const applied = S.apply(other, back)
assert.strictEqual(applied.teamId, "t9")
assert.strictEqual(applied.layout, "list")
assert.deepStrictEqual(plain(applied.recurring), [rule])
assert.ok(S.differs(other, applied))
assert.ok(!S.differs(applied, S.apply(applied, back)))
assert.ok(!S.differs(config, Object.assign({}, config, { teamId: "x" })))

// export holds settings and time, never the key or the current team
const time = { version: 1, running: null, entries: [{ id: "e1", issueId: "i1", start: "2026-10-27T10:00:00.000Z", seconds: 60 }] }
const exp = S.exportText(config, time, new Date("2026-10-27T12:00:00Z"))
const px = S.parseExport(exp)
assert.deepStrictEqual(plain(px.settings), plain(S.pick(config)))
assert.strictEqual(px.time.entries.length, 1)
assert.strictEqual(JSON.parse(exp).settings.teamId, undefined)
// an older time-only export
const old = S.parseExport(JSON.stringify(time))
assert.deepStrictEqual(plain(old.settings), {})
assert.strictEqual(old.time.entries.length, 1)
assert.ok(S.parseExport("{}").error)
assert.ok(S.parseExport("nope").error)

// import adds what is missing, replaces nothing
const here = Object.assign({}, other, { recurring: [{ id: "r1", title: "Mine", teamId: "t1" }], projectCodes: { p1: "OWN" }, hidden: { t1: [] } })
const m = S.mergeSettings(here, { recurring: [rule, { id: "r2", title: "New", teamId: "t1" }], projectCodes: { p1: "WEB", p2: "API" }, hidden: { t1: ["s1"], t2: ["s2"] }, layout: "list" })
assert.strictEqual(m.rules, 1)
assert.strictEqual(m.codes, 1)
assert.deepStrictEqual(plain(m.config.recurring.map(r => r.title)), ["Mine", "New"])
assert.deepStrictEqual(plain(m.config.projectCodes), { p1: "OWN", p2: "API" })
assert.deepStrictEqual(plain(m.config.hidden), { t1: [], t2: ["s2"] })
assert.strictEqual(m.config.layout, "board")
const none = S.mergeSettings(here, {})
assert.strictEqual(none.rules + none.codes, 0)
assert.ok(!S.differs(here, none.config))

console.log("shared tests passed")
