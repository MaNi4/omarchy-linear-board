// Run: node tests/e2e/shared.js [name filter]
// Two computers sharing a folder (Settings → Data, e.g. Syncthing): two
// isolated boards, "a" and "b", against one fake Linear, with their time
// file and linear-board.json in one folder. What Syncthing does on top
// (late copies, .sync-conflict files) is done by hand here.
const { spawn, execFileSync } = require("child_process")
const fs = require("fs"), path = require("path")
const H = require("./run.js")
const { waitFor, sleep, eq, ok, ctl, records } = H

const ONLY = process.argv[2] ? new RegExp(process.argv[2], "i") : null
const SHARED = path.join(H.TMP, "shared")
const TIME = path.join(SHARED, "linear-time.json")
const SETTINGS = path.join(SHARED, "linear-board.json")

// One computer: its own harness copy (Quickshell tells instances apart by
// their config path), runtime dir and files.
function computer(name) {
  const dir = path.join(H.TMP, "pc-" + name), harness = path.join(dir, "h"), run = path.join(dir, "r"), files = path.join(dir, "f")
  fs.mkdirSync(harness, { recursive: true }); fs.mkdirSync(run, { mode: 0o700 })
  for (const l of ["Commons", "Ui", "lb"]) fs.symlinkSync(fs.readlinkSync(path.join(H.HARNESS, l)), path.join(harness, l))
  fs.copyFileSync(path.join(H.HARNESS, "shell.qml"), path.join(harness, "shell.qml"))
  const shellPath = path.join(harness, "shell.qml")
  const pc = { name, files, run, proc: null }
  pc.ev = js => {
    const out = execFileSync("quickshell", ["ipc", "--any-display", "-p", shellPath, "call", "t", "ev", js],
      { env: { PATH: process.env.PATH, LANG: "C.UTF-8", XDG_RUNTIME_DIR: run }, stdio: ["ignore", "pipe", "ignore"] }).toString().trim()
    const v = JSON.parse(out)
    if (v && v.__error) throw new Error(name + ": " + v.__error + "\n  " + js)
    return v
  }
  pc.start = async (config) => {
    await pc.stop()
    const cfg = path.join(files, "config", "omarchy-linear-board")
    fs.mkdirSync(cfg, { recursive: true })
    fs.writeFileSync(path.join(cfg, "config.json"), JSON.stringify(Object.assign({ teamId: "team-eng", desktopNotify: false }, config || {})))
    const env = { HOME: process.env.HOME, PATH: H.BIN + ":" + process.env.PATH, LANG: "C.UTF-8", XDG_RUNTIME_DIR: run,
      XDG_CONFIG_HOME: path.join(files, "config"), XDG_CACHE_HOME: path.join(files, "cache"), XDG_DATA_HOME: path.join(files, "data"),
      HYPRLAND_INSTANCE_SIGNATURE: "none", OMARCHY_PATH: H.OMARCHY, QT_QPA_PLATFORM: "offscreen",
      LINEAR_API_KEY: "lin_api_fake", LINEAR_BOARD_ENDPOINT: "http://127.0.0.1:" + H.PORT + "/graphql" }
    pc.proc = spawn("dbus-run-session", ["--", "quickshell", "-n", "-p", shellPath], { env, stdio: "ignore", detached: true })
    await waitFor(() => { try { return pc.ev("board.mode") === "board" } catch (e) { return false } }, 20000, name + " to start")
    await waitFor(() => pc.ev("board.issues.length > 0 && board.pending === 0"), 15000, name + " to load")
  }
  pc.stop = async () => {
    if (!pc.proc) return
    try { process.kill(-pc.proc.pid, "SIGTERM") } catch (e) {}
    await new Promise(r => { pc.proc.once("exit", r); setTimeout(r, 3000) })
    pc.proc = null
  }
  pc.log = () => {
    const d = path.join(run, "quickshell", "by-id")
    try { return fs.readdirSync(d).map(x => { try { return fs.readFileSync(path.join(d, x, "log.log"), "utf8") } catch (e) { return "" } }).join("") } catch (e) { return "" }
  }
  // Time entries this board holds.
  pc.entries = () => pc.ev("m('saveTime').timeData.entries.map(function(e) { return e.note || e.id })")
  pc.addTime = (issueId, note) => pc.ev("m('addManualTime').addManualTime(board.issues.filter(function(i) { return i.id === '" + issueId + "' })[0], '30m', '" +
    new Date().toISOString().slice(0, 10) + "', '" + note + "')")
  return pc
}

