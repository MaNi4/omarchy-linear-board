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

  // Updates of one issue go out one at a time: a later one waits while an
  // earlier one is on its way, because one given up on after a timeout can
  // still reach Linear when the network is back. issue id → waiting sends.
  property var issueBusy: ({})

  function send(label, query, variables, ok, fail) {
    if (Linear.createdLookup(query)) variables = Edit.withClientId(variables)
    // While changes wait in the outbox, later ones wait behind them, so
    // Linear gets them in the order they were made.
    if (sync.outbox.length && root.apiKey) { sync.enqueue(label, query, variables, ok, 0); return }
    var issueId = query === Linear.M_ISSUE_UPDATE && variables && variables.id ? variables.id : ""
    if (issueId) {
      if (sync.issueBusy[issueId]) { sync.issueBusy[issueId].push([label, query, variables, ok, fail]); return }
      sync.issueBusy[issueId] = []
    }
    var released = false
    var next = function() {
      if (!issueId || released) return
      released = true
      var waiting = sync.issueBusy[issueId] || []
      delete sync.issueBusy[issueId]
      waiting.forEach(function(a) { sync.send(a[0], a[1], a[2], a[3], a[4]) })
    }
    root.gql(query, variables, function(data) {
      try { if (ok) ok(data) } finally { next() }
    }, function(msg, status) {
      // Offline (0) or Linear's rate limit (429): sent later, from the outbox.
      // Only a lost one (0) may still reach Linear later; a refused one (429) cannot.
      if ((status === 0 || status === 429) && root.apiKey) sync.enqueue(label, query, variables, ok, status, status === 0)
      else if (fail) fail(msg, status)
      else notices.notify(msg, true)
      next()
    })
  }

  // attempted: it was sent and its answer lost, so it may still land late.
  function enqueue(label, query, variables, ok, status, attempted) {
    var stale = attempted && query === Linear.M_ISSUE_UPDATE && variables && variables.input ? [variables.input] : []
    // Edits of one issue in a row (typing while offline) are one entry:
    // the later values win.
    var last = sync.outbox[sync.outbox.length - 1]
    if (Edit.outboxJoins(last, query, variables, sync.outboxFlushing, Linear.M_ISSUE_UPDATE)) {
      var input = Edit.mergeInput(last.variables.input, variables.input)
      var prevOk = last.ok
      var merged = { label: label, query: query, variables: { id: variables.id, input: input }, stale: (last.stale || []).concat(stale),
        ok: function(data) { if (prevOk) prevOk(data); if (ok) ok(data) } }
      sync.outbox = sync.outbox.slice(0, -1).concat([merged])
      sync.saveOutbox()
      return
    }
    sync.outbox = sync.outbox.concat([{ label: label, query: query, variables: variables, stale: stale, ok: ok || null }])
    sync.saveOutbox()
    notices.notify((status === 429 ? "Linear's rate limit: " + label + " will be sent in a while"
      : "Offline: " + label + " will be sent when Linear is reachable") + " (" + sync.outbox.length + " waiting)", true)
  }

  function saveOutbox() {
    if (!root.dirsReady) return
    privateFiles.write(outboxFile, JSON.stringify(sync.outbox.map(function(o) { return { label: o.label, query: o.query, variables: o.variables, stale: o.stale || [] } })) + "\n")
  }

  function flushOutbox() {
    if (sync.outboxFlushing || !sync.outbox.length || !root.apiKey) return
    sync.outboxFlushing = true
    var item = sync.outbox[0]
    var sent = function(data) {
      if (item.query === Linear.M_ISSUE_UPDATE && item.stale && item.stale.length) sync.checkLater(item)
      sync.outbox = sync.outbox.slice(1)
      sync.saveOutbox()
      sync.outboxFlushing = false
      if (item.ok) { try { item.ok(data) } catch (e) { console.warn("linear-board: updating the board after a waiting change failed: " + e) } }
      if (sync.outbox.length) sync.flushOutbox()
      else { notices.notify("Back online: everything was sent to Linear"); sync.loadTeam() }
    }
    var refused = function(msg) {
      sync.outbox = sync.outbox.slice(1)
      sync.saveOutbox()
      sync.outboxFlushing = false
      notices.notify("Linear refused a waiting change (" + item.label + "): " + msg, true)
      if (sync.outbox.length) sync.flushOutbox()
      else sync.loadTeam()
    }
    root.gql(item.query, item.variables, sent, function(msg, status) {
      if (status === 0 || status === 429) { sync.outboxFlushing = false; return }   // still offline or rate limited, try again later
      // A create refused because an earlier try (whose answer was lost) made
      // it already: that one is the result.
      var lookup = Linear.createdLookup(item.query)
      var id = lookup && item.variables && item.variables.input ? item.variables.input.id : ""
      if (!id) { refused(msg); return }
      root.gql(lookup.query, { id: id }, function(d) {
        if (!d[lookup.field]) { refused(msg); return }
        var data = {}
        data[lookup.payload] = { success: true }
        data[lookup.payload][lookup.field] = d[lookup.field]
        sent(data)
      }, function(msg2, status2) {
        if (status2 === 0 || status2 === 429) { sync.outboxFlushing = false; return }
        refused(msg)
      })
    })
  }

  // Sent changes whose older values may still land: checked in Linear a few
  // times. The system keeps retrying an unsent request after the network is
  // back, waiting up to 2 minutes between tries, so the last check is later.
  property var checks: []
  function checkLater(item) {
    var now = Date.now()
    ;[15000, 60000, 180000].forEach(function(after) {
      sync.checks = sync.checks.concat([{ id: item.variables.id, input: item.variables.input, stale: item.stale, at: now + after }])
    })
  }
  Timer {
    interval: 5000
    repeat: true
    running: sync.checks.length > 0
    onTriggered: {
      var now = Date.now()
      var due = sync.checks.filter(function(c) { return c.at <= now })
      if (!due.length) return
      sync.checks = sync.checks.filter(function(c) { return c.at > now })
      due.forEach(function(c) {
        root.gql(Linear.Q_ISSUE, { id: c.id }, function(d) {
          var fix = Edit.reassertInput(c.input, c.stale, d.issue)
          if (!fix) return
          console.warn("linear-board: an older change to " + (d.issue.identifier || c.id) + " reached Linear late; sending the newer values again")
          root.gql(Linear.M_ISSUE_UPDATE, { id: c.id, input: fix }, null, function() {})
        }, function() {})
      })
    }
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
          sync.outbox = list.map(function(o) { return { label: o.label, query: o.query, variables: o.variables, stale: o.stale || [], ok: null } })
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
          notices.notify("Linear has more than " + nodes.length + " here. Only those are shown.", true)
        }
        ok(nodes)
      }, fail)
    }
    step("")
  }

  // Load the team's columns, labels, projects, members, cycles and issues,
  // then apply them all at once so the board does not flicker.
  // Loading a team that failed because Linear could not be reached (no
  // network yet after waking, a dead connection) is tried again a few times.
  readonly property var teamRetryDelays: [2000, 5000, 10000]
  Timer {
    id: teamRetry
    property int attempt: 0
    property int forSeq: 0
    onTriggered: if (forSeq === root.teamSeq) sync.loadTeam(attempt)
  }

  function loadTeam(attempt) {
    attempt = attempt || 0
    var teamId = root.config.teamId
    if (!teamId) { root.team = null; root.issues = []; return }
    var seq = ++root.teamSeq
    var edits = root.editSeq
    root.loadingTeam = true
    var got = {}, left = 8, failed = false
    var fail = function(msg, status) {
      if (seq !== root.teamSeq || failed) return
      failed = true
      if (status === 0 && attempt < sync.teamRetryDelays.length) {
        teamRetry.attempt = attempt + 1
        teamRetry.forSeq = seq   // a newer load (another team) cancels the retry
        teamRetry.interval = sync.teamRetryDelays[attempt]
        teamRetry.restart()
        return
      }
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
    if (!t) { notices.notify("Linear didn't return this team. Pick another one (O then T).", true); return }
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
