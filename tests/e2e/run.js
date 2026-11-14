// Run: node tests/e2e/run.js [name filter]
// The board end to end, without a Linear account and without touching the
// desktop: tests/fake-linear.js stands in for Linear, and the board (with the
// bar widget) runs in its own offscreen Quickshell with its files in a
// temporary directory. Commands the board would run on the desktop
// (hyprctl, wl-copy, xdg-open, omarchy-shell, desktop notifications) are
// stubs that only log. Needs Omarchy (quickshell, $OMARCHY_PATH/shell) and
// the graphql package; not part of `npm test`, which runs anywhere.
const { spawn, execFileSync } = require("child_process")
const fs = require("fs"), path = require("path"), os = require("os"), http = require("http")

const ROOT = path.join(__dirname, "..", "..")
const OMARCHY = process.env.OMARCHY_PATH || "/usr/share/omarchy"
const PORT = 47199
const ONLY = process.argv[2] ? new RegExp(process.argv[2], "i") : null
// Short: Quickshell's IPC socket lives under XDG_RUNTIME_DIR (108 bytes max).
const TMP = fs.mkdtempSync(path.join("/tmp", "lbe2e-"))
const HARNESS = path.join(TMP, "h"), RUN = path.join(TMP, "r"), BIN = path.join(TMP, "bin")
const FILES = path.join(TMP, "f")
const SHELL = path.join(HARNESS, "shell.qml")

// ---- setup ------------------------------------------------------------------------------

function setup() {
  fs.mkdirSync(HARNESS); fs.mkdirSync(RUN, { mode: 0o700 }); fs.mkdirSync(BIN)
  fs.symlinkSync(path.join(OMARCHY, "shell", "Commons"), path.join(HARNESS, "Commons"))
  fs.symlinkSync(path.join(OMARCHY, "shell", "Ui"), path.join(HARNESS, "Ui"))
  fs.symlinkSync(ROOT, path.join(HARNESS, "lb"))
  fs.copyFileSync(path.join(__dirname, "shell.qml"), SHELL)
  const stub = (name, body) => fs.writeFileSync(path.join(BIN, name), "#!/bin/bash\n" + body + "\n", { mode: 0o755 })
  const log = name => 'printf "%s\\n" "' + name + ' $*" >> "' + path.join(TMP, "calls.log") + '"'
  stub("hyprctl", log("hyprctl") + '\n[ "$1" = binds ] && echo "[]"; exit 0')
  stub("wl-copy", log("wl-copy") + "\ncat > /dev/null")
  stub("wl-paste", "exit 1")
  stub("xdg-open", log("xdg-open"))
  stub("omarchy-shell", log("omarchy-shell"))
  stub("notify-send", log("notify-send"))
  // Desktop notifications: bin/linear-notify reads one JSON object on stdin.
  const py = execFileSync("sh", ["-c", "command -v python3"]).toString().trim()
  stub("python3", 'case "$1" in */linear-notify) cat >> "' + path.join(TMP, "notes.log") + '"; echo >> "' + path.join(TMP, "notes.log") +
    '"; echo 1; exit 0;; esac\nexec ' + py + ' "$@"')
}

// ---- the fake server ------------------------------------------------------------------------

let server
function startServer() {
  server = spawn(process.execPath, [path.join(ROOT, "tests", "fake-linear.js"), "--port", String(PORT)], { stdio: ["ignore", "pipe", "pipe"] })
  server.stderrText = ""
  server.stderr.on("data", d => { server.stderrText += d })
  return waitFor(() => request("GET", "/_log").then(() => true, () => false), 30000, "fake server")
}

function request(method, p, body) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body)
    const req = http.request({ host: "127.0.0.1", port: PORT, path: p, method, agent: false, headers: { "Content-Type": "application/json" } }, res => {
      let d = ""
      res.on("data", c => d += c)
      res.on("end", () => { try { resolve(JSON.parse(d)) } catch (e) { resolve(d) } })
    })
    req.on("error", reject)
    if (data) req.write(data)
    req.end()
  })
}
const ctl = (what, body) => request("POST", "/_control/" + what, body || {})
const serverLog = () => request("GET", "/_log")
const records = type => request("GET", "/_db/" + type)
const record = async (type, id) => (await records(type)).find(r => r.id === id)

