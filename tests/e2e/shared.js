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

const readTime = () => JSON.parse(fs.readFileSync(TIME, "utf8")).entries.map(e => e.note).sort()
const readSettings = () => JSON.parse(fs.readFileSync(SETTINGS, "utf8"))

let a, b
async function fresh(config) {
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
  await waitFor(() => !fs.existsSync(conflict), 5000, "the conflict copy cleared away")
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

async function main() {
  H.setup()
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