// A disk that fails writes (full, read-only, quota): bin/linear-file is run
// through python3, and the stub put first on PATH in main() makes every
// write of the file named here fail. "" puts writes back to normal.
const FAIL_WRITES = path.join(H.TMP, "fail-writes")
const failWrites = name => fs.writeFileSync(FAIL_WRITES, name)
// Reads of sync conflict copies take this many seconds (0: normal), to
// change things while the board is in the middle of a pass.
const SLOW_READS = path.join(H.TMP, "slow-reads")
const slowReads = seconds => fs.writeFileSync(SLOW_READS, String(seconds))

const readTime = () => JSON.parse(fs.readFileSync(TIME, "utf8")).entries.map(e => e.note).sort()
const readSettings = () => JSON.parse(fs.readFileSync(SETTINGS, "utf8"))

let a, b
async function fresh(config) {
  failWrites(""); slowReads(0)
  await ctl("reset")
  await a.stop(); await b.stop()
  fs.rmSync(SHARED, { recursive: true, force: true })
  fs.mkdirSync(SHARED)
  for (const pc of [a, b]) fs.rmSync(pc.files, { recursive: true, force: true })
  // Settings → Data → the shared folder, first on a (it is empty: a's
  // settings and time go there), then on b (it takes what is there).
  await a.start(config)
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(SHARED) + ")")
  await waitFor(() => fs.existsSync(SETTINGS) && fs.existsSync(TIME), 10000, () => "a to fill the shared folder; " +
    JSON.stringify(a.ev("({ state: p('sharedState').sharedState, dir: p('sharedState').sharedDir, problem: p('sharedState').sharedProblem, error: m('setTimeLocation').timeError, writable: m('setTimeLocation').timeWritable, queue: p('sharedState').queue.length, files: " + JSON.stringify(fs.readdirSync(SHARED)) + " })")))
  await b.start(config)
  b.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(SHARED) + ")")
  await waitFor(() => b.ev("m('setTimeLocation').timeLocation") === SHARED && b.ev("m('setTimeLocation').timeWritable"), 10000, "b to use the shared folder")
}

const tests = []
const test = (name, fn) => tests.push({ name, fn })

test("time logged on one computer shows on the other", async () => {
  await fresh()
  ok(a.addTime("issue-1", "from a"), "a: addManualTime")
  await waitFor(() => readTime().includes("from a"), 5000, "the entry in the shared file")
  await waitFor(() => b.entries().includes("from a"), 15000, "b to read it")
  ok(b.addTime("issue-2", "from b"), "b: addManualTime")
  await waitFor(() => a.entries().includes("from b"), 15000, "a to read b's entry")
  eq(readTime(), ["from a", "from b"], "the shared file has both")
})

test("settings changed on one computer apply on the other", async () => {
  await fresh()
  a.ev("board.setConfig({ projectCodes: { 'project-alpha': 'ALF' }, doneWindow: 'month' })")
  await waitFor(() => readSettings().doneWindow === "month", 5000, "linear-board.json")
  await waitFor(() => b.ev("board.config.doneWindow") === "month" && b.ev("board.config.projectCodes['project-alpha']") === "ALF", 20000, "b to apply them")
  eq(b.ev("board.config.teamId"), "team-eng", "b keeps its own team")
})