// ---- the board ----------------------------------------------------------------------------------

let shell = null
function env(extra) {
  return Object.assign({
    HOME: process.env.HOME, PATH: BIN + ":" + process.env.PATH, LANG: "C.UTF-8",
    XDG_RUNTIME_DIR: RUN, XDG_CONFIG_HOME: path.join(FILES, "config"), XDG_CACHE_HOME: path.join(FILES, "cache"),
    XDG_DATA_HOME: path.join(FILES, "data"), HYPRLAND_INSTANCE_SIGNATURE: "none", OMARCHY_PATH: OMARCHY,
    QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1", LINEAR_API_KEY: "lin_api_fake", LINEAR_BOARD_ENDPOINT: "http://127.0.0.1:" + PORT + "/graphql"
  }, extra || {})
}

async function startBoard(opts) {
  opts = opts || {}
  await stopBoard()
  if (!opts.keepFiles) fs.rmSync(FILES, { recursive: true, force: true })
  fs.rmSync(path.join(RUN, "omarchy-linear-board"), { recursive: true, force: true })
  fs.rmSync(path.join(RUN, "quickshell"), { recursive: true, force: true })
  if (opts.config) {
    fs.mkdirSync(path.join(FILES, "config", "omarchy-linear-board"), { recursive: true })
    fs.writeFileSync(path.join(FILES, "config", "omarchy-linear-board", "config.json"), opts.config)
  }
  const e = env(opts.env)
  if (opts.noEnvKey) delete e.LINEAR_API_KEY
  shell = spawn("dbus-run-session", ["--", "quickshell", "-n", "-p", SHELL], { env: e, stdio: ["ignore", "pipe", "pipe"], detached: true })
  shell.out = ""
  shell.stdout.on("data", d => { shell.out += d })
  shell.stderr.on("data", d => { shell.out += d })
  await waitFor(() => { try { return ev("1") === 1 } catch (e) { return false } }, 15000, "the board's shell")
  if (opts.wait !== false) await waitFor(() => ev("board.mode") !== "loading", 10000, "the board to start")
}

async function stopBoard() {
  if (!shell) return
  try { process.kill(-shell.pid, "SIGTERM") } catch (e) {}
  await new Promise(r => { shell.once("exit", r); setTimeout(r, 3000) })
  shell = null
}

function ev(js) {
  const out = execFileSync("quickshell", ["ipc", "--any-display", "-p", SHELL, "call", "t", "ev", js],
    { env: { PATH: process.env.PATH, LANG: "C.UTF-8", XDG_RUNTIME_DIR: RUN }, stdio: ["ignore", "pipe", "ignore"] }).toString().trim()
  const v = JSON.parse(out)
  if (v && v.__error) throw new Error("in the board: " + v.__error + "\n  " + js)
  return v
}
// ev() of a statement list; the last expression is the result.
const evs = (...lines) => ev("(function() { " + lines.slice(0, -1).join("; ") + "; return " + lines[lines.length - 1] + " })()")

// A picture of the board's window (it is grabbed asynchronously).
async function shot(name) {
  const file = path.join(TMP, name + ".png")
  execFileSync("quickshell", ["ipc", "--any-display", "-p", SHELL, "call", "t", "shot", file],
    { env: { PATH: process.env.PATH, LANG: "C.UTF-8", XDG_RUNTIME_DIR: RUN }, stdio: "ignore" })
  await waitFor(() => fs.existsSync(file) && fs.statSync(file).size > 0, 3000, "the screenshot").catch(() => {})
  await sleep(300)
  return fs.existsSync(file) ? file : "(none, the window is closed)"
}

