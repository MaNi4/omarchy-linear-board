import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Linear.js" as Linear
import "Dates.js" as Dates
import "Issues.js" as Issues
import "Shared.js" as Shared
import "ui"
import "logic"

// Linear board overlay. Columns are the team's workflow states, cards are
// issues, labels and projects are Linear's own. Every change goes straight
// to Linear; the board updates first and rolls back if Linear refuses.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false

  // ---- files ---------------------------------------------------------------
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy-linear-board"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/omarchy-linear-board"
  readonly property string envKey: Quickshell.env("LINEAR_API_KEY") || ""
  readonly property string endpoint: Linear.endpointFor(Quickshell.env("LINEAR_BOARD_ENDPOINT"))
  // Shared with the bar widget: unread count and the latest unread notifications.
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/omarchy-linear-board"
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-linear-board"
  property bool dirsReady: false
  property bool configLoaded: false    // config.json read (or missing); the shared folder waits for it

  // ---- Linear state ----------------------------------------------------------
  property string apiKey: ""
  property bool keyChecked: false
  property var viewer: null
  property var teams: []
  property var team: null
  property var labels: []
  property var projects: []
  property var members: []
  property var cycles: []
  property var issues: []
  // Issues opened from search, the inbox or a relation that are not on the board.
  property var extraIssues: []
  property var templates: []           // Linear issue templates (all teams)
  // Cards picked for bulk actions (ids).
  property var multi: []
  // assignee: "" anyone, "me", "none" or a user id (filters the board, not the query)
  property var config: ({ teamId: "", projectId: "", assignee: "", hidden: {}, desktopNotify: true, sort: "manual", group: "none",
    timeComments: true, projectCodes: {}, recurring: [], layout: "board", doneWindow: "2weeks" })
  property int pending: 0
  property int teamSeq: 0
  property int editSeq: 0             // bumped by every issue change, so an older refresh does not undo it
  property string syncedAt: ""
  property double syncedAtMs: 0
  property bool loadingTeam: false

  readonly property string mode: !keyChecked ? "loading" : (apiKey ? "board" : "setup")
  readonly property var states: team ? Linear.sortStates(team.states) : []
  readonly property var hiddenStates: team && config.hidden && Array.isArray(config.hidden[team.id]) ? config.hidden[team.id] : null
  readonly property var columns: team ? Issues.visibleStates(team.states, hiddenStates) : []
  readonly property var currentProject: projectById(config.projectId)

  // ---- view state --------------------------------------------------------------
  property string query: ""
  property var labelFilter: []
  property int priorityFilter: -1     // -1 any
  property string cycleFilter: ""     // "" any | current | none | a cycle id
  readonly property var activeCycle: root.cycles.filter(function(c) { return c.isActive })[0] || null
  readonly property string cycleFilterLabel: {
    var f = root.cycleFilter
    if (!f) return "Any cycle"
    if (f === "current") return root.activeCycle ? "Current cycle" : "Current cycle (none)"
    if (f === "none") return "No cycle"
    var c = root.cycleById(f)
    return c ? (c.name || "Cycle " + c.number) : "Cycle"
  }
  property int selCol: 0
  property int selIdx: 0
  property bool cursorShown: false
  property string dialog: ""          // "" | issue | settings | help | picker
  property string settingsTab: "columns"
  property string setupError: ""
  property bool connecting: false

  readonly property var visibleByColumn: {
    var q = root.query, f = root.labelFilter, ls = root.labels, all = root.issues
    var who = root.config.assignee || "", me = root.viewer ? root.viewer.id : "", prio = root.priorityFilter
    var cyc = root.cycleFilter, active = root.activeCycle ? root.activeCycle.id : ""
    var sort = root.config.sort || "manual", group = root.config.group || "none"
    var ctx = { labels: ls, projects: root.projects }
    return root.columns.map(function(s) {
      return Issues.arrange(Issues.issuesIn(all, s.id).filter(function(i) {
        return Issues.passesFilters(i, who, me, prio) && Issues.passesCycle(i, cyc, active) && Issues.issueMatches(i, ls, q, f)
      }), sort, group, ctx)
    })
  }
  readonly property bool manualOrder: (root.config.sort || "manual") === "manual"
  readonly property bool listLayout: (root.config.layout || "board") === "list"
  readonly property bool anyFilter: root.labelFilter.length > 0 || root.query !== "" || root.priorityFilter >= 0 || !!root.config.assignee || root.cycleFilter !== ""

  // Sub-issue counts among the loaded issues: { parentId: { total, done } }.
  readonly property var childStats: {
    var out = {}, sts = root.states
    var closed = {}
    sts.forEach(function(s) { closed[s.id] = s.type === "completed" || s.type === "canceled" })
    root.issues.forEach(function(i) {
      if (!i.parent) return
      var c = out[i.parent.id] || (out[i.parent.id] = { total: 0, done: 0 })
      c.total++
      if (closed[i.stateId]) c.done++
    })
    return out
  }
  property string today: Dates.isoDate(new Date())   // refreshed on every sync
  readonly property var estimateOptions: Linear.estimateOptions(root.team)
  readonly property var selectedIssue: {
    var col = visibleByColumn[selCol]
    return col && col[selIdx] ? col[selIdx] : null
  }

  // ---- look ------------------------------------------------------------------
  readonly property color bg: Commons.Color.menu.background
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color muted: Commons.Color.muted
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int radius: Style.cornerRadius
  readonly property string font: Style.font.family
  readonly property int gap: Style.spacing.lg
  // Height of a standard button; small inputs and chips use it so a row of
  // field + button lines up.
  readonly property real inlineHeight: heightProbe.implicitHeight > 0 ? heightProbe.implicitHeight : Style.spacing.controlHeight
  Button { id: heightProbe; visible: false; text: "Ag"; iconText: root.icon.plus }
  property var themePalette: ({})

  readonly property var icon: ({
    cog: String.fromCodePoint(0xF0493), plus: String.fromCodePoint(0xF0415), close: String.fromCodePoint(0xF0156),
    search: String.fromCodePoint(0xF0349), down: String.fromCodePoint(0xF0140), left: String.fromCodePoint(0xF0141),
    right: String.fromCodePoint(0xF0142), check: String.fromCodePoint(0xF012C), trash: String.fromCodePoint(0xF01B4),
    help: String.fromCodePoint(0xF02D7), refresh: String.fromCodePoint(0xF0450), open: String.fromCodePoint(0xF03CC),
    eye: String.fromCodePoint(0xF0208), eyeOff: String.fromCodePoint(0xF0209), account: String.fromCodePoint(0xF0004),
    inbox: String.fromCodePoint(0xF0687), checkAll: String.fromCodePoint(0xF012D), archive: String.fromCodePoint(0xF120E),
    alert: String.fromCodePoint(0xF05D6), info: String.fromCodePoint(0xF02FD),
    clock: String.fromCodePoint(0xF0150), timer: String.fromCodePoint(0xF13AB), play: String.fromCodePoint(0xF040A),
    stop: String.fromCodePoint(0xF04DB), download: String.fromCodePoint(0xF01DA), upload: String.fromCodePoint(0xF0552), bellOff: String.fromCodePoint(0xF009B),
    mailOpen: String.fromCodePoint(0xF05EF), mail: String.fromCodePoint(0xF01F0), bell: String.fromCodePoint(0xF009A),
    text: String.fromCodePoint(0xF09A8), calendar: String.fromCodePoint(0xF00ED), tree: String.fromCodePoint(0xF0645),
    cycle: String.fromCodePoint(0xF04E6), estimate: String.fromCodePoint(0xF0537), parent: String.fromCodePoint(0xF060D),
    comment: String.fromCodePoint(0xF0182), filter: String.fromCodePoint(0xF0236), send: String.fromCodePoint(0xF048A),
    unassigned: String.fromCodePoint(0xF0BE7), repeat: String.fromCodePoint(0xF0456), flag: String.fromCodePoint(0xF023B),
    list: String.fromCodePoint(0xF0279), board: String.fromCodePoint(0xF056E), project: String.fromCodePoint(0xF01A7), label: String.fromCodePoint(0xF0315), image: String.fromCodePoint(0xF02E9),
    reply: String.fromCodePoint(0xF045A), console: String.fromCodePoint(0xF018D)
  })

  function tint(name) {
    if (name === "muted") return root.muted
    return root.themePalette[name] || root.accent
  }

  function parsePalette(raw) {
    var v = {}
    String(raw || "").split("\n").forEach(function(line) {
      var m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) v[m[1]] = m[2]
    })
    var map = { red: "color1", green: "color2", yellow: "color3", blue: "color4", magenta: "color5", cyan: "color6" }
    var out = {}
    for (var k in map) out[k] = v[k] || v[map[k]] || ""
    out.orange = v.orange || out.yellow
    for (var n in out) if (!out[n]) delete out[n]
    return out
  }

  // ---- lifecycle -------------------------------------------------------------------
  property bool closingFromHost: false

  // The keybinding sends {"toggle": true}: it closes the board when the board
  // is the focused window, and otherwise brings it to the front.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { console.warn("linear-board: ignoring a summon payload that is not JSON") }
    // The bar's timer button: stop the timer, leave the board as it is.
    if (payload.timer === "away") {
      timeTracker.removeAway(payload.from, payload.to)
      if (!(root.opened && panel.visible) && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "mani4.linear-board")
      return
    }
    if (payload.timer === "stop") {
      timeTracker.stopTimer()
      if (!(root.opened && panel.visible) && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "mani4.linear-board")
      return
    }
    if (root.opened && panel.visible) {
      if (payload.toggle && card.Window.active && (!payload.inbox || (root.dialog === "inbox" && !inboxCtl.filtered))) root.dismiss()
      else {
        root.raiseWindow()
        if (payload.inbox) inboxCtl.openInbox()
        if (payload.notification) root.openNotificationById(payload.notification)
        if (payload["new"]) issueOps.newIssue(root.selCol)
        if (payload.help) keyboard.openHelp(String(payload.help))
        if (payload.setup) pickers.openSettings("keys")
        if (payload.issue) inboxCtl.openRef(String(payload.issue).toUpperCase())
      }
      return
    }
    root.opened = true
    panel.visible = true
    root.raiseWindow()
    root.dialog = ""
    pickers.confirmText = ""
    themeColors.reload()
    if (root.apiKey) sync.refresh()
    if (payload.inbox && root.apiKey) inboxCtl.openInbox()
    if (payload.notification) root.openNotificationById(payload.notification)
    Qt.callLater(root.focusBoard)
    if (payload["new"] && root.apiKey) Qt.callLater(function() { issueOps.newIssue(root.selCol) })
    if (payload.help) Qt.callLater(function() { keyboard.openHelp(String(payload.help)) })
    if (payload.setup) Qt.callLater(function() { pickers.openSettings("keys") })
    if (payload.issue && root.apiKey) Qt.callLater(function() { inboxCtl.openRef(String(payload.issue).toUpperCase()) })
  }

  function openNotificationById(id) {
    for (var i = 0; i < inboxCtl.items.length; i++) if (inboxCtl.items[i].id === id) { inboxCtl.openNotification(inboxCtl.items[i]); return }
    inboxCtl.openInbox()
  }

  function close() {
    if (root.dialog === "issue") editorOps.flush()
    root.opened = false
    bulk.endDrag(false)
    root.closingFromHost = true
    panel.visible = false
    root.closingFromHost = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "mani4.linear-board")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Hyprland does not always hand keyboard focus to a window that a running
  // process maps, so ask for it explicitly. The window may take a moment to
  // map, hence a few tries.
  property int raiseTries: 0
  function raiseWindow() {
    root.raiseTries = 0
    raiseTimer.restart()
  }
  Timer {
    id: raiseTimer
    interval: 150
    repeat: true
    onTriggered: {
      root.raiseTries++
      if (!panel.visible || root.raiseTries > 4) { stop(); return }
      if (!raiseProc.running) raiseProc.running = true
      Qt.callLater(root.focusBoard)
    }
  }
  Process {
    id: raiseProc
    command: ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "title:^Linear Board$" })']
  }

  // Give the keyboard to what is in front: the issue editor's title (unless
  // one of its fields already has it), the palette's field, or the board.
  // raiseWindow() calls this a few times while the window maps, so it must
  // not take the focus away from the editor (Super + Alt + Shift + K).
  function focusBoard() {
    if (root.mode === "setup") { setupField.forceActiveFocus(); return }
    if (root.dialog === "issue") {
      var fields = [editor.titleField, editor.descField, editor.commentField, editor.parentField, editor.relationField,
        editor.linkField, editor.edTimeField, editor.edTimeDate, editor.edTimeNote]
      if (!fields.some(function(f) { return f.activeFocus }) && !ed.menu) {
        if (ed.issueId) keyScope.forceActiveFocus()
        else editor.titleField.forceActiveFocus()
      }
      return
    }
    if (root.dialog === "palette") { paletteDialog.paletteField.forceActiveFocus(); return }
    keyScope.forceActiveFocus()
  }

  // ---- desktop notifications ----
  // Sent over D-Bus by bin/linear-notify, which reads them on stdin: issue
  // titles and inbox text never show up in process listings. `payload` is
  // what a click summons on the board (Omarchy runs it, also from the
  // notification history), or null for no click action.
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^[a-z]+:\/\//, "").replace(/\/?$/, "/")
  readonly property string pluginId: (root.manifest && root.manifest.id) || "mani4.linear-board"
  // ---- network -----------------------------------------------------------------------
  // Requests still waiting for Linear: { xhr, at, finish }. A connection left
  // over from before a suspend can hang forever without an error, and then
  // the board stays on "Loading…"; requestWatchdog gives up on it instead.
  property var inflight: []

  Timer {
    id: requestWatchdog
    interval: 2000
    repeat: true
    running: root.inflight.length > 0
    onTriggered: {
      var now = Date.now()
      root.inflight.filter(function(r) { return now - r.at > Linear.requestTimeout(r.at, root.wokeAt) })
        .forEach(function(r) { r.finish(true) })
    }
  }

  // A suspend shows as a gap between ticks. Right after waking, requests on
  // connections from before it hang (6 of them block all the rest), so for a
  // minute they are given up on sooner; what failed is then tried again on
  // fresh connections.
  property double wokeAt: 0
  property double lastTick: Date.now()
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      if (Linear.wokeUp(root.lastTick, now)) root.wokeAt = now
      root.lastTick = now
    }
  }

  // Linear's rate limit: until this time (ms) no request is sent; each one
  // fails with status 429 at once, and changes wait in the outbox.
  property double rateLimitedUntil: 0

  function failRequest(fail, msg, status) {
    if (fail) fail(msg, status)
    else notices.notify(msg, true)
  }

  // Qt does not close a connection when a request on it is given up: the
  // next request reuses it and hangs too, until the system drops it (up to
  // ~15 minutes after a suspend or a network change). So after a request was
  // given up on, requests go through curl (a fresh connection each) for a
  // while; then the board tries its own connections again.
  readonly property int curlAfterTimeoutMs: 15 * 60000
  property double viaCurlUntil: 0

  function gqlWith(key, query, variables, ok, fail) {
    if (Date.now() < root.rateLimitedUntil) {
      var wait = "Linear's rate limit was reached. Trying again after " + Qt.formatTime(new Date(root.rateLimitedUntil), "HH:mm") + "."
      Qt.callLater(function() { if (root) root.failRequest(fail, wait, 429) })
      return
    }
    var viaCurl = Date.now() < root.viaCurlUntil
    var req = { at: Date.now(), finish: null, abort: null }
    var done = false
    root.pending++
    root.inflight = root.inflight.concat([req])
    // status 0: no answer. header(name) reads a response header.
    var settle = function(status, text, header, timedOut) {
      if (done || !root) return   // !root: the board was unloaded (shell restart) while this was in flight
      done = true
      root.inflight = root.inflight.filter(function(r) { return r !== req })
      root.pending = Math.max(0, root.pending - 1)
      var body = null
      if (status > 0) try { body = JSON.parse(text) } catch (e) { body = null }
      if (status === 200 && body && body.data && !body.errors) {
        // A handler that throws (an answer of an unexpected shape) is
        // reported like a failed request, so nothing waits for it forever.
        if (ok) try { ok(body.data) } catch (e) {
          console.warn("linear-board: could not use Linear's answer: " + e)
          root.failRequest(fail, "Linear's answer could not be read.", -1)
        }
      } else {
        if (status > 0 && Linear.isRateLimited(body, status)) {
          status = 429
          root.rateLimitedUntil = Linear.rateLimitUntil(header("X-RateLimit-Requests-Reset"), header("Retry-After"), Date.now())
        }
        var msg = timedOut ? "Linear did not answer. Check your connection and try again." : Linear.errorMessage(body, status)
        if (status === 401 || /authenticat/i.test(msg)) sync.keyRejected(key, msg)
        root.failRequest(fail, msg, status)
      }
    }
    req.finish = function(timedOut) {
      if (done) return
      if (timedOut && !viaCurl) {
        root.viaCurlUntil = Date.now() + root.curlAfterTimeoutMs
        console.warn("linear-board: a request to Linear hung; using fresh connections (curl) for the next " + (root.curlAfterTimeoutMs / 60000) + " minutes")
      }
      settle(0, "", null, true)
      if (req.abort) req.abort()
    }
    var payload = JSON.stringify({ query: query, variables: variables || {} })
    if (viaCurl) {
      var proc = curlRequest.createObject(root, { config: Linear.curlConfig(root.endpoint, key, payload, uploads.curlQuote) })
      proc.done.connect(function(status, text) { settle(status, text, function() { return null }, false) })
      req.abort = function() { if (proc) proc.running = false }
      proc.running = true
      return
    }
    var xhr = new XMLHttpRequest()
    req.abort = function() { xhr.abort() }
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) settle(xhr.status, xhr.responseText, function(n) { return xhr.getResponseHeader(n) }, false)
    }
    xhr.open("POST", root.endpoint)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Authorization", key)
    xhr.send(payload)
  }

  // One request through curl. The key and the body go in as a config on
  // stdin, never as arguments anyone can list. done(status, body): status
  // is 0 when curl got no answer.
  Component {
    id: curlRequest
    Process {
      id: curlProc
      property string config: ""
      property bool exited: false
      property bool read: false
      property int exitCode: 0
      signal done(int status, string text)
      command: ["curl", "-K", "-"]
      stdinEnabled: true
      onStarted: { curlProc.write(curlProc.config); curlProc.config = ""; stdinEnabled = false }
      stdout: StdioCollector {
        onStreamFinished: { curlProc.read = true; curlProc.finishIfDone() }
      }
      onExited: function(code) { curlProc.exitCode = code; curlProc.exited = true; curlProc.finishIfDone() }
      function finishIfDone() {
        if (!curlProc.exited || !curlProc.read) return
        var r = Linear.curlResult(curlProc.exitCode, curlProc.stdout.text)
        curlProc.done(r.status, r.body)
        Qt.callLater(function() { curlProc.destroy() })
      }
    }
  }

  function gql(query, variables, ok, fail) {
    if (!root.apiKey) return
    root.gqlWith(root.apiKey, query, variables, ok, fail)
  }

  Sync { id: sync }

  // ---- key / config / cache files ----------------------------------------------------
  function connect(key) {
    key = String(key || "").trim()
    if (!key) { root.setupError = "Paste your Linear API key first."; return }
    root.connecting = true
    root.setupError = ""
    root.gqlWith(key, Linear.Q_BOOT, {}, function(data) {
      root.connecting = false
      root.apiKey = key
      setupField.text = ""
      if (key !== root.envKey) privateFiles.write(keyFile, key + "\n")
      sync.applyBoot(data)
      sync.loadTeam()
      Qt.callLater(root.focusBoard)
    }, function(msg) {
      root.connecting = false
      root.setupError = /authenticat|401|rejected/i.test(msg) ? "Linear did not accept this key. Check that you copied all of it." : msg
    })
  }

  function disconnect() {
    root.apiKey = ""
    root.viewer = null
    root.teams = []
    root.team = null
    root.issues = []
    root.labels = []
    root.projects = []
    root.members = []
    root.cycles = []
    inboxCtl.items = []
    inboxCtl.unreadCount = 0
    inboxCtl.since = ""
    inboxCtl.writeInboxState()
    root.dialog = ""
    privateFiles.write(keyFile, "")
    privateFiles.write(cacheFile, "{}\n")
    Qt.callLater(root.focusBoard)
  }

  function setConfig(patch) {
    var next = {}
    for (var k in root.config) next[k] = root.config[k]
    for (var p in patch) next[p] = patch[p]
    var toShare = Shared.differs(root.config, next)
    root.config = next
    if (root.dirsReady) privateFiles.write(configFile, JSON.stringify(next, null, 2) + "\n")
    if (toShare) shared.save()
  }

  // Settings that came from the shared folder: kept in config.json too, not written back.
  function applySharedConfig(next) {
    var reload = Linear.doneWindow(next.doneWindow).id !== Linear.doneWindow(root.config.doneWindow).id
    root.config = next
    if (reload && root.team) sync.loadTeam()
    if (root.dirsReady) privateFiles.write(configFile, JSON.stringify(next, null, 2) + "\n")
    root.clampSelection()
  }

  function saveCache() {
    if (!root.dirsReady) return
    privateFiles.write(cacheFile, JSON.stringify({
      teamId: root.config.teamId, projectId: root.config.projectId,
      viewer: root.viewer, teams: root.teams, team: root.team, labels: root.labels,
      projects: root.projects, members: root.members, cycles: root.cycles, issues: root.issues
    }) + "\n")
  }

  function applyCache(raw) {
    var c = null
    try { c = JSON.parse(raw) } catch (e) { return }
    // Network data that arrived first is fresher than the cache.
    if (!c || !c.team || c.teamId !== root.config.teamId || root.team) return
    root.viewer = c.viewer
    root.teams = c.teams || []
    root.team = c.team
    root.labels = c.labels || []
    root.projects = c.projects || []
    root.members = c.members || []
    root.cycles = c.cycles || []
    if (c.projectId === root.config.projectId) root.issues = c.issues || []
  }

  Process {
    id: mkdirs
    // Files an older version left readable by others become 0600 (see logic/PrivateFiles.qml).
    command: ["sh", "-c", "umask 077 && mkdir -p \"$1\" \"$2\" \"$3\" \"$4\" && find \"$@\" -type f ! -perm 600 -exec sh -c '" + privateFiles.tightenScript.replace(/'/g, "'\\''") + "' sh {} +",
      "sh", root.configDir, root.cacheDir, root.runtimeDir, root.dataDir]
    // Started once everything exists: the command reads privateFiles, made further down.
    Component.onCompleted: running = true
    onExited: function(code, status) {
      root.dirsReady = true
      configFile.path = root.configDir + "/config.json"
      timeTracker.timeLocationFile.path = root.configDir + "/time-location"
    }
  }

  FileView {
    id: configFile
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var c = JSON.parse(text())
        if (c && typeof c === "object") root.config = {
          teamId: String(c.teamId || ""), projectId: String(c.projectId || ""),
          // onlyMine is the older setting this replaced
          assignee: String(c.assignee || (c.onlyMine === true ? "me" : "")),
          hidden: c.hidden && typeof c.hidden === "object" ? c.hidden : {},
          desktopNotify: c.desktopNotify !== false,
          sort: String(c.sort || "manual"), group: String(c.group || "none"),
          timeComments: c.timeComments !== false,
          projectCodes: c.projectCodes && typeof c.projectCodes === "object" ? c.projectCodes : {},
          recurring: Array.isArray(c.recurring) ? c.recurring : [],
          layout: c.layout === "list" ? "list" : "board",
          doneWindow: Linear.doneWindow(c.doneWindow).id
        }
      } catch (e) { console.warn("linear-board: config.json is not valid JSON, the defaults are used: " + e) }
      root.configLoaded = true
      root.loadKey()
    }
    onLoadFailed: { root.configLoaded = true; root.loadKey() }
  }

  function loadKey() {
    if (root.envKey) { root.apiKey = root.envKey; root.afterKey(); return }
    keyFile.path = root.configDir + "/api-key"
  }

  function afterKey() {
    root.keyChecked = true
    cacheFile.path = root.cacheDir + "/cache.json"
    if (root.apiKey) sync.refresh()
    if (root.opened) Qt.callLater(root.focusBoard)
  }

  FileView {
    id: keyFile
    printErrors: false
    atomicWrites: true
    blockWrites: true
    onLoaded: {
      if (!root.keyChecked) { root.apiKey = text().trim(); root.afterKey() }
    }
    onLoadFailed: if (!root.keyChecked) root.afterKey()
  }

  FileView {
    id: cacheFile
    printErrors: false
    atomicWrites: true
    property bool applied: false
    onLoaded: if (!applied) { applied = true; root.applyCache(text()) }
    onLoadFailed: applied = true
  }

  FileView {
    id: themeColors
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.themePalette = root.parsePalette(text())
  }

  Notices { id: notices }

  PrivateFiles { id: privateFiles }

  Clipboard { id: clipboard }

  TimeTracker { id: timeTracker }

  SharedFolder { id: shared }

  InboxCtl { id: inboxCtl }

  Lists { id: lists }

  // ---- lookups -------------------------------------------------------------------------
  function labelById(id) { return Issues.labelById(root.labels, id) }
  function projectById(id) {
    if (!id) return null
    for (var i = 0; i < root.projects.length; i++) if (root.projects[i].id === id) return root.projects[i]
    return null
  }
  function stateById(id) {
    for (var i = 0; i < root.states.length; i++) if (root.states[i].id === id) return root.states[i]
    return null
  }
  // Short code of a project (the web), shown next to issue ids.
  function codeFor(projectId) { return Issues.projectCode(root.projectById(projectId), root.config.projectCodes) }
  function colorFor(projectId) { var p = root.projectById(projectId); return p && p.color ? p.color : root.accent }

  function setProjectCode(projectId, code) {
    var codes = {}
    for (var k in (root.config.projectCodes || {})) codes[k] = root.config.projectCodes[k]
    code = String(code || "").trim().toUpperCase()
    var p = root.projectById(projectId)
    if (!code || (p && code === Issues.projectCode(p, {}))) delete codes[projectId]
    else codes[projectId] = code
    root.setConfig({ projectCodes: codes })
  }

  function changeTeamKey(key) {
    key = String(key || "").trim().toUpperCase()
    if (!key || !root.team || key === root.team.key) return
    if (!/^[A-Z0-9]{1,7}$/.test(key)) { notices.notify("Use 1–7 letters or digits, e.g. WEB", true); return }
    var old = root.team.key
    pickers.ask("Change the issue prefix of " + root.team.name + " from " + old + " to " + key + "? Every issue is renumbered (" + old + "-12 becomes " + key + "-12); old links keep working in Linear.", "Change", function() {
      root.gql(Linear.M_TEAM_UPDATE, { id: root.team.id, input: { key: key } }, function(data) {
        var t = data.teamUpdate.team
        root.teams = root.teams.map(function(x) { return x.id === t.id ? t : x })
        notices.notify("Issues of " + t.name + " now start with " + t.key)
        sync.loadTeam()
      }, function(msg) { notices.notify("Could not change the prefix: " + msg, true) })
    })
  }

  function memberById(id) {
    if (!id) return null
    for (var i = 0; i < root.members.length; i++) if (root.members[i].id === id) return root.members[i]
    return null
  }
  function milestoneById(id) {
    if (!id) return null
    var all = root.projects.concat(ed.teamData ? ed.teamData.projects : [])
    for (var i = 0; i < all.length; i++) {
      var ms = all[i].milestones || []
      for (var j = 0; j < ms.length; j++) if (ms[j].id === id) return ms[j]
    }
    return null
  }
  function cycleById(id) {
    if (!id) return null
    for (var i = 0; i < root.cycles.length; i++) if (root.cycles[i].id === id) return root.cycles[i]
    return null
  }
  function issueById(id) {
    for (var i = 0; i < root.issues.length; i++) if (root.issues[i].id === id) return root.issues[i]
    for (var j = 0; j < root.extraIssues.length; j++) if (root.extraIssues[j].id === id) return root.extraIssues[j]
    return null
  }
  // Does the issue belong on this board: its team and, with a project
  // picked, that project?
  function fitsBoard(issue) {
    return !!issue && (!root.team || !issue.teamId || issue.teamId === root.team.id)
      && (!root.config.projectId || issue.projectId === root.config.projectId)
  }
  // Issues changed so they no longer fit (moved to another project) leave
  // the board at once instead of at the next refresh. They stay known in
  // extraIssues, so an open editor or undo still finds them.
  function dropMisfits() {
    var gone = root.issues.filter(function(i) { return !root.fitsBoard(i) })
    if (!gone.length) return
    root.issues = root.issues.filter(function(i) { return root.fitsBoard(i) })
    gone.forEach(function(i) { root.extraIssues = Issues.upsertIssue(root.extraIssues, i) })
  }
  // The other way, after an undo: issues that fit again come back.
  function takeBack(ids) {
    var back = root.extraIssues.filter(function(i) { return ids.indexOf(i.id) >= 0 && root.fitsBoard(i) })
    if (!back.length) return
    root.extraIssues = root.extraIssues.filter(function(i) { return back.indexOf(i) < 0 })
    back.forEach(function(i) { root.issues = Issues.upsertIssue(root.issues, i) })
  }
  // Why the issue in the editor is not on the board ("" when it is).
  function offBoardReason(issue) {
    if (!issue) return ""
    var shown = root.visibleByColumn.some(function(col) { return col.some(function(i) { return i.id === issue.id }) })
    var me = root.viewer ? root.viewer.id : "", active = root.activeCycle ? root.activeCycle.id : ""
    var filtered = Issues.passesFilters(issue, root.config.assignee || "", me, root.priorityFilter)
      && Issues.passesCycle(issue, root.cycleFilter, active) && Issues.issueMatches(issue, root.labels, root.query, root.labelFilter)
    return Issues.offBoardReason(issue, { teamId: root.team ? root.team.id : "", teamName: root.team ? root.team.name : "",
      projectId: root.config.projectId || "", projectName: root.currentProject ? root.currentProject.name : "",
      doneWindow: root.config.doneWindow, hidden: root.hiddenStates || [], shown: shown, filtered: filtered, now: new Date() })
  }

  // Every issue of the team, done ones of any age too, as one list: for
  // cleaning up (archive or delete what is not needed). V → Completed undoes it.
  function showEverything() {
    workspace.clearFilters(true)
    var patch = {}
    if (root.config.projectId) patch.projectId = ""
    if (Linear.doneWindow(root.config.doneWindow).id !== "all") patch.doneWindow = "all"
    if ((root.config.layout || "board") !== "list") patch.layout = "list"
    if (Object.keys(patch).length) root.setConfig(patch)
    if (patch.projectId !== undefined) root.issues = []
    if (patch.projectId !== undefined || patch.doneWindow) sync.loadTeam()
    notices.notify("Every issue of " + (root.team ? root.team.name : "the team") + ", done ones too. X or Ctrl+A selects, then archive (Ctrl+Shift+X) or delete. V → Completed: Past 2 weeks goes back.")
  }

  function onBoard(id) {
    for (var i = 0; i < root.issues.length; i++) if (root.issues[i].id === id) return true
    return false
  }

  // Keep a saved issue where it lives: on the board, or among the extra ones.
  function storeIssue(issue) {
    if (!issue) return
    if (root.onBoard(issue.id)) root.issues = Issues.upsertIssue(root.issues, issue)
    else root.extraIssues = Issues.upsertIssue(root.extraIssues, issue)
  }

  // Open an issue in the editor even when it is not on the board (it is
  // fetched first). Issues of other teams open in Linear, since the editor
  // offers this team's columns and labels.
  function openIssueAnywhere(id, url) {
    if (!id) { editorOps.openInLinear(url); return }
    var known = root.issueById(id)
    if (known && (!known.teamId || !root.team || known.teamId === root.team.id)) { issueOps.editIssue(id); return }
    if (known) { lists.switchTeamAndEdit(known.teamId, id); return }
    root.gql(Linear.Q_ISSUE, { id: id }, function(d) {
      var issue = Linear.toIssue(d.issue)
      if (!issue) { editorOps.openInLinear(url); return }
      if (root.team && issue.teamId && issue.teamId !== root.team.id) { lists.switchTeamAndEdit(issue.teamId, issue.id); return }
      root.extraIssues = Issues.upsertIssue(root.extraIssues, issue)
      issueOps.editIssue(issue.id)
    }, function(msg) { notices.notify(msg, true); editorOps.openInLinear(url) })
  }
  function columnOfState(stateId) {
    for (var i = 0; i < root.columns.length; i++) if (root.columns[i].id === stateId) return i
    return -1
  }
  function countIn(stateId) { return Issues.issuesIn(root.issues, stateId).length }

  // ---- selection ------------------------------------------------------------------------
  function clampSelection() {
    root.selCol = Math.max(0, Math.min(root.selCol, root.columns.length - 1))
    var n = (root.visibleByColumn[root.selCol] || []).length
    root.selIdx = Math.max(0, Math.min(root.selIdx, n - 1))
  }

  // Point the cursor at an issue without scrolling; false when it is not on the board.
  function locateIssue(id) {
    var cols = root.visibleByColumn
    for (var c = 0; c < cols.length; c++)
      for (var i = 0; i < cols[c].length; i++)
        if (cols[c][i].id === id) { root.selCol = c; root.selIdx = i; return true }
    return false
  }

  function selectIssue(id) {
    if (root.locateIssue(id)) root.ensureVisible()
  }

  function moveCursor(dc, di) {
    root.cursorShown = true
    if (dc !== 0) {
      root.selCol = Math.max(0, Math.min(root.selCol + dc, root.columns.length - 1))
      var n = (root.visibleByColumn[root.selCol] || []).length
      root.selIdx = Math.max(0, Math.min(root.selIdx, n - 1))
    }
    if (di !== 0) {
      var m = (root.visibleByColumn[root.selCol] || []).length
      var to = root.selIdx + di
      // The list layout is one long list: past a group's end, go on in the next one.
      if (root.listLayout && (to < 0 || to >= m)) {
        for (var c = root.selCol + (di > 0 ? 1 : -1); c >= 0 && c < root.columns.length; c += (di > 0 ? 1 : -1)) {
          var k = (root.visibleByColumn[c] || []).length
          if (k) { root.selCol = c; root.selIdx = di > 0 ? 0 : k - 1; root.ensureVisible(); return }
        }
      }
      root.selIdx = Math.max(0, Math.min(to, m - 1))
    }
    root.ensureVisible()
  }

  // The mouse over a card hides the keyboard cursor, but only when the mouse
  // itself moved: cards scrolled under a resting pointer (arrow keys) do not.
  property real lastPointerX: -1
  property real lastPointerY: -1
  property double keyNavAt: 0
  function pointerMoved(item, x, y) {
    var g = item.mapToGlobal(x, y)
    var known = root.lastPointerX >= 0
    var moved = Math.abs(g.x - root.lastPointerX) > 2 || Math.abs(g.y - root.lastPointerY) > 2
    root.lastPointerX = g.x
    root.lastPointerY = g.y
    return known ? moved : Date.now() - root.keyNavAt > 600
  }

  function ensureVisible() {
    root.keyNavAt = Date.now()
    if (root.listLayout) {
      var g = boardScreen.listGroups.itemAt(root.selCol)
      if (!g) return
      var y = g.rowY(root.selIdx), h = g.rowH(root.selIdx)
      if (y < boardScreen.listFlick.contentY) boardScreen.listFlick.contentY = Math.max(0, y - Style.spacing.lg)
      else if (y + h > boardScreen.listFlick.contentY + boardScreen.listFlick.height) boardScreen.listFlick.contentY = y + h - boardScreen.listFlick.height + Style.spacing.lg
      return
    }
    var item = boardScreen.colRepeater.itemAt(root.selCol)
    if (!item) return
    if (item.x < boardScreen.boardFlick.contentX) boardScreen.boardFlick.contentX = item.x
    else if (item.x + item.width > boardScreen.boardFlick.contentX + boardScreen.boardFlick.width)
      boardScreen.boardFlick.contentX = item.x + item.width - boardScreen.boardFlick.width
    item.ensureCardVisible(root.selIdx)
  }

  Undoer { id: undoer }

  IssueOps { id: issueOps }

  EditorState { id: ed }
  EditorOps { id: editorOps }

  Uploads { id: uploads }

  Workspace { id: workspace }

  Commands { id: commands }

  ProjectOps { id: projectOps }

  Pickers { id: pickers }

  Bulk { id: bulk }

  Hotkeys { id: hotkeys }

  Keyboard { id: keyboard }

  // ---- window ---------------------------------------------------------------------------------
  // A normal window, so Hyprland tiles it, moves it between workspaces and
  // closes it with the usual keys like any other app.
  FloatingWindow {
    id: panel
    visible: false
    title: "Linear Board"
    color: root.bg
    implicitWidth: Style.space(1400)
    implicitHeight: Style.space(860)
    minimumSize: Qt.size(Style.space(640), Style.space(420))

    onVisibleChanged: {
      if (visible) Qt.callLater(root.focusBoard)
      else if (!root.closingFromHost && root.opened) root.dismiss()
    }

    Item {
      id: card
      anchors.fill: parent
      readonly property real contentTopInset: Style.spacing.panelPadding
      readonly property real contentRightInset: Style.spacing.panelPadding
      readonly property real contentBottomInset: Style.spacing.panelPadding
      readonly property real contentLeftInset: Style.spacing.panelPadding

      // Coming back to the board after a while: pick up what changed meanwhile.
      Window.onActiveChanged: if (Window.active && Date.now() - root.syncedAtMs > 15000) sync.backgroundRefresh()

      // A plain Item, not a FocusScope: forceActiveFocus() on a FocusScope hands
      // focus back to the last focused child (e.g. the search field), so the
      // board would never get the keys back.
      Item {
        id: keyScope
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true
        Keys.onPressed: function(event) { keyboard.handleKey(event) }

        // ================= loading =================
        Label {
          anchors.centerIn: parent
          visible: root.mode === "loading"
          text: "Loading…"
          opacity: 0.6
        }

        // ================= setup =================
        Column {
          id: setup
          visible: root.mode === "setup"
          anchors.centerIn: parent
          width: Math.min(parent.width, Style.space(520))
          spacing: Style.spacing.xxl

          Label { text: "Connect Linear"; font.pixelSize: Style.font.display; font.bold: true }
          Label {
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            opacity: 0.8
            text: "The board shows your Linear issues by workflow state. It needs a personal API key, which stays on this machine (" + root.configDir.replace(root.home, "~") + "/api-key)."
          }
          Row {
            spacing: Style.spacing.lg
            Label { text: "1"; color: root.accent; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Label { text: "Create a key in Linear: Settings → Security & access → Personal API keys"; anchors.verticalCenter: parent.verticalCenter }
          }
          Button {
            tooltipText: "Opens Linear → Settings → Security & access"
            text: "Open Linear settings"
            iconText: root.icon.open
            bordered: true
            onClicked: editorOps.openInLinear(Linear.KEY_URL)
          }
          Row {
            spacing: Style.spacing.lg
            Label { text: "2"; color: root.accent; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Label { text: "Paste it here and press Enter"; anchors.verticalCenter: parent.verticalCenter }
          }
          SecretField {
            id: setupField
            width: parent.width
            placeholderText: "lin_api_…"
            Keys.onReturnPressed: function(event) { root.connect(setupField.text); event.accepted = true }
            Keys.onEnterPressed: function(event) { root.connect(setupField.text); event.accepted = true }
          }
          Row {
            spacing: Style.spacing.lg
            Button {
              tooltipText: "Connect (Enter)"
              text: root.connecting ? "Connecting…" : "Connect"
              bordered: true
              accent: root.accent
              selected: true
              onClicked: root.connect(setupField.text)
            }
            Button { tooltipText: "Close (Esc)"; text: "Close"; onClicked: root.dismiss() }
          }
          Label {
            visible: root.setupError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: root.urgent
            text: root.setupError
          }
        }

        // ================= board =================
        BoardView { id: boardScreen }

        // ================= bulk bar =================
        BulkBar { id: bulkBar }

        // ================= drag ghost =================
        Item {
          id: dragLayer
          anchors.fill: parent
          z: 50
          Rectangle {
            visible: bulk.dragging
            x: bulk.dragPoint.x - bulk.dragOffset.x
            y: bulk.dragPoint.y - bulk.dragOffset.y
            width: root.listLayout ? Math.min(Style.space(480), boardScreen.listFlick.width * 0.6) : boardScreen.boardFlick.columnWidth - Style.spacing.md * 2
            height: ghostText.implicitHeight + Style.spacing.xl * 2
            rotation: 1.5
            radius: root.radius
            color: Qt.lighter(root.bg, 1.25)
            border.width: Math.max(1, Style.space(2))
            border.color: root.accent
            Label {
              id: ghostText
              anchors.fill: parent
              anchors.margins: Style.spacing.xl
              text: bulk.dragTitle
              wrapMode: Text.Wrap
              maximumLineCount: 3
            }
          }
        }

        // ================= dialogs =================
        Rectangle {
          id: modalScrim
          anchors.fill: parent
          z: 60
          visible: root.dialog === "issue" || root.dialog === "settings" || root.dialog === "inbox" || root.dialog === "search" || root.dialog === "time"
            || root.dialog === "palette" || root.dialog === "project"
          color: Util.alpha(root.bg, 0.6)
          MouseArea { anchors.fill: parent; onClicked: pickers.closeDialog() }
        }

        // ---- picker (team / project) ----
        PickerPopup { id: pickerPopup }

        // ---- issue editor ----
        IssueEditor { id: editor }

        // ---- settings ----
        SettingsDialog { id: settings }

        // ---- time report ----
        TimeReport { id: timeDialog }

        // ---- search results ----
        IssueListDialog { id: issueListDialog }

        // ---- inbox ----
        InboxDialog { id: inboxDialog }

        // ---- command palette (Ctrl+K) ----
        CommandPalette { id: paletteDialog }

        // ---- project overview ----
        ProjectDialog { id: projectDialog }

        // ---- shortcut help (for the window it was opened from) ----
        HelpOverlay { id: helpOverlay }

        // ---- toast: short messages (copied, saved, errors), above everything ----
        Toast { id: toastBox }

        // ---- confirm ----
        ConfirmBox { id: confirmBox }
      }

      // Clicking anywhere outside a text field gives the keyboard back to the
      // board, so shortcuts work again after using search or a settings field.
      // The press is passed on untouched (accepted = false), and text fields
      // still take focus themselves when they are the thing clicked.
      MouseArea {
        anchors.fill: parent
        z: 10000
        acceptedButtons: Qt.AllButtons
        onPressed: function(mouse) {
          if (root.dialog !== "issue") keyScope.forceActiveFocus()
          mouse.accepted = false
        }
      }
    }
  }
}