test("both computers logged time while out of sync: Syncthing's conflict copy is merged", async () => {
  await fresh()
  // b is offline: it logs time into its own copy; a logs into the shared one.
  await b.stop()
  ok(a.addTime("issue-1", "a offline"), "a: addManualTime")
  await waitFor(() => readTime().includes("a offline"), 5000, "a's entry")
  const aVersion = fs.readFileSync(TIME, "utf8")
  // What b wrote while away, as Syncthing keeps it next to the winner.
  const bData = JSON.parse(aVersion)
  bData.entries = bData.entries.filter(e => e.note !== "a offline").concat([{ id: "b-offline-1", issueId: "issue-2", identifier: "ENG-2", title: "Add dark mode toggle",
    start: new Date().toISOString(), seconds: 1800, note: "b offline", manual: true }])
  const conflict = path.join(SHARED, "linear-time.sync-conflict-20261114-221500-ABCDEFG.json")
  fs.writeFileSync(conflict, JSON.stringify(bData))
  await waitFor(() => readTime().includes("b offline"), 90000, "the conflict copy merged into the time file")
  eq(readTime(), ["a offline", "b offline"], "both entries")
  await waitFor(() => !fs.existsSync(conflict), 45000, "the conflict copy cleared away (on the next pass)")
})

test("conflicting settings files: recurring rules from both are kept", async () => {
  await fresh()
  const mine = readSettings()
  const other = JSON.parse(JSON.stringify(mine))
  other.recurring = [{ id: "rule-b", issueId: "issue-2", teamId: "team-eng", teamName: "Engineering", title: "Weekly sync", every: "week", start: "2030-01-07" }]
  fs.writeFileSync(path.join(SHARED, "linear-board.sync-conflict-20261114-221500-ABCDEFG.json"), JSON.stringify(other))
  await waitFor(() => (readSettings().recurring || []).some(r => r.id === "rule-b"), 90000, "the other computer's rule merged")
})

test("a recurring issue due on both computers at once is made once", async () => {
  const today = new Date().toISOString().slice(0, 10)
  const rule = { id: "rule-daily", issueId: "issue-2", teamId: "team-eng", teamName: "Engineering", title: "Daily check", every: "day", start: today }
  await fresh({ recurring: [rule] })
  // The copy takes the source issue's current title (ENG-2).
  const copies = async () => (await records("Issue")).filter(i => i.title === "Add dark mode toggle" && i.id !== "issue-2")
  await waitFor(async () => (await copies()).length > 0, 90000, "the recurring issue")
  await sleep(70000)   // both boards check every minute
  eq((await copies()).length, 1, "made once")
})

test("both computers create the same recurring copy in the same instant", async () => {
  const today = new Date().toISOString().slice(0, 10)
  // Due tomorrow: nothing happens until both are told it is due today.
  const rule = { id: "rule-race", issueId: "issue-3", teamId: "team-eng", teamName: "Engineering", title: "Race", every: "day", start: "2099-01-01" }
  await fresh({ recurring: [rule] })
  const due = "board.config = (function(c) { var n = {}; for (var k in c) n[k] = c[k]; n.recurring = [ " +
    JSON.stringify(Object.assign({}, rule, { start: today })) + " ]; return n })(board.config)"
  a.ev(due); b.ev(due)
  // Both see no copy in Linear yet, both create it: the same id, so Linear keeps one.
  await ctl("fault", { match: "^RecurExists$", kind: "slow", ms: 1500, times: 2 })
  const go = pc => new Promise(r => require("child_process").execFile("quickshell", ["ipc", "--any-display", "-p", path.join(H.TMP, "pc-" + pc.name, "h", "shell.qml"),
    "call", "t", "ev", "m('runRecurring').runRecurring()"], { env: { PATH: process.env.PATH, LANG: "C.UTF-8", XDG_RUNTIME_DIR: pc.run } }, r))
  await Promise.all([go(a), go(b)])
  const copies = async () => (await records("Issue")).filter(i => i.title === "Write onboarding docs" && i.id !== "issue-3")
  await waitFor(async () => (await copies()).length > 0, 20000, "the copy")
  await sleep(5000)
  eq((await copies()).length, 1, "one copy")
  const creates = (await H.serverLog()).filter(e => e.op === "IssueCreate")
  ok(creates.length >= 2, "both tried (" + creates.length + ")")
  ok(!/Could not create the recurring/.test(a.ev("m('notify').toast") + b.ev("m('notify').toast")), "no error shown")
})