// What the board logged (Quickshell's plain log of this instance).
function shellLog() {
  const dir = path.join(RUN, "quickshell", "by-id")
  try { return fs.readdirSync(dir).map(d => { try { return fs.readFileSync(path.join(dir, d, "log.log"), "utf8") } catch (e) { return "" } }).join("") } catch (e) { return "" }
}
const inboxState = () => { try { return JSON.parse(fs.readFileSync(path.join(RUN, "omarchy-linear-board", "inbox.json"), "utf8")) } catch (e) { return null } }
const notes = () => { try { return fs.readFileSync(path.join(TMP, "notes.log"), "utf8").split("\n").filter(Boolean).map(JSON.parse) } catch (e) { return [] } }
const sleep = ms => new Promise(r => setTimeout(r, ms))

async function waitFor(fn, ms, what) {
  const end = Date.now() + (ms || 10000)
  let last
  while (Date.now() < end) {
    try { last = await fn(); if (last) return last } catch (e) { last = e }
    await sleep(150)
  }
  if (typeof what === "function") what = what()
  throw new Error("timed out waiting for " + (what || fn.toString()) + (last instanceof Error ? " (" + last.message + ")" : ""))
}

function eq(actual, expected, what) {
  if (JSON.stringify(actual) !== JSON.stringify(expected))
    throw new Error((what || "value") + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual))
}
function ok(cond, what) { if (!cond) throw new Error(what) }

// Fresh data and a fresh board with its first loads done.
async function fresh(opts) {
  await ctl("reset")
  try { fs.unlinkSync(path.join(TMP, "notes.log")) } catch (e) {}
  await startBoard(opts)
  if (!opts || opts.wait !== false) {
    await waitFor(() => ev("board.issues.length > 0 && board.pending === 0"), 10000, "the issues")
    await waitFor(() => { const s = inboxState(); return s && s.checkedAt }, 10000, "the first inbox check")
  }
}

const stateOf = id => ev("(board.issues.filter(function(i) { return i.id === " + JSON.stringify(id) + " })[0] || {}).stateId || null")
const issue = id => ev("board.issues.filter(function(i) { return i.id === " + JSON.stringify(id) + " })[0] || null")
const outbox = () => ev("m('flushOutbox').outbox.length")
const toast = () => ev("m('notify').toast")

// ---- scenarios ------------------------------------------------------------------------------------

const tests = []
const test = (name, fn) => tests.push({ name, fn })

test("loads the team, the issues and the inbox", async () => {
  await fresh()
  eq(ev("board.mode"), "board", "mode")
  eq(ev("board.team.key"), "ENG", "team")
  eq(ev("board.columns.map(function(c) { return c.name })"), ["Backlog", "Todo", "In Progress", "Done"], "columns (Canceled hidden)")
  // Done within 2 weeks shows, canceled does not count as open either.
  eq(ev("board.issues.length"), 10, "issues (closed ones of the last 2 weeks too)")
  const s = inboxState()
  eq(s.connected, true, "inbox.json connected")
  eq(s.unread, 5, "inbox.json unread (Linear's count)")
  eq(s.error, "", "inbox.json error")
  eq(s.items.length, 4, "unread rows in inbox.json")
  await waitFor(() => ev("bar.unread") === 5, 12000, "the bar widget's count")
  eq(ev("bar.health.stale"), false, "bar stale")
  ok(!/TypeError|ReferenceError|Cannot read/.test(shellLog()), "QML errors in the log:\n" + shellLog())
})

test("moving an issue goes to Linear", async () => {
  await fresh()
  ev("m('moveIssue').moveIssue('issue-3', 'state-started', 0)")
  await waitFor(async () => (await record("Issue", "issue-3")).stateId === "state-started", 5000, "the move on the server")
  eq(stateOf("issue-3"), "state-started", "board state")
})

test("Linear refusing a change rolls it back", async () => {
  await fresh()
  await ctl("fault", { match: "^IssueUpdate$", kind: "status", status: 400,
    body: { errors: [{ message: "Entity not found", extensions: { code: "INVALID_INPUT", userPresentableMessage: "This issue was deleted." } }] } })
  const before = stateOf("issue-3")
  ev("m('moveIssue').moveIssue('issue-3', 'state-started', 0)")
  await waitFor(() => /deleted/.test(toast()), 5000, "the error toast")
  await waitFor(() => stateOf("issue-3") === before, 5000, "the rollback")
  eq(outbox(), 0, "outbox")
})

