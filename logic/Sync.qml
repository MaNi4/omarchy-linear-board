import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Linear.js" as Linear
import "../Dates.js" as Dates
import "../Edit.js" as Edit

// Offline outbox, refresh and loading the team.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `sync`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: sync
  visible: false

  // ---- offline outbox ----
  // Changes that could not reach Linear (no network) wait here, in order,
  // and are sent when Linear answers again; the board keeps showing them.
  // Kept in ~/.cache/omarchy-linear-board/outbox.json across restarts.
  property var outbox: []
  property bool outboxFlushing: false

  function send(label, query, variables, ok, fail) {
    root.gql(query, variables, ok, function(msg, status) {
      // Offline (0) or Linear's rate limit (429): sent later, from the outbox.
      if ((status === 0 || status === 429) && root.apiKey) { sync.enqueue(label, query, variables, ok, status); return }
      if (fail) fail(msg, status)
      else notices.notify(msg, true)
    })
  }

  function enqueue(label, query, variables, ok, status) {
    // Edits of one issue in a row (typing while offline) are one entry:
    // the later values win.
    var last = sync.outbox[sync.outbox.length - 1]
    if (Edit.outboxJoins(last, query, variables, sync.outboxFlushing, Linear.M_ISSUE_UPDATE)) {
      var input = Edit.mergeInput(last.variables.input, variables.input)
      var prevOk = last.ok
      var merged = { label: label, query: query, variables: { id: variables.id, input: input },
        ok: function(data) { if (prevOk) prevOk(data); if (ok) ok(data) } }
      sync.outbox = sync.outbox.slice(0, -1).concat([merged])
      sync.saveOutbox()
      return
    }
    sync.outbox = sync.outbox.concat([{ label: label, query: query, variables: variables, ok: ok || null }])
    sync.saveOutbox()
    notices.notify((status === 429 ? "Linear's rate limit: " + label + " will be sent in a while"
      : "Offline: " + label + " will be sent when Linear is reachable") + " (" + sync.outbox.length + " waiting)", true)
  }

  function saveOutbox() {
    if (!root.dirsReady) return
    privateFiles.write(outboxFile, JSON.stringify(sync.outbox.map(function(o) { return { label: o.label, query: o.query, variables: o.variables } })) + "\n")
  }

  function flushOutbox() {
    if (sync.outboxFlushing || !sync.outbox.length || !root.apiKey) return
    sync.outboxFlushing = true
    var item = sync.outbox[0]
    root.gql(item.query, item.variables, function(data) {
      sync.outbox = sync.outbox.slice(1)
      sync.saveOutbox()
      sync.outboxFlushing = false
      if (item.ok) { try { item.ok(data) } catch (e) { console.warn("linear-board: updating the board after a waiting change failed: " + e) } }
      if (sync.outbox.length) sync.flushOutbox()
      else { notices.notify("Back online: everything was sent to Linear"); sync.loadTeam() }
    }, function(msg, status) {
      sync.outboxFlushing = false
      if (status === 0 || status === 429) return   // still offline or rate limited, try again later
      sync.outbox = sync.outbox.slice(1)
      sync.saveOutbox()
      notices.notify("Linear refused a waiting change (" + item.label + "): " + msg, true)
      if (sync.outbox.length) sync.flushOutbox()
      else sync.loadTeam()
    })
  }

  Timer {
    interval: 15000
    repeat: true
    running: sync.outbox.length > 0
    onTriggered: sync.flushOutbox()
  }

  FileView {
    id: outboxFile
    path: root.dirsReady ? root.cacheDir + "/outbox.json" : ""
    printErrors: false
    atomicWrites: true
    property bool applied: false
    onLoaded: {
      if (applied) return
      applied = true
      try {
        var list = JSON.parse(text())
        if (Array.isArray(list) && list.length) {
          sync.outbox = list.map(function(o) { return { label: o.label, query: o.query, variables: o.variables, ok: null } })
          Qt.callLater(sync.flushOutbox)
        }
      } catch (e) { console.warn("linear-board: outbox.json could not be read, waiting changes are lost: " + e) }
    }
    onLoadFailed: applied = true
  }

  function keyRejected(key, msg) {
    if (key !== root.apiKey || !root.apiKey) return
    root.apiKey = ""
    root.setupError = msg
    inboxCtl.writeInboxState()
    Qt.callLater(root.focusBoard)
  }

  function refresh() {
    if (!root.apiKey) return
    inboxCtl.loadInbox()
    root.gql(Linear.Q_TEMPLATES, {}, function(d) { root.templates = d.templates || [] }, function() {})
    if (!root.viewer || root.teams.length === 0) sync.boot()
    else sync.loadTeam()
  }

  function boot() {
    root.gql(Linear.Q_BOOT, {}, function(data) {
      sync.applyBoot(data)
      sync.loadTeam()
    })
  }

  function applyBoot(data) {
    root.viewer = data.viewer
    root.teams = data.teams.nodes
    var teamId = root.config.teamId
    if (!root.teams.some(function(t) { return t.id === teamId })) {
      root.setConfig({ teamId: root.teams.length ? root.teams[0].id : "", projectId: "" })
    }
  }

  // Fetch every page of a connection. `pick` returns the connection from the
  // response data; `ok` gets all nodes.
  // enough(nodes), when given, stops paging early once it returns true.
  function gqlAll(query, variables, pick, ok, fail, maxPages, enough) {
    var nodes = [], pages = 0, limit = maxPages || Linear.MAX_PAGES
    var step = function(after) {
      var v = {}
      for (var k in variables) v[k] = variables[k]
      if (after) v.after = after
      root.gql(query, v, function(data) {
        var conn = pick(data)
        if (conn) nodes = nodes.concat(conn.nodes || [])
        var info = conn && conn.pageInfo
        var more = !!(info && info.hasNextPage && info.endCursor)
        if (more && ++pages < limit && !(enough && enough(nodes))) { step(info.endCursor); return }
        // Cut off by the page limit (not by `enough`): say so instead of
        // showing part of the list as if it were all.
        if (more && pages >= limit && !enough) {
          console.warn("linear-board: stopped after " + limit + " pages (" + nodes.length + " items)")
          notices.notify("Linear has more than " + nodes.length + " here; only those are shown.", true)
        }
        ok(nodes)
      }, fail)
    }
    step("")
  }

  // Load the team's columns, labels, projects, members, cycles and issues,
  // then apply them all at once so the board does not flicker.
  function loadTeam() {
    var teamId = root.config.teamId
    if (!teamId) { root.team = null; root.issues = []; return }
    var seq = ++root.teamSeq
    var edits = root.editSeq
    root.loadingTeam = true
    var got = {}, left = 8, failed = false
    var fail = function(msg) {
      if (seq !== root.teamSeq || failed) return
      failed = true
      root.loadingTeam = false
      notices.notify(msg, true)
    }
    var take = function(key) {
      return function(value) {
        got[key] = value
        if (--left === 0 && seq === root.teamSeq && !failed) sync.applyTeam(got, edits)
      }
    }
    var of = function(name) { return function(d) { return d.team ? d.team[name] : null } }
    var v = { teamId: teamId }
    root.gql(Linear.Q_TEAM, v, function(d) { take("team")(d.team) }, fail)
    sync.gqlAll(Linear.Q_STATES, v, of("states"), take("states"), fail)
    sync.gqlAll(Linear.Q_LABELS, v, of("labels"), take("labels"), fail)
    sync.gqlAll(Linear.Q_WS_LABELS, {}, function(d) { return d.issueLabels }, take("wsLabels"), fail)
    sync.gqlAll(Linear.Q_PROJECTS, v, of("projects"), take("projects"), fail)
    sync.gqlAll(Linear.Q_MEMBERS, v, of("members"), take("members"), fail)
    sync.gqlAll(Linear.Q_CYCLES, v, of("cycles"), take("cycles"), fail)
    sync.gqlAll(Linear.Q_ISSUES, { filter: Linear.issueFilter(teamId, root.config.projectId, root.config.doneWindow) },
      function(d) { return d.issues }, take("issues"), fail)
  }

  function applyTeam(got, edits) {
    root.loadingTeam = false
    var t = got.team
    if (!t) { notices.notify("Linear did not return this team. Pick another one (t).", true); return }
    var sel = root.selectedIssue ? root.selectedIssue.id : ""
    root.team = { id: t.id, name: t.name, key: t.key, states: got.states,
      estimationType: t.issueEstimationType, estimationAllowZero: t.issueEstimationAllowZero,
      estimationExtended: t.issueEstimationExtended, autoArchivePeriod: t.autoArchivePeriod, triageEnabled: !!t.triageEnabled }
    root.labels = Linear.mergeLabels(got.labels, got.wsLabels)
    root.projects = got.projects.map(Linear.toProject)
    root.members = Linear.toMembers(got.members, root.viewer ? root.viewer.id : "")
    root.cycles = Linear.toCycles(got.cycles)
    root.labelFilter = root.labelFilter.filter(function(id) { return root.labelById(id) })
    var who = root.config.assignee
    if (who && who !== "me" && who !== "none" && !root.memberById(who)) root.setConfig({ assignee: "" })
    // An issue changed while this was loading is newer than what came back;
    // keep the board as it is and let the next refresh catch up.
    if (edits === root.editSeq) {
      root.issues = got.issues.map(Linear.toIssue)
      root.multi = root.multi.filter(function(id) { return root.onBoard(id) })
    }
    root.today = Dates.isoDate(new Date())
    root.syncedAt = Qt.formatTime(new Date(), "HH:mm")
    root.syncedAtMs = Date.now()
    if (sel) root.locateIssue(sel)
    root.clampSelection()
    root.saveCache()
    if (root.config.projectId && !root.projectById(root.config.projectId)) workspace.setProject("")
    if (lists.pendingEditId) {
      var pend = lists.pendingEditId
      lists.pendingEditId = ""
      root.openIssueAnywhere(pend, "")
    }
  }

  // Refresh in the background: every minute while the board is open and when
  // its window gets focus. Skipped while something is being edited or moved.
  function backgroundRefresh() {
    if (!root.apiKey || !panel.visible || root.dialog || bulk.dragging || pickers.confirmText
        || root.pending > 0 || root.loadingTeam || sync.outbox.length) return
    sync.refresh()
  }
  Timer {
    id: autoRefresh
    interval: 60000
    repeat: true
    running: panel.visible && root.mode === "board"
    onTriggered: sync.backgroundRefresh()
  }
}