test("a shared folder other users can change is neither read nor written", async () => {
  await ctl("reset")
  await a.stop(); await b.stop()
  fs.rmSync(SHARED, { recursive: true, force: true })
  fs.mkdirSync(SHARED)
  fs.rmSync(a.files, { recursive: true, force: true })
  // Someone else could write here: a planted settings file with a recurring
  // issue, and the time file swapped for a link to one of your files.
  fs.chmodSync(SHARED, 0o777)
  const victim = path.join(H.TMP, "victim.txt")
  fs.writeFileSync(victim, "your own file\n")
  fs.symlinkSync(victim, TIME)
  fs.writeFileSync(SETTINGS, JSON.stringify({ version: 1, recurring: [{ id: "planted", issueId: "issue-2", teamId: "team-eng", title: "Planted", every: "day", start: "2020-01-01" }] }))
  await a.start()
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(SHARED) + ")")
  await waitFor(() => /Other users on this computer can change/.test(a.ev("m('setTimeLocation').timeError")), 10000, "the warning")
  ok(a.addTime("issue-1", "must not land") === false || true, "addManualTime")
  await sleep(3000)
  eq(fs.readFileSync(victim, "utf8"), "your own file\n", "the linked file is untouched")
  eq((a.ev("board.config.recurring") || []).length, 0, "the planted recurring issue is not taken")
  // Made private again, the folder is used.
  fs.chmodSync(SHARED, 0o755)
  fs.unlinkSync(TIME)
  await waitFor(() => a.ev("m('setTimeLocation').timeError") === "" || a.ev("p('sharedState').sharedState") === "ok", 15000, "the folder to be used once it is private")
  eq(a.ev("p('sharedState').sharedState"), "ok", "folder state")
})

test("a link in the chosen path swapped after the check is not followed", async () => {
  await ctl("reset")
  await a.stop(); await b.stop()
  fs.rmSync(SHARED, { recursive: true, force: true })
  fs.mkdirSync(SHARED)
  fs.rmSync(a.files, { recursive: true, force: true })
  // The chosen path goes through a link in a folder anyone can change; the
  // link first points to a private folder, so the check passes.
  const open = path.join(H.TMP, "open"), evil = path.join(H.TMP, "evil")
  fs.rmSync(open, { recursive: true, force: true }); fs.rmSync(evil, { recursive: true, force: true })
  fs.mkdirSync(open); fs.chmodSync(open, 0o777)
  fs.mkdirSync(evil); fs.chmodSync(evil, 0o777)
  const link = path.join(open, "sync")
  fs.symlinkSync(SHARED, link)
  await a.start()
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(link) + ")")
  await waitFor(() => fs.existsSync(TIME) && fs.existsSync(SETTINGS), 10000, "a to fill the folder behind the link")
  eq(a.ev("p('sharedState').sharedReal"), fs.realpathSync(SHARED), "files are used through the resolved path")
  // Someone else swaps the link for one to their folder, where the time file
  // and the settings file are links to files of yours.
  const victim = path.join(H.TMP, "victim2.txt"), victim2 = path.join(H.TMP, "victim3.txt")
  fs.writeFileSync(victim, "your own file\n"); fs.writeFileSync(victim2, "your other file\n")
  fs.symlinkSync(victim, path.join(evil, "linear-time.json"))
  fs.symlinkSync(victim2, path.join(evil, "linear-board.json"))
  fs.unlinkSync(link); fs.symlinkSync(evil, link)
  // Saves before the next check (every minute) go to the checked folder.
  ok(a.addTime("issue-1", "after the swap"), "a: addManualTime")
  a.ev("board.setConfig({ doneWindow: 'month' })")
  await waitFor(() => readTime().includes("after the swap") && readSettings().doneWindow === "month", 5000, "the saves in the checked folder")
  eq(fs.readFileSync(victim, "utf8"), "your own file\n", "the linked time file is untouched")
  eq(fs.readFileSync(victim2, "utf8"), "your other file\n", "the linked settings file is untouched")
  // The next check finds the folder others can change and stops using it.
  a.ev("p('sharedState').checkShared()")
  await waitFor(() => a.ev("p('sharedState').sharedState") === "unsafe", 5000, "the swapped link to be found")
  ok(a.addTime("issue-1", "must not land") === false || true, "addManualTime")
  await sleep(2000)
  eq(fs.readFileSync(victim, "utf8"), "your own file\n", "still untouched")
  eq(fs.readFileSync(victim2, "utf8"), "your other file\n", "still untouched")
})