test("offline: changes wait in the outbox, are merged and sent later", async () => {
  await fresh()
  await ctl("fault", { match: "^IssueUpdate$", kind: "drop", times: 0 })
  ev("m('moveIssue').moveIssue('issue-3', 'state-started', 0)")
  await waitFor(() => outbox() === 1, 5000, "the outbox")
  ok(/Offline/.test(toast()), "offline toast, got " + toast())
  eq(stateOf("issue-3"), "state-started", "the board keeps the change")
  ev("m('moveIssue').moveIssue('issue-3', 'state-unstarted', 0)")
  await waitFor(() => outbox() === 1 && ev("m('flushOutbox').outbox[0].variables.input.stateId") === "state-unstarted", 5000, "the joined outbox entry")
  const saved = JSON.parse(fs.readFileSync(path.join(FILES, "cache", "omarchy-linear-board", "outbox.json"), "utf8"))
  eq(saved.length, 1, "outbox.json entries")
  await ctl("clear-faults")
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(() => outbox() === 0, 5000, "the outbox to empty")
  eq((await record("Issue", "issue-3")).stateId, "state-unstarted", "server state after the flush")
  ok(/Back online/.test(toast()), "back online toast, got " + toast())
})

test("the outbox survives a restart", async () => {
  await fresh()
  await ctl("fault", { match: "^IssueUpdate$", kind: "drop", times: 0 })
  ev("m('moveIssue').moveIssue('issue-10', 'state-started', 0)")
  await waitFor(() => outbox() === 1, 5000, "the outbox")
  await ctl("clear-faults")
  await startBoard({ keepFiles: true })
  await waitFor(async () => (await record("Issue", "issue-10")).stateId === "state-started", 10000, "the change sent after the restart")
  await waitFor(() => outbox() === 0, 5000, "the outbox to empty")
})

test("rate limit (400 RATELIMITED): nothing is sent until it resets, changes wait", async () => {
  await fresh()
  await ctl("fault", { match: "^Inbox$", kind: "ratelimit", resetMs: 4000 })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => ev("board.rateLimitedUntil") > Date.now(), 5000, "the rate limit to be noted")
  const sent = (await serverLog()).length
  ev("m('moveIssue').moveIssue('issue-3', 'state-started', 0)")
  await waitFor(() => outbox() === 1, 5000, "the change to wait")
  ok(/rate limit/i.test(toast()), "rate limit toast, got " + toast())
  eq((await serverLog()).length, sent, "requests sent while rate limited")
  eq(inboxState().error !== "", true, "the inbox error is in inbox.json")
  await sleep(4500)
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(async () => (await record("Issue", "issue-3")).stateId === "state-started", 5000, "the change after the reset")
})

test("rate limit (HTTP 429 with Retry-After)", async () => {
  await fresh()
  await ctl("fault", { match: "^Inbox$", kind: "status", status: 429, headers: { "Retry-After": "2" }, body: { errors: [{ message: "Too many requests" }] } })
  const t = Date.now()
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => ev("board.rateLimitedUntil") > t, 5000, "the rate limit to be noted")
  const until = ev("board.rateLimitedUntil")
  ok(until - t > 1000 && until - t < 4000, "Retry-After used, waits " + (until - t) + " ms")
})

test("Linear stops answering the internal inbox fields: the public ones are used", async () => {
  await ctl("reset")
  await ctl("internal", { on: false })
  try { fs.unlinkSync(path.join(TMP, "notes.log")) } catch (e) {}
  await startBoard()
  await waitFor(() => { const s = inboxState(); return s && s.checkedAt }, 10000, "the inbox check")
  eq(ev("m('loadInbox').publicOnly"), true, "publicOnly")
  const s = inboxState()
  eq(s.error, "", "error")
  eq(s.unread, 4, "unread counted from the rows (Linear's own count is gone)")
  // Made up from the type and the actor's display name.
  eq(s.items.map(i => i.subtitle).sort(), ["Marked urgent by alex", "Mentioned you by alex", "New project update by alex", "Status changed by Sentry"], "made-up subtitles")
})

