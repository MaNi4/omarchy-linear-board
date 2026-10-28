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
import "../Markdown.js" as Markdown

// The project overview: status, target date, milestones and project updates.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `projectOps`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: projectOps
  visible: false

  // ---- project overview: status, health, target date, milestones, updates ----
  property string projectViewId: ""
  property var projectDetail: null
  property var projectUpdates: []
  property var projectStatuses: []
  property bool projectLoading: false
  property string updateHealth: "onTrack"
  property string projectEditUpdateId: ""   // your update being edited in the field
  function openProject(id) {
    if (!id) id = root.projects.length ? root.projects[0].id : ""
    if (!id) { notices.notify("This team has no active projects. Create one in Settings → Projects."); return }
    projectOps.projectViewId = id
    projectOps.projectDetail = root.projectById(id)
    projectOps.projectUpdates = []
    projectOps.projectEditUpdateId = ""
    projectDialog.projUpdateField.text = ""
    root.dialog = "project"
    keyScope.forceActiveFocus()
    projectOps.reloadProject()
    if (!projectOps.projectStatuses.length)
      root.gql(Linear.Q_PROJECT_STATUSES, {}, function(d) {
        projectOps.projectStatuses = d.projectStatuses.nodes.slice().sort(function(a, b) { return a.position - b.position })
      }, function() {})
  }
  function reloadProject() {
    var id = projectOps.projectViewId
    projectOps.projectLoading = true
    root.gql(Linear.Q_PROJECT_UPDATES, { id: id }, function(d) {
      if (projectOps.projectViewId !== id) return
      projectOps.projectLoading = false
      projectOps.applyProject(Linear.toProject(d.project))
      projectOps.projectUpdates = d.project.projectUpdates.nodes.map(Linear.toProjectUpdate)
      var last = projectOps.projectUpdates[0]
      projectOps.updateHealth = (last && last.health) || projectOps.projectDetail.health || "onTrack"
    }, function(msg) { projectOps.projectLoading = false; notices.notify(msg, true) })
  }
  function applyProject(p) {
    if (!p) return
    root.projects = root.projects.map(function(x) { return x.id === p.id ? p : x })
    if (projectOps.projectViewId === p.id) projectOps.projectDetail = p
    root.saveCache()
  }
  function saveProject(id, input) {
    root.gql(Linear.M_PROJECT_SAVE, { id: id, input: input }, function(d) { projectOps.applyProject(Linear.toProject(d.projectUpdate.project)) },
      function(msg) { notices.notify("Could not change the project: " + msg, true) })
  }
  function setProjectTarget(text) {
    var d = Dates.parseDate(text)
    if (d === null) { notices.notify("Date should look like 2026-12-31 or 31.12.2026", true); return }
    projectOps.saveProject(projectOps.projectViewId, { targetDate: d || null })
  }
  function addMilestone(name, date) {
    name = String(name || "").trim()
    if (!name) return false
    var d = Dates.parseDate(date)
    if (d === null) { notices.notify("Date should look like 2026-12-31 or 31.12.2026", true); return false }
    var input = { projectId: projectOps.projectViewId, name: name }
    if (d) input.targetDate = d
    root.gql(Linear.M_MILESTONE_CREATE, { input: input }, function() { notices.notify("Milestone “" + name + "” added"); projectOps.reloadProject() },
      function(msg) { notices.notify("Could not add the milestone: " + msg, true) })
    return true
  }
  function updateMilestone(m, name, date) {
    name = String(name || "").trim()
    var d = Dates.parseDate(date)
    if (!name || d === null) { notices.notify(!name ? "A milestone needs a name." : "Date should look like 2026-12-31", true); return }
    if (name === m.name && d === (m.targetDate || "")) return
    root.gql(Linear.M_MILESTONE_UPDATE, { id: m.id, input: { name: name, targetDate: d || null } }, function() { projectOps.reloadProject() },
      function(msg) { notices.notify("Could not change the milestone: " + msg, true) })
  }
  function deleteMilestone(m) {
    pickers.ask("Delete the milestone “" + m.name + "”? Its issues stay in the project.", "Delete", function() {
      root.gql(Linear.M_MILESTONE_DELETE, { id: m.id }, function() { projectOps.reloadProject() },
        function(msg) { notices.notify("Could not delete: " + msg, true) })
    })
  }
  // A click on a checklist box in your own update: saved at once.
  function toggleUpdateTask(u, line) {
    var body = Markdown.toggleTask(u.body, line)
    if (body === u.body) return
    var swap = function(b) {
      projectOps.projectUpdates = projectOps.projectUpdates.map(function(x) {
        if (x.id !== u.id) return x
        var n = {}
        for (var k in x) n[k] = x[k]
        n.body = b
        return n
      })
    }
    swap(body)
    var input = { body: body }
    if (u.health) input.health = u.health
    root.gql(Linear.M_PROJECT_UPDATE_EDIT, { id: u.id, input: input }, function(d) {
      var nu = Linear.toProjectUpdate(d.projectUpdateUpdate.projectUpdate)
      projectOps.projectUpdates = projectOps.projectUpdates.map(function(x) { return x.id === u.id ? nu : x })
    }, function(msg) { swap(u.body); notices.notify("Could not save the checklist: " + msg, true) })
  }

  // Your own updates: edit puts the text into the field, delete archives it
  // (what Linear's Delete does).
  function editProjectUpdate(u) {
    projectOps.projectEditUpdateId = u.id
    projectDialog.projUpdateField.text = u.body
    if (u.health) projectOps.updateHealth = u.health
    projectDialog.projUpdateField.forceActiveFocus()
  }
  function cancelProjectUpdateEdit() {
    projectOps.projectEditUpdateId = ""
    projectDialog.projUpdateField.text = ""
  }
  function deleteProjectUpdate(u) {
    pickers.ask("Delete this project update? Linear archives it; it can be restored there.", "Delete", function() {
      var before = projectOps.projectUpdates
      projectOps.projectUpdates = projectOps.projectUpdates.filter(function(x) { return x.id !== u.id })
      if (projectOps.projectEditUpdateId === u.id) projectOps.cancelProjectUpdateEdit()
      root.gql(Linear.M_PROJECT_UPDATE_ARCHIVE, { id: u.id }, function() { notices.notify("Update deleted"); projectOps.reloadProject() },
        function(msg) { projectOps.projectUpdates = before; notices.notify("Could not delete the update: " + msg, true) })
    })
  }
  function postProjectUpdate(body) {
    body = String(body || "").trim()
    if (!body) { notices.notify("Write what changed first.", true); return false }
    if (projectOps.projectEditUpdateId) {
      var uid = projectOps.projectEditUpdateId
      root.gql(Linear.M_PROJECT_UPDATE_EDIT, { id: uid, input: { body: body, health: projectOps.updateHealth } }, function(d) {
        var nu = Linear.toProjectUpdate(d.projectUpdateUpdate.projectUpdate)
        projectOps.projectUpdates = projectOps.projectUpdates.map(function(x) { return x.id === uid ? nu : x })
        projectOps.projectEditUpdateId = ""
        notices.notify("Update saved", false, root.icon.check)
        projectOps.reloadProject()
      }, function(msg) { notices.notify("Could not save the update: " + msg, true) })
      return true
    }
    root.gql(Linear.M_PROJECT_UPDATE_CREATE, { input: { projectId: projectOps.projectViewId, body: body, health: projectOps.updateHealth } }, function(d) {
      projectOps.projectUpdates = [Linear.toProjectUpdate(d.projectUpdateCreate.projectUpdate)].concat(projectOps.projectUpdates)
      notices.notify("Project update posted", false, root.icon.check)
      projectOps.reloadProject()
    }, function(msg) { notices.notify("Could not post the update: " + msg, true) })
    return true
  }
}