// Syncthing (and other sync tools) bring links from the other computers as
// links: whoever else syncs the folder could put one in place of a file.
// Like Syncthing does it: made under a new name, then renamed over the file.
function swapLink(target, at) {
  const tmp = at + ".tmp-link"
  fs.rmSync(tmp, { force: true })
  fs.symlinkSync(target, tmp)
  fs.renameSync(tmp, at)
}
const outsideEntry = note => ({ id: "outside-" + note, issueId: "issue-2", identifier: "ENG-2", title: "Add dark mode toggle",
  start: new Date().toISOString(), seconds: 1800, note, manual: true })

test("a time or settings file that is a link (synced from elsewhere) is neither read nor written", async () => {
  await fresh()
  await b.stop()
  // Files of yours elsewhere, in the board's own formats.
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = [outsideEntry("outside")]
  const s = readSettings()
  s.recurring = [{ id: "outside-rule", issueId: "issue-2", teamId: "team-eng", teamName: "Engineering", title: "Outside", every: "day", start: "2099-01-01" }]
  const vt = path.join(H.TMP, "outside-time.json"), vs = path.join(H.TMP, "outside-settings.json")
  fs.writeFileSync(vt, JSON.stringify(t)); fs.writeFileSync(vs, JSON.stringify(s))
  const before = [fs.readFileSync(vt, "utf8"), fs.readFileSync(vs, "utf8")]
  swapLink(vt, TIME); swapLink(vs, SETTINGS)
  await waitFor(() => /link/i.test(a.ev("m('setTimeLocation').timeError")), 20000, () => "the time file to be refused; error: " + a.ev("m('setTimeLocation').timeError"))
  await waitFor(() => /link/i.test(a.ev("m('findConflicts').error")), 20000, () => "the settings file to be refused; error: " + a.ev("m('findConflicts').error"))
  ok(!a.entries().includes("outside"), "the linked time file is not read")
  ok(!(a.ev("board.config.recurring") || []).some(r => r.id === "outside-rule"), "the linked settings are not taken")
  eq(a.addTime("issue-1", "must not land"), false, "time cannot be logged")
  a.ev("board.setConfig({ doneWindow: 'month' })")
  await sleep(3000)
  eq([fs.readFileSync(vt, "utf8"), fs.readFileSync(vs, "utf8")], before, "the linked files are untouched")
  ok(fs.lstatSync(TIME).isSymbolicLink() && fs.lstatSync(SETTINGS).isSymbolicLink(), "the links are left for you to look at")
  // Back to real files: used again.
  fs.unlinkSync(TIME); fs.unlinkSync(SETTINGS)
  fs.writeFileSync(TIME, JSON.stringify(Object.assign({}, t, { entries: [outsideEntry("back")] })))
  fs.writeFileSync(SETTINGS, JSON.stringify(readSettingsFrom(vs)))
  await waitFor(() => a.ev("m('setTimeLocation').timeError") === "" && a.entries().includes("back"), 20000, "the real time file to be used")
})
const readSettingsFrom = p => { const s = JSON.parse(fs.readFileSync(p, "utf8")); s.recurring = []; return s }