test("an inbox check that never comes back is given up", async () => {
  await fresh()
  await ctl("fault", { match: "^Inbox$", kind: "hang" })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => ev("m('loadInbox').loading"), 3000, "loading")
  await waitFor(() => !ev("m('loadInbox').loading"), 40000, "the 30 s request watchdog")
  ok(/did not answer/.test(inboxState().error), "error in inbox.json: " + inboxState().error)
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => inboxState().error === "", 5000, "the next check to work")
})

test("an answer that is not JSON", async () => {
  await fresh()
  await ctl("fault", { match: "^Inbox$", kind: "garbage" })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => inboxState().error !== "", 5000, "the error")
  eq(ev("m('loadInbox').loading"), false, "loading")
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => inboxState().error === "", 5000, "recovery")
})

test("an answer of an unexpected shape does not break the board", async () => {
  await fresh()
  await ctl("set", { id: "issue-1", fields: { title: null, labelIds: ["label-gone"], stateId: "state-gone" } })
  ev("m('refresh').refresh()")
  await waitFor(() => ev("board.pending") === 0, 5000, "the refresh")
  ok(ev("board.issues.length") >= 8, "issues still shown")
  ev("board.open('{}')")
  await shot("odd-shape")
})

test("a wrong key shows the setup screen; the bar says not connected", async () => {
  await ctl("reset")
  await startBoard({ env: { LINEAR_API_KEY: "lin_api_wrong" } })
  await waitFor(() => ev("board.mode") === "setup", 10000, "the setup screen")
  ok(/rejected/i.test(ev("board.setupError")), "setup error: " + ev("board.setupError"))
  await waitFor(() => inboxState() && inboxState().connected === false, 5000, "inbox.json connected false")
  await waitFor(() => ev("bar.connected") === false, 12000, "the bar")
})

test("a key revoked while running", async () => {
  await fresh()
  await ctl("fault", { match: "^Inbox$", kind: "status", status: 401,
    body: { errors: [{ message: "Authentication required, not authenticated", extensions: { code: "AUTHENTICATION_ERROR", http: { status: 401 } } }] } })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => ev("board.mode") === "setup", 5000, "the setup screen")
  await waitFor(() => inboxState().connected === false, 5000, "inbox.json")
})

test("a new notification: desktop note, count, mark read", async () => {
  await fresh()
  eq(notes().length, 0, "no notes for what was there at the start")
  const n = await ctl("notify", { issueId: "issue-9", type: "issueAssignedToYou", subtitle: "Assigned to you by Alex Other", title: "Profile slow search", groupingKey: "issue#issue-9" })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => inboxState().unread === 6, 5000, "the new count")
  await waitFor(() => notes().length === 1, 5000, "the desktop note")
  const note = notes()[0]
  eq(note.title, "Profile slow search", "note title")
  ok(/ENG-9/.test(note.body), "note body " + note.body)
  eq(note.exec.slice(0, 4), ["omarchy-shell", "shell", "summon", "mani4.linear-board"], "click action")
  ev("m('loadInbox').loadInbox()")
  await sleep(1500)
  eq(notes().length, 1, "announced once")
  // Mark the row read: both notifications of ENG-9 (one was read already).
  evs("var c = m('loadInbox')", "var row = c.items.filter(function(x) { return x.identifier === 'ENG-9' })[0]", "c.setRead(row, true)", "row.ids.length")
  await waitFor(async () => (await record("IssueNotification", n.id)).readAt, 5000, "readAt on the server")
  await waitFor(() => inboxState().unread === 5, 5000, "the count after reading")
})

test("more than 3 new notifications: one summary note", async () => {
  await fresh()
  for (const id of ["issue-2", "issue-3", "issue-6", "issue-10"]) await ctl("notify", { issueId: id, groupingKey: "issue#" + id })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => notes().length === 1, 5000, "the summary")
  eq(notes()[0].body, "4 new notifications", "summary body")
})

