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
import "../Issues.js" as Issues

// Team, project and filters, and the workflow / labels / projects settings.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `workspace`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: workspace
  visible: false

  // ---- team / project / filters -------------------------------------------------------------
  function setTeam(id) {
    if (id === root.config.teamId) return
    root.setConfig({ teamId: id, projectId: "" })
    root.multi = []
    root.extraIssues = []
    root.team = null
    root.issues = []
    root.labels = []
    root.projects = []
    root.members = []
    root.cycles = []
    root.labelFilter = []
    root.selCol = 0
    root.selIdx = 0
    sync.loadTeam()
  }

  function toggleLayout() {
    root.setConfig({ layout: (root.config.layout || "board") === "list" ? "board" : "list" })
    root.clampSelection()
    Qt.callLater(root.ensureVisible)
  }

  function setProject(id) {
    if (id === root.config.projectId) return
    root.setConfig({ projectId: id })
    root.issues = []
    sync.loadTeam()
  }

  function toggleMine() {
    workspace.setAssigneeFilter(root.config.assignee === "me" ? "" : "me")
  }

  function setAssigneeFilter(who) {
    root.setConfig({ assignee: who })
    root.clampSelection()
  }

  function setPriorityFilter(value) {
    root.priorityFilter = value
    root.clampSelection()
  }

  function setCycleFilter(value) {
    root.cycleFilter = value
    root.clampSelection()
  }

  function clearFilters(all) {
    root.labelFilter = []
    root.priorityFilter = -1
    root.cycleFilter = ""
    boardScreen.searchField.text = ""
    if (all) root.setConfig({ assignee: "" })
    root.clampSelection()
  }

  readonly property string assigneeFilterLabel: {
    var who = root.config.assignee
    if (!who) return "Anyone"
    if (who === "me") return "Mine"
    if (who === "none") return "Unassigned"
    var m = root.memberById(who)
    return m ? m.name : "Anyone"
  }

  function toggleLabelFilter(id) {
    var f = root.labelFilter.slice()
    var i = f.indexOf(id)
    if (i >= 0) f.splice(i, 1)
    else f.push(id)
    root.labelFilter = f
    root.clampSelection()
  }

  function toggleEdLabel(id) {
    var l = ed.labels.slice()
    var i = l.indexOf(id)
    if (i >= 0) l.splice(i, 1)
    else l.push(id)
    ed.labels = l
  }

  // ---- workflow / labels / projects (settings) -------------------------------------------------
  function afterSchemaChange(message) {
    if (message) notices.notify(message)
    sync.loadTeam()
  }

  function updateState(id, input) {
    root.gql(Linear.M_STATE_UPDATE, { id: id, input: input }, function() { workspace.afterSchemaChange("") })
  }

  function addState(name, type) {
    name = String(name || "").trim()
    if (!name || !root.team) return
    var colors = { triage: "#fc7840", backlog: "#bec2c8", unstarted: "#e2e2e2", started: "#f2c94c", completed: "#5e6ad2", canceled: "#95a2b3" }
    root.gql(Linear.M_STATE_CREATE, { input: { teamId: root.team.id, name: name, type: type, color: colors[type] || "#5e6ad2",
      position: Linear.positionForNewState(root.team.states, type) } }, function() { workspace.afterSchemaChange("Added column “" + name + "”") })
  }

  function moveState(id, delta) {
    var swap = Linear.positionSwap(root.team.states, id, delta)
    if (!swap) { notices.notify("Linear keeps columns grouped by kind (To do, In progress, Done…), so it can only move within its group."); return }
    var left = swap.length
    swap.forEach(function(s) {
      root.gql(Linear.M_STATE_UPDATE, { id: s.id, input: { position: s.position } }, function() { if (--left === 0) workspace.afterSchemaChange("") })
    })
  }

  function archiveState(state) {
    var n = root.countIn(state.id)
    pickers.ask(n > 0
      ? "Archive column “" + state.name + "”? Linear only allows this once its " + n + " issue(s) are moved elsewhere."
      : "Archive column “" + state.name + "”?", "Archive", function() {
      root.gql(Linear.M_STATE_ARCHIVE, { id: state.id }, function() { workspace.afterSchemaChange("Archived “" + state.name + "”") })
    })
  }

  function toggleStateHidden(id) {
    var hidden = {}
    for (var k in root.config.hidden) hidden[k] = root.config.hidden[k]
    hidden[root.team.id] = Issues.toggleHidden(root.team.states, root.hiddenStates, id)
    root.setConfig({ hidden: hidden })
    root.clampSelection()
  }

  function addLabel(name, then) {
    name = String(name || "").trim()
    if (!name || !root.team) return
    if (root.dialog === "issue" && ed.teamData) {
      var td = ed.teamData
      root.gql(Linear.M_LABEL_CREATE, { input: { teamId: td.id, name: name, color: Linear.COLORS[1] } }, function(data) {
        var l = data.issueLabelCreate.issueLabel
        if (ed.teamData !== td) return
        var next = {}
        for (var k in td) next[k] = td[k]
        next.labels = Linear.mergeLabels(td.labels.concat([l]), [])
        ed.teamData = next
        if (then) then(l)
      })
      return
    }
    var used = root.labels.map(function(l) { return l.color })
    var free = Linear.COLORS.filter(function(c) { return used.indexOf(c) < 0 })
    root.gql(Linear.M_LABEL_CREATE, { input: { teamId: root.team.id, name: name, color: free[0] || Linear.COLORS[1] } }, function(data) {
      var l = data.issueLabelCreate.issueLabel
      root.labels = Linear.mergeLabels(root.labels.concat([l]), [])
      if (then) then(l)
      root.saveCache()
    })
  }

  function updateLabel(id, input) {
    root.gql(Linear.M_LABEL_UPDATE, { id: id, input: input }, function(data) {
      var l = data.issueLabelUpdate.issueLabel
      root.labels = Linear.mergeLabels(root.labels.map(function(x) { return x.id === l.id ? l : x }), [])
      root.saveCache()
    })
  }

  function deleteLabel(label) {
    pickers.ask("Delete label “" + label.name + "”? It is removed from every issue in Linear.", "Delete", function() {
      root.gql(Linear.M_LABEL_DELETE, { id: label.id }, function() { workspace.afterSchemaChange("Deleted label “" + label.name + "”") })
    })
  }

  function addProject(name) {
    name = String(name || "").trim()
    if (!name || !root.team) return
    root.gql(Linear.M_PROJECT_CREATE, { input: { name: name, teamIds: [root.team.id] } }, function(data) {
      var p = Linear.toProject(data.projectCreate.project)
      root.projects = root.projects.concat([p])
      notices.notify("Created project “" + p.name + "”")
      workspace.setProject(p.id)
    })
  }

  function renameTeam(name) {
    name = String(name || "").trim()
    if (!name || !root.team || name === root.team.name) return
    root.gql(Linear.M_TEAM_UPDATE, { id: root.team.id, input: { name: name } }, function(data) {
      var t = data.teamUpdate.team
      root.teams = root.teams.map(function(x) { return x.id === t.id ? t : x })
      var nt = {}
      for (var k in root.team) nt[k] = root.team[k]
      nt.name = t.name
      nt.key = t.key
      root.team = nt
      notices.notify("Team renamed to “" + t.name + "”")
      root.saveCache()
    })
  }

  function renameProject(id, name) {
    name = String(name || "").trim()
    var p = root.projectById(id)
    if (!name || !p || p.name === name) return
    projectOps.saveProject(id, { name: name })
  }
}