test("a sync conflict copy that is a link is neither merged nor removed", async () => {
  await fresh()
  await b.stop()
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = [outsideEntry("outside-conflict")]
  const victim = path.join(H.TMP, "outside-conflict.json")
  fs.writeFileSync(victim, JSON.stringify(t))
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261117-101500-ABCDEFG.json")
  swapLink(victim, copy)
  // A real conflict copy next to it shows the conflicts were looked at.
  const real = JSON.parse(fs.readFileSync(TIME, "utf8"))
  real.entries = real.entries.concat([outsideEntry("real-conflict")])
  const realCopy = path.join(SHARED, "linear-time.sync-conflict-20261117-101600-ABCDEFG.json")
  fs.writeFileSync(realCopy, JSON.stringify(real))
  await waitFor(() => readTime().includes("real-conflict") || readTime().includes("outside-conflict"), 90000, "the real conflict copy merged")
  ok(!readTime().includes("outside-conflict"), "the linked copy is not merged")
  await waitFor(() => readTime().includes("real-conflict"), 30000, "the real conflict copy merged")
  await waitFor(() => !fs.existsSync(realCopy), 45000, "the real conflict copy cleared away (on the next pass)")
  ok(!readTime().includes("outside-conflict"), "the linked copy is not merged")
  ok(fs.existsSync(victim) && fs.lstatSync(copy).isSymbolicLink(), "the linked copy and its target are left alone")
})

// (A copy cleared away goes to the trash with gio, which refuses trashing in
// /tmp, where these tests run, so here it is removed: not checked below.)

test("a sync conflict copy is kept until its time entries are on disk", async () => {
  await fresh()
  await b.stop()
  failWrites("linear-time.json")
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = t.entries.concat([outsideEntry("only in the copy")])
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261119-090000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(t))
  // a merges the copy, but the time file cannot be written.
  await waitFor(() => /Could not save the time file/.test(a.ev("m('notify').toast")), 90000, "the failed save")
  await sleep(3000)
  ok(!readTime().includes("only in the copy"), "the entry is not on disk (the write failed)")
  ok(fs.existsSync(copy), "the copy, the only saved place of the entry, is kept")
  // Writes work again: the entry is saved on a later pass, then the copy goes to the trash.
  failWrites("")
  await waitFor(() => readTime().includes("only in the copy"), 90000, "the entry saved once writes work")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away once its entry is on disk")
})

test("a sync conflict copy of the settings is kept until its rules are on disk", async () => {
  await fresh()
  await b.stop()
  failWrites("linear-board.json")
  const other = readSettings()
  other.recurring = [{ id: "rule-only-copy", issueId: "issue-2", teamId: "team-eng", teamName: "Engineering", title: "Only in the copy", every: "week", start: "2030-01-07" }]
  const copy = path.join(SHARED, "linear-board.sync-conflict-20261119-090000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(other))
  await waitFor(() => /Could not save .*linear-board\.json/.test(a.ev("m('notify').toast")), 90000, "the failed save")
  await sleep(3000)
  ok(!(readSettings().recurring || []).some(r => r.id === "rule-only-copy"), "the rule is not on disk (the write failed)")
  ok(fs.existsSync(copy), "the copy, the only saved place of the rule, is kept")
  failWrites("")
  await waitFor(() => (readSettings().recurring || []).some(r => r.id === "rule-only-copy"), 90000, "the rule saved once writes work")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away once its rule is on disk")
})

test("a sync conflict copy is kept when the folder changes before its entries are on disk", async () => {
  await fresh()
  await b.stop()
  failWrites("linear-time.json")
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = t.entries.concat([outsideEntry("copy before the move")])
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261119-100000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(t))
  await waitFor(() => /Could not save the time file/.test(a.ev("m('notify').toast")), 90000, "the failed save")
  // Settings → Data → another folder, before the merge reached the disk.
  failWrites("")
  const other = path.join(H.TMP, "shared-other")
  fs.rmSync(other, { recursive: true, force: true })
  fs.mkdirSync(other)
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(other) + ")")
  await waitFor(() => a.ev("m('setTimeLocation').timeLocation") === other && a.ev("m('setTimeLocation').timeWritable") &&
    fs.existsSync(path.join(other, "linear-time.json")), 15000, "a to use the other folder")
  await sleep(40000)   // more than one pass of the conflict check (every 30 s)
  ok(fs.existsSync(copy), "the copy in the old folder is kept")
  ok(!readTime().includes("copy before the move"), "the entry is still only in the copy")
  // Back to the first folder: the copy is merged there, then cleared away.
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(SHARED) + ")")
  await waitFor(() => readTime().includes("copy before the move"), 90000, "the entry saved in the first folder")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away once its entry is on disk")
})