test("desktop notifications off", async () => {
  await fresh({ config: JSON.stringify({ desktopNotify: false }) })
  await ctl("notify", { issueId: "issue-2", groupingKey: "issue#issue-2" })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => inboxState().unread === 6, 5000, "the new count")
  await sleep(800)
  eq(notes().length, 0, "notes")
})

test("paging: 230 more issues and an unread notification 120 rows deep", async () => {
  await ctl("reset")
  await ctl("bulk", { issues: 230, notifications: 150, unread: 1 })
  await startBoard()
  await waitFor(() => ev("board.issues.length") >= 239 && ev("board.pending") === 0, 20000, "all issues (" + ev("board.issues.length") + ")")
  await waitFor(() => { const s = inboxState(); return s && s.checkedAt }, 15000, "the inbox")
  const s = inboxState()
  eq(s.unread, 6, "unread count")
  ok(ev("m('loadInbox').items.some(function(n) { return n.title === 'Bulk notification 0' && !n.read })"), "the old unread row was paged in")
})

test("a change made in Linear shows after a refresh", async () => {
  await fresh()
  await ctl("set", { id: "issue-2", fields: { title: "Renamed in Linear" } })
  ev("m('refresh').refresh()")
  await waitFor(() => issue("issue-2").title === "Renamed in Linear", 5000, "the new title")
})

test("an invalid config.json: defaults, still works", async () => {
  await fresh({ config: "{ not json" })
  eq(ev("board.mode"), "board", "mode")
  await waitFor(() => /config\.json is not valid JSON/.test(shellLog()), 5000, "a warning in the log")
})

test("the bar: stale state, an older board, broken file", async () => {
  await fresh()
  await waitFor(() => ev("bar.unread") === 5, 12000, "the bar")
  const file = path.join(RUN, "omarchy-linear-board", "inbox.json")
  const later = new Date(Date.now() + 60000).toISOString()
  // A board that started later but has not checked for 20 minutes.
  const old = new Date(Date.now() - 20 * 60000).toISOString()
  fs.writeFileSync(file, JSON.stringify({ connected: true, unread: 2, items: [], startedAt: later, checkedAt: old, error: "Cannot reach Linear." }))
  ev("bar.apply(" + JSON.stringify(fs.readFileSync(file, "utf8")) + ")")
  eq(ev("bar.health.stale"), true, "stale")
  ok(/Not updated for 20 min: Cannot reach Linear/.test(ev("bar.health.note")), "note: " + ev("bar.health.note"))
  // An older board writing afterwards is ignored.
  ev("bar.apply(" + JSON.stringify(JSON.stringify({ connected: true, unread: 9, items: [], startedAt: "2000-01-01T00:00:00.000Z", checkedAt: new Date().toISOString() })) + ")")
  eq(ev("bar.unread"), 2, "older writer ignored")
  ev("bar.apply('{oops')")
  eq(ev("bar.connected"), false, "broken file")
})

test("creating an issue that times out is not created twice", async () => {
  await fresh()
  await ctl("fault", { match: "^IssueCreate$", kind: "slow", ms: 33000 })
  ev("m('flushOutbox').send('New issue', Linear.M_ISSUE_CREATE, { input: { teamId: 'team-eng', title: 'Timeout test' } }, null)")
  await waitFor(() => outbox() === 1, 55000, "the timed-out create to wait in the outbox")
  await sleep(4000)   // the slow answer arrives on the server side: the issue exists
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(() => outbox() === 0, 5000, "the outbox to empty")
  const made = (await records("Issue")).filter(i => i.title === "Timeout test")
  eq(made.length, 1, "issues created")
  ok(/Back online/.test(toast()), "the retry counts as sent, got " + toast())
})

test("connecting on the setup screen: a wrong key, then a good one", async () => {
  await ctl("reset")
  await startBoard({ noEnvKey: true })
  eq(ev("board.mode"), "setup", "mode without a key")
  ev("board.connect('lin_api_wrong')")
  await waitFor(() => /did not accept/.test(ev("board.setupError")), 5000, "the error: " + ev("board.setupError"))
  ev("board.connect('  lin_api_fake  ')")
  await waitFor(() => ev("board.mode") === "board", 5000, "the board")
  const keyFile = path.join(FILES, "config", "omarchy-linear-board", "api-key")
  await waitFor(() => fs.existsSync(keyFile), 5000, "the key file")
  eq(fs.readFileSync(keyFile, "utf8"), "lin_api_fake\n", "the key file")
  eq((fs.statSync(keyFile).mode & 0o777).toString(8), "600", "key file mode")
  await startBoard({ keepFiles: true, noEnvKey: true })
  eq(ev("board.mode"), "board", "the saved key is used after a restart")
})

