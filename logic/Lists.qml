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
import "../Issues.js" as Issues

// Issue lists in the search window: search, my issues, cycles (and editing them), triage and the trash.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `lists`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: lists

  // Search over all of the team's issues in Linear (old done ones too).
  property var searchResults: []
  property bool searchLoading: false
  property string searchTerm: ""
  property int searchCursor: 0
  visible: false

  // ---- issue lists in the search window: my issues, a cycle, triage ----
  // The search window lists issues for these too (listMode); each has its
  // own title, keys and footer.
  property string listMode: "search"   // search | mine | cycle | triage | archived | trash
  // Archived and trash share one window (Tab switches) and the picking.
  readonly property bool isBin: lists.listMode === "archived" || lists.listMode === "trash"
  property var allCycles: []
  property string cycleViewId: ""
  readonly property var cycleView: {
    for (var i = 0; i < lists.allCycles.length; i++) if (lists.allCycles[i].id === lists.cycleViewId) return lists.allCycles[i]
    return null
  }
  readonly property var listStats: Issues.cycleStats(lists.searchResults)
  readonly property var triageIssues: root.issues.filter(function(i) { return i.stateType === "triage" })
  readonly property bool triageOn: !!(root.team && (root.team.triageEnabled || lists.triageIssues.length))

  function openList(mode) {
    lists.listMode = mode
    lists.binPicked = []
    lists.binAll = []
    lists.binQuery = ""
    if (issueListDialog.binField.text) issueListDialog.binField.text = ""
    lists.searchResults = []
    lists.searchCursor = 0
    lists.searchTerm = ""
    root.dialog = "search"
    keyScope.forceActiveFocus()
  }

  function byTeamThenPriority(a, b) {
    if (a.teamName !== b.teamName) return a.teamName < b.teamName ? -1 : 1
    var pa = Issues.priorityRank(a.priority), pb = Issues.priorityRank(b.priority)
    if (pa !== pb) return pa - pb
    return Linear.typeRank(a.stateType) - Linear.typeRank(b.stateType)
  }

  // Open issues assigned to you in every team.
  function openMyIssues() {
    lists.openList("mine")
    lists.searchLoading = true
    sync.gqlAll(Linear.Q_MY_ISSUES, {}, function(d) { return d.issues }, function(nodes) {
      if (lists.listMode !== "mine") return
      lists.searchLoading = false
      lists.searchResults = nodes.map(Linear.toIssue).sort(lists.byTeamThenPriority)
    }, function(msg) { lists.searchLoading = false; notices.notify(msg, true) })
  }

  // The team's cycles: the current one first (or the next one), H / L for
  // others. which = "next": the upcoming one (G then W, like Linear).
  function openCycles(which) {
    if (!root.team) return
    lists.openList("cycle")
    lists.searchLoading = true
    var teamId = root.team.id
    sync.gqlAll(Linear.Q_ALL_CYCLES, { teamId: teamId }, function(d) { return d.team ? d.team.cycles : null }, function(nodes) {
      if (lists.listMode !== "cycle" || !root.team || root.team.id !== teamId) return
      lists.allCycles = nodes.map(Linear.toCycle).sort(function(a, b) { return a.startsAt < b.startsAt ? -1 : 1 })
      if (!lists.allCycles.length) { lists.searchLoading = false; lists.cycleViewId = ""; return }
      var now = new Date().toISOString()
      var next = lists.allCycles.filter(function(c) { return c.isNext })[0] || lists.allCycles.filter(function(c) { return c.startsAt > now })[0]
      var pick = (which === "next" && next) || lists.allCycles.filter(function(c) { return c.isActive })[0] || next
        || lists.allCycles[lists.allCycles.length - 1]
      lists.showCycle(pick.id)
    }, function(msg) { lists.searchLoading = false; notices.notify(msg, true) })
  }

  function showCycle(id) {
    lists.cycleViewId = id
    lists.cycleEditing = false
    lists.searchResults = []
    lists.searchCursor = 0
    lists.searchLoading = true
    sync.gqlAll(Linear.Q_CYCLE_ISSUES, { id: id }, function(d) { return d.cycle ? d.cycle.issues : null }, function(nodes) {
      if (lists.listMode !== "cycle" || lists.cycleViewId !== id) return
      lists.searchLoading = false
      lists.searchResults = nodes.map(Linear.toIssue).sort(function(a, b) {
        return Linear.typeRank(a.stateType) - Linear.typeRank(b.stateType) || Issues.priorityRank(a.priority) - Issues.priorityRank(b.priority)
      })
    }, function(msg) { lists.searchLoading = false; notices.notify(msg, true) })
  }

  function stepCycle(delta) {
    var i = lists.allCycles.findIndex(function(c) { return c.id === lists.cycleViewId })
    var next = lists.allCycles[i + delta]
    if (next) lists.showCycle(next.id)
  }

  // ---- editing cycles ----
  // Name, description and dates of a cycle; the next one can start today;
  // any can be archived (its issues leave the cycle). New cycles come from
  // the team's cycle settings (Settings → Team), as Linear makes them.
  property bool cycleEditing: false

  function replaceCycle(c) {
    lists.allCycles = lists.allCycles.map(function(x) { return x.id === c.id ? c : x })
    root.cycles = root.cycles.map(function(x) {
      if (x.id !== c.id) return x
      var n = {}
      for (var k in x) n[k] = x[k]
      n.name = c.name; n.startsAt = c.startsAt; n.endsAt = c.endsAt; n.isActive = c.isActive
      return n
    })
  }

  function saveCycle(name, startText, endText, description) {
    var c = lists.cycleView
    if (!c) return
    var r = Edit.cycleInput(c, name, Dates.parseDate(startText) || String(startText || "").trim(), Dates.parseDate(endText) || String(endText || "").trim(), description)
    if (r.error) { notices.notify(r.error, true); return }
    if (!Object.keys(r.input).length) { lists.cycleEditing = false; return }
    root.gql(Linear.M_CYCLE_UPDATE, { id: c.id, input: r.input }, function(d) {
      lists.replaceCycle(Linear.toCycle(d.cycleUpdate.cycle))
      lists.cycleEditing = false
      notices.notify("Cycle saved", false, root.icon.check)
      if (r.input.startsAt || r.input.endsAt) lists.openCyclesAt(c.id)
    }, function(msg) { notices.notify("Could not save the cycle: " + msg, true) })
  }

  // Reload the list (dates move cycles around), staying on this cycle.
  function openCyclesAt(id) {
    if (!root.team) return
    var teamId = root.team.id
    sync.gqlAll(Linear.Q_ALL_CYCLES, { teamId: teamId }, function(d) { return d.team ? d.team.cycles : null }, function(nodes) {
      if (lists.listMode !== "cycle" || !root.team || root.team.id !== teamId) return
      lists.allCycles = nodes.map(Linear.toCycle).sort(function(a, b) { return a.startsAt < b.startsAt ? -1 : 1 })
      if (lists.allCycles.some(function(c) { return c.id === id })) lists.showCycle(id)
      else if (lists.allCycles.length) lists.showCycle(lists.allCycles[lists.allCycles.length - 1].id)
      else lists.cycleViewId = ""
    }, function(msg) { notices.notify(msg, true) })
  }

  function startCycleToday() {
    var c = lists.cycleView
    if (!c || !c.isNext) return
    pickers.ask("Start " + (c.name || "Cycle " + c.number) + " today? The current cycle ends now, as Linear does at a cycle's end.", "Start", function() {
      root.gql(Linear.M_CYCLE_START_TODAY, { id: c.id }, function(d) {
        notices.notify((c.name || "Cycle " + c.number) + " started", false, root.icon.check)
        lists.openCyclesAt(c.id)
        sync.loadTeam()
      }, function(msg) { notices.notify("Could not start the cycle: " + msg, true) })
    })
  }

  function archiveCycle() {
    var c = lists.cycleView
    if (!c) return
    var label = c.name || "Cycle " + c.number
    pickers.ask("Archive " + label + "? Its " + lists.searchResults.length + " issues leave the cycle (they stay in the team). Linear may make a new cycle in its place from the team's settings.", "Archive", function() {
      root.gql(Linear.M_CYCLE_ARCHIVE, { id: c.id }, function() {
        notices.notify(label + " archived", false, root.icon.check)
        if (root.cycleFilter === c.id) workspace.setCycleFilter("")
        lists.openCyclesAt("")
        sync.loadTeam()
      }, function(msg) { notices.notify("Could not archive the cycle: " + msg, true) })
    })
  }

  // The team's cycle settings, for Settings → Team.
  property var cycleSettings: null
  function loadCycleSettings() {
    if (!root.team) return
    var teamId = root.team.id
    root.gql(Linear.Q_TEAM_CYCLES, { teamId: teamId }, function(d) {
      if (root.team && root.team.id === teamId) lists.cycleSettings = d.team
    }, function(msg) { notices.notify("Cycle settings: " + msg, true) })
  }
  function saveCycleSettings(patch) {
    if (!root.team || !lists.cycleSettings) return
    var teamId = root.team.id
    root.gql(Linear.M_TEAM_CYCLES, { id: teamId, input: patch }, function(d) {
      lists.cycleSettings = d.teamUpdate.team
      notices.notify(patch.cyclesEnabled === false ? "Cycles turned off" : (patch.cyclesEnabled ? "Cycles turned on: Linear makes them in a moment" : "Cycle settings saved"), false, root.icon.check)
      sync.loadTeam()
    }, function(msg) { notices.notify("Could not change cycle settings (team admins only?): " + msg, true) })
  }

  Connections {
    target: root
    function onSettingsTabChanged() { if (root.dialog === "settings" && root.settingsTab === "team") { lists.loadCycleSettings(); lists.loadUsage() } }
    function onDialogChanged() { if (root.dialog === "settings" && root.settingsTab === "team") { lists.loadCycleSettings(); lists.loadUsage() } }
  }

  // ---- archived and trash ----
  // Archived: kept by Linear for good, out of boards and out of the Free
  // plan's count; restore them or delete them (to the trash).
  function openArchived() {
    if (!root.team) return
    lists.openList("archived")
    lists.searchLoading = true
    lists.loadUsage()
    var teamId = root.team.id
    sync.gqlAll(Linear.Q_ARCHIVED, { filter: Linear.archivedFilter(teamId) }, function(d) { return d.issues }, function(nodes) {
      if (lists.listMode !== "archived") return
      lists.searchLoading = false
      lists.setBin(Linear.toArchived(nodes))
    }, function(msg) { lists.searchLoading = false; notices.notify(msg, true) })
  }
  // The whole list of the window; what shows (lists.searchResults) is what
  // matches the filter typed in it (/ goes there).
  property var binAll: []
  property string binQuery: ""
  function setBin(list) { lists.binAll = list; lists.applyBinQuery() }
  function applyBinQuery() {
    lists.searchResults = lists.binAll.filter(function(i) { return Issues.binMatches(i, lists.binQuery) })
    lists.searchCursor = Math.max(0, Math.min(lists.searchCursor, lists.searchResults.length - 1))
  }
  function setBinQuery(text) {
    lists.binQuery = text
    lists.binPicked = []
    lists.searchCursor = 0
    lists.applyBinQuery()
  }

  function switchBin() {
    // The filter stays when switching.
    var q = lists.binQuery
    if (lists.listMode === "archived") lists.openTrash(); else lists.openArchived()
    lists.binQuery = q
    issueListDialog.binField.text = q
  }

  // How many issues count toward the Free plan's 250: all not archived, in every team.
  property int usageCount: -1
  property bool usageLoading: false
  function loadUsage() {
    if (lists.usageLoading || !root.apiKey) return
    lists.usageLoading = true
    sync.gqlAll(Linear.Q_ACTIVE_IDS, {}, function(d) { return d.issues }, function(nodes) {
      lists.usageLoading = false
      lists.usageCount = nodes.length
    }, function() { lists.usageLoading = false })
  }
  readonly property string usageText: lists.usageCount < 0 ? ""
    : lists.usageCount + " of " + Linear.FREE_PLAN_ISSUES + " issues count toward the Free plan (all teams; archived and deleted ones do not)"

  // Archived → trash (Linear's delete; it can still be restored for 30 days).
  function trashArchived(issue, picked) {
    var list = picked ? lists.binTargets(issue) : (issue ? [issue] : [])
    if (!list.length) return
    var what = list.length === 1 ? list[0].identifier + " “" + list[0].title + "”" : list.length + " archived issues"
    pickers.ask("Delete " + what + "? They go to Linear's trash for 30 days (G then X, Tab), then are gone.", "Delete", function() {
      lists.runOnBin(list, Linear.deleteDocument, function(ok, failed) {
        lists.dropFromBin(ok)
        if (ok.length) notices.notify((ok.length === 1 ? "1 issue" : ok.length + " issues") + " moved to the trash")
        if (failed) { notices.notify("Could not delete " + (list.length - ok.length) + " of them: " + failed, true); lists.openArchived() }
      })
    })
  }

  // ---- trash: deleted issues Linear still keeps (30 days) ----
  function openTrash() {
    if (!root.team) return
    lists.openList("trash")
    lists.loadUsage()
    lists.searchLoading = true
    var teamId = root.team.id
    sync.gqlAll(Linear.Q_TRASH, { filter: Linear.trashFilter(teamId, new Date()) }, function(d) { return d.issues }, function(nodes) {
      if (lists.listMode !== "trash") return
      lists.searchLoading = false
      lists.setBin(Linear.toTrash(nodes))
    }, function(msg) { lists.searchLoading = false; notices.notify(msg, true) })
  }

  // Several at once: X (or Ctrl+click) picks, Ctrl+A picks all, Esc clears;
  // Restore and Delete then act on the picked ones, else on the one under the cursor.
  property var binPicked: []
  function isBinPicked(id) { return lists.binPicked.indexOf(id) >= 0 }
  function toggleBinPick(issue) {
    if (!issue) return
    var p = lists.binPicked.slice(), i = p.indexOf(issue.id)
    if (i >= 0) p.splice(i, 1)
    else p.push(issue.id)
    lists.binPicked = p
  }
  function pickAllBin() {
    var all = lists.searchResults.map(function(i) { return i.id })
    lists.binPicked = lists.binPicked.length === all.length ? [] : all
  }
  function binTargets(fallback) {
    if (lists.binPicked.length) return lists.searchResults.filter(function(i) { return lists.isBinPicked(i.id) })
    return fallback ? [fallback] : []
  }
  function trashLabel(list) { return list.length === 1 ? list[0].identifier : list.length + " issues" }

  function dropFromBin(ids) {
    lists.binAll = lists.binAll.filter(function(i) { return ids.indexOf(i.id) < 0 })
    lists.searchResults = lists.searchResults.filter(function(i) { return ids.indexOf(i.id) < 0 })
    lists.binPicked = lists.binPicked.filter(function(id) { return ids.indexOf(id) < 0 })
    lists.searchCursor = Math.max(0, Math.min(lists.searchCursor, lists.searchResults.length - 1))
  }

  // Sends `doc` for the issues in chunks; done() with the ids that went through.
  function runOnBin(list, doc, done, failWord) {
    var ids = list.map(function(i) { return i.id }), ok = [], left = 0, failed = ""
    for (var c = 0; c < ids.length; c += Linear.BATCH_SIZE) {
      var chunk = ids.slice(c, c + Linear.BATCH_SIZE)
      left++
      ;(function(chunk) {
        root.gql(doc(chunk.length), Linear.idVariables(chunk), function() {
          ok = ok.concat(chunk)
          if (--left === 0) done(ok, failed)
        }, function(msg) {
          failed = msg
          if (--left === 0) done(ok, failed)
        })
      })(chunk)
    }
  }

  // The row's own button passes its issue; keys and the header act on the picked ones.
  function restoreTrashed(issue, picked) {
    var list = picked ? lists.binTargets(issue) : (issue ? [issue] : [])
    if (!list.length) return
    lists.runOnBin(list, Linear.unarchiveDocument, function(ok, failed) {
      lists.dropFromBin(ok)
      if (ok.length) notices.notify((ok.length === 1 ? list.filter(function(i) { return i.id === ok[0] })[0].identifier : ok.length + " issues") + " restored", false, root.icon.check)
      if (failed) { notices.notify("Could not restore " + (list.length - ok.length) + " of them: " + failed, true); if (lists.listMode === "archived") lists.openArchived(); else lists.openTrash() }
      if (ok.length) { sync.loadTeam(); lists.usageCount = -1; lists.loadUsage() }
    })
  }

  function deleteForever(issue, picked) {
    var list = picked ? lists.binTargets(issue) : (issue ? [issue] : [])
    if (!list.length) return
    var what = list.length === 1 ? list[0].identifier + " “" + list[0].title + "”" : list.length + " issues"
    pickers.ask("Delete " + what + " for good? They cannot be restored after this (Linear allows it to workspace admins only).", "Delete for good", function() {
      lists.runOnBin(list, Linear.deleteForeverDocument, function(ok, failed) {
        lists.dropFromBin(ok)
        if (ok.length) notices.notify((ok.length === 1 ? "1 issue" : ok.length + " issues") + " deleted for good")
        if (failed) { notices.notify("Could not delete " + (list.length - ok.length) + " of them for good: " + failed, true); lists.openTrash() }
      })
    })
  }

  function shortDay(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    return Dates.MONTHS[d.getMonth()] + " " + d.getDate()
  }

  // Triage (when the team has it on): new issues waiting to be accepted.
  function openTriage() {
    lists.openList("triage")
    lists.searchResults = lists.triageIssues.slice()
  }
  // Accept: to the team's first backlog (or todo) column, like Linear.
  function triageAccept(issue) {
    if (!issue) return
    var st = root.states.filter(function(x) { return x.type === "backlog" })[0] || root.states.filter(function(x) { return x.type === "unstarted" })[0]
    if (!st) return
    issueOps.moveIssue(issue.id, st.id, 0)
    lists.afterTriage(issue)
  }
  function triageDecline(issue) {
    if (!issue) return
    var st = root.states.filter(function(x) { return x.type === "canceled" })[0]
    if (!st) return
    issueOps.moveIssue(issue.id, st.id, 0)
    lists.afterTriage(issue)
  }
  function afterTriage(issue) {
    if (root.dialog === "issue") pickers.closeDialog()
    if (lists.listMode === "triage") {
      lists.searchResults = lists.searchResults.filter(function(i) { return i.id !== issue.id })
      lists.searchCursor = Math.max(0, Math.min(lists.searchCursor, lists.searchResults.length - 1))
    }
  }

  function runSearch(term) {
    lists.listMode = "search"
    lists.searchTerm = term
    lists.searchResults = []
    lists.searchCursor = 0
    lists.searchLoading = true
    root.dialog = "search"
    keyScope.forceActiveFocus()
    // Every team: the results say which team each issue is in.
    root.gql(Linear.Q_SEARCH, { term: term }, function(d) {
      if (lists.searchTerm !== term) return
      lists.searchLoading = false
      lists.searchResults = d.searchIssues.nodes.map(Linear.toIssue)
    }, function(msg) { lists.searchLoading = false; notices.notify("Search failed: " + msg, true) })
  }

  // A row of the archived or trash list: Linear's web app shows it (a
  // deleted issue cannot be edited here). Only from that window.
  function openBinResult(issue) {
    if (issue) editorOps.openInLinear(issue.url)
  }

  function openSearchResult(issue) {
    if (!issue) return
    pickers.closeDialog()
    if (root.team && issue.teamId && issue.teamId !== root.team.id) { lists.switchTeamAndEdit(issue.teamId, issue.id); return }
    if (!root.onBoard(issue.id)) root.extraIssues = Issues.upsertIssue(root.extraIssues, issue)
    issueOps.editIssue(issue.id)
  }

  // The editor works with the board's team, so an issue of another team
  // switches the board to that team first and opens once it has loaded.
  property string pendingEditId: ""
  function switchTeamAndEdit(teamId, issueId) {
    lists.pendingEditId = issueId
    workspace.setTeam(teamId)
    var t = root.teams.filter(function(x) { return x.id === teamId })[0]
    notices.notify("Switched the board to " + (t ? t.name : "the issue's team"))
  }

  function openTimeReport() {
    timeTracker.nowMs = Date.now()
    timeTracker.reportEditId = ""
    root.dialog = "time"
    keyScope.forceActiveFocus()
  }
}