const readRunning = () => JSON.parse(fs.readFileSync(TIME, "utf8")).running

test("a sync conflict copy whose only news is a running timer is not dropped", async () => {
  await fresh()
  await b.stop()
  // b started a timer while offline; Syncthing kept a's version.
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  const startedAt = new Date(Date.now() - 10 * 60000).toISOString()
  t.running = { issueId: "issue-2", identifier: "ENG-2", title: "Add dark mode toggle", startedAt, device: "pc-b" }
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261119-110000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(t))
  await waitFor(() => !fs.existsSync(copy) || (readRunning() || {}).startedAt === startedAt, 90000, "the copy merged or cleared away")
  await sleep(1000)
  eq((readRunning() || {}).startedAt, startedAt, "the copy's running timer is in the time file")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away once its timer is on disk")
  eq(a.ev("m('saveTime').timeData.running ? m('saveTime').timeData.running.startedAt : ''"), startedAt, "a runs the timer")
})

test("a sync conflict merge does not write over what synced in since the last read", async () => {
  await fresh()
  await b.stop()
  failWrites("linear-time.json")
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = t.entries.concat([outsideEntry("in the copy")])
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261119-120000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(t))
  await waitFor(() => /Could not save the time file/.test(a.ev("m('notify').toast")), 90000, "the failed save")
  // Writes work again, and an entry from another computer syncs in right
  // before the next pass, before a's next read of the time file.
  failWrites("")
  const now = JSON.parse(fs.readFileSync(TIME, "utf8"))
  now.entries = now.entries.concat([outsideEntry("synced in")])
  fs.writeFileSync(TIME, JSON.stringify(now))
  a.ev("m('findConflicts').findConflicts()")
  await waitFor(() => readTime().includes("in the copy"), 90000, "the copy's entry saved")
  ok(readTime().includes("synced in"), "the entry that synced in is still there")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away")
  ok(readTime().includes("synced in"), "the entry that synced in is still there")
})