test("creating an issue in the editor", async () => {
  await fresh()
  ev("board.open('{}')")
  ev("m('newIssue').newIssue(1)")
  await waitFor(() => ev("board.dialog") === "issue", 3000, "the editor")
  ev("find('titleField').titleField.text = 'Made in the editor'")
  ok(ev("m('saveIssue').saveIssue()"), "saveIssue")
  await waitFor(async () => (await records("Issue")).some(i => i.title === "Made in the editor"), 5000, "the issue on the server")
  const made = (await records("Issue")).find(i => i.title === "Made in the editor")
  ok(/^[0-9a-f-]{36}$/.test(made.id), "a client id: " + made.id)
  eq(made.stateId, "state-unstarted", "the column it was made in")
  await waitFor(() => issue(made.id) !== null, 5000, "the issue on the board")
  ok(/Created ENG-11/.test(toast()), "toast " + toast())
  // An empty title is not sent.
  ev("m('newIssue').newIssue(1)")
  eq(ev("m('saveIssue').saveIssue()"), false, "no title")
})

test("deleting an issue and undoing it", async () => {
  await fresh()
  ev("board.open('{}')")
  ev("m('deleteIssue').deleteIssue('issue-6')")
  ok(/Delete ENG-6/.test(ev("m('runConfirm').confirmText")), "asks first")
  ev("m('runConfirm').runConfirm()")
  await waitFor(async () => (await record("Issue", "issue-6")).trashed, 5000, "trashed on the server")
  eq(issue("issue-6"), null, "gone from the board")
  await waitFor(() => /Deleted ENG-6/.test(toast()), 3000, "the undo toast")
  ev("m('clickToast').clickToast()")
  await waitFor(async () => !(await record("Issue", "issue-6")).trashed, 5000, "restored on the server")
  await waitFor(() => issue("issue-6") !== null, 5000, "back on the board")
})

test("a comment that times out is not posted twice", async () => {
  await fresh()
  await ctl("fault", { match: "^CommentCreate$", kind: "slow", ms: 33000 })
  ev("m('flushOutbox').send('Comment', Linear.M_COMMENT_CREATE, { input: { issueId: 'issue-2', body: 'Only once' } }, null)")
  await waitFor(() => outbox() === 1, 55000, () => "the timed-out comment to wait (toast: " + toast() + ", log: " + shellLog().split("\n").slice(-5).join(" | ") + ")")
  await sleep(4000)
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(() => outbox() === 0, 5000, "the outbox to empty")
  eq((await records("Comment")).filter(c => c.body === "Only once").length, 1, "comments")
})

test("the inbox window", async () => {
  await fresh()
  ev("board.open('{\"inbox\":true}')")
  await waitFor(() => ev("board.dialog") === "inbox", 3000, "the inbox")
  eq(ev("m('loadInbox').shown.length"), 4, "unread rows")
  await shot("inbox")
})

// ---- run ------------------------------------------------------------------------------------------------

async function main() {
  setup()
  await startServer()
  let failed = 0, ran = 0
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
      try { console.log("     screenshot: " + await shot(t.name.replace(/\W+/g, "-").slice(0, 40))) } catch (x) {}
    }
  }
  await stopBoard()
  server.kill()
  if (server.stderrText.trim()) console.log("fake server said:\n" + server.stderrText.trim().split("\n").map(l => "  " + l).join("\n"))
  console.log((failed ? failed + " of " + ran + " failed" : "all " + ran + " passed") + "  (files in " + TMP + ")")
  process.exit(failed ? 1 : 0)
}

main().catch(async e => { console.error(e); await stopBoard(); if (server) server.kill(); process.exit(1) })