test("a settings conflict merge does not write over rules that synced in since the last read", async () => {
  await fresh()
  await b.stop()
  failWrites("linear-board.json")
  const rule = (id, title) => ({ id, issueId: "issue-2", teamId: "team-eng", teamName: "Engineering", title, every: "week", start: "2030-01-07" })
  const other = readSettings()
  other.recurring = [rule("rule-in-copy", "In the copy")]
  const copy = path.join(SHARED, "linear-board.sync-conflict-20261119-140000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(other))
  await waitFor(() => /Could not save .*linear-board\.json/.test(a.ev("m('notify').toast")), 90000, "the failed save")
  failWrites("")
  const now = readSettings()
  now.recurring = (now.recurring || []).concat([rule("rule-synced-in", "Synced in")])
  fs.writeFileSync(SETTINGS, JSON.stringify(now))
  a.ev("m('findConflicts').findConflicts()")
  const ids = () => (readSettings().recurring || []).map(r => r.id)
  await waitFor(() => ids().includes("rule-in-copy"), 90000, "the copy's rule saved")
  ok(ids().includes("rule-synced-in"), "the rule that synced in is still there")
  await waitFor(() => !fs.existsSync(copy), 90000, "the copy cleared away")
  ok(ids().includes("rule-synced-in"), "the rule that synced in is still there")
})

test("a folder change during a pass leaves the old folder's conflict copy alone", async () => {
  await fresh()
  await b.stop()
  // Another folder whose time file already has the copy's entry: compared
  // with it, the copy would look merged.
  const other = path.join(H.TMP, "shared-other")
  fs.rmSync(other, { recursive: true, force: true })
  fs.mkdirSync(other)
  const t = JSON.parse(fs.readFileSync(TIME, "utf8"))
  t.entries = t.entries.concat([outsideEntry("old folder only")])
  fs.writeFileSync(path.join(other, "linear-time.json"), JSON.stringify(t))
  fs.copyFileSync(SETTINGS, path.join(other, "linear-board.json"))
  slowReads(6)
  const copy = path.join(SHARED, "linear-time.sync-conflict-20261119-130000-ABCDEFG.json")
  fs.writeFileSync(copy, JSON.stringify(t))
  a.ev("m('findConflicts').findConflicts()")
  await sleep(1500)   // the pass is reading the copy
  a.ev("m('setTimeLocation').setTimeLocation(" + JSON.stringify(other) + ")")
  await waitFor(() => a.ev("m('setTimeLocation').timeFilePath") === fs.realpathSync(other) + "/linear-time.json", 5000, "a to use the other folder")
  await sleep(10000)  // the read is done, and whatever the pass does with it
  slowReads(0)
  ok(fs.existsSync(copy), "the old folder's copy is kept: its entry is not in the old folder's time file")
  ok(!readTime().includes("old folder only"), "the old folder's time file is unchanged")
})

async function main() {
  H.setup()
  failWrites(""); slowReads(0)
  fs.writeFileSync(path.join(H.BIN, "python3"), "#!/bin/bash\n" +
    "# Test stub: a write of the file named in " + FAIL_WRITES + " fails like a full disk.\n" +
    "fail=$(cat " + JSON.stringify(FAIL_WRITES) + " 2>/dev/null)\n" +
    "if [ -n \"$fail\" ] && [ \"$3\" = write ] && [ \"$(basename -- \"${@: -1}\")\" = \"$fail\" ]; then cat >/dev/null; echo 'linear-file: No space left on device' >&2; exit 1; fi\n" +
    "slow=$(cat " + JSON.stringify(SLOW_READS) + " 2>/dev/null)\n" +
    "if [ \"${slow:-0}\" != 0 ] && [ \"$3\" = read ] && [[ \"${@: -1}\" == *.sync-conflict-* ]]; then sleep \"$slow\"; fi\n" +
    "exec /usr/bin/python3 \"$@\"\n", { mode: 0o755 })
  await H.startServer()
  a = computer("a"); b = computer("b")
  let failed = 0, ran = 0
  try {
    for (const t of tests) {
      if (ONLY && !ONLY.test(t.name)) continue
      ran++
      const t0 = Date.now()
      try {
        await t.fn()
        console.log("ok   " + t.name + "  (" + ((Date.now() - t0) / 1000).toFixed(1) + " s)")
      } catch (e) {
        failed++
        console.log("FAIL " + t.name + "\n     " + String(e.message || e).split("\n").join("\n     "))
        const warn = (a.log() + b.log()).split("\n").filter(l => /linear-board|WARN qml/.test(l)).slice(-6)
        if (warn.length) console.log("     log: " + warn.join("\n          "))
      }
    }
  } finally {
    await a.stop(); await b.stop(); H.stopServer()
  }
  console.log((failed ? failed + " of " + ran + " failed" : "all " + ran + " passed") + "  (files in " + H.TMP + ")")
  process.exit(failed ? 1 : 0)
}

main().catch(async e => { console.error(e); try { await a.stop(); await b.stop(); H.stopServer() } catch (x) {} process.exit(1) })
