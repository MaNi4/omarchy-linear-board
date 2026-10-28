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
import "../Issues.js" as Issues

// Dialogs, confirmations and the pickers.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `pickers`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: pickers

  // The open picker (a small list under a button) and where it shows.
  property string kind: ""            // team | project | assignee | priority | view | filter | bulk*
  property int cursor: 0
  property real popupX: 0
  property real popupBottom: -1       // >= 0: open upwards, ending here (the bulk bar)

  // The confirmation box (ui/ConfirmBox.qml): question, button, what it runs.
  property string confirmText: ""
  property string confirmLabel: "Delete"
  property var confirmAction: null
  visible: false

  // ---- dialogs -----------------------------------------------------------------------------
  function ask(text, label, action) {
    pickers.confirmText = text
    pickers.confirmLabel = label
    pickers.confirmAction = action
  }

  function runConfirm() {
    var a = pickers.confirmAction
    pickers.confirmText = ""
    pickers.confirmAction = null
    if (a) a()
    pickers.refocus()
  }

  function refocus() {
    if (root.dialog === "issue" && !ed.issueId) editor.titleField.forceActiveFocus()
    else keyScope.forceActiveFocus()
  }

  function closeDialog() {
    if (root.dialog === "issue") editorOps.flush()
    root.dialog = ""
    pickers.kind = ""
    keyScope.forceActiveFocus()
  }

  function openSettings(tab) {
    root.settingsTab = tab || "columns"
    if (root.settingsTab === "keys") hotkeys.refreshBinds()
    root.dialog = "settings"
    keyScope.forceActiveFocus()
  }

  readonly property var pickerItems: {
    if (pickers.kind === "team")
      return root.teams.map(function(t) { return { id: t.id, label: t.name, hint: t.key, selected: t.id === root.config.teamId } })
    if (pickers.kind === "project")
      return [{ id: "", label: "All issues", hint: "", selected: !root.config.projectId }].concat(
        root.projects.map(function(p) { return { id: p.id, label: p.name, hint: "", color: p.color, selected: p.id === root.config.projectId } }),
        [{ id: "__new", label: "New project…", hint: "", selected: false }])
    if (pickers.kind === "assignee") {
      var who = root.config.assignee || ""
      var me = root.viewer ? root.viewer.id : ""
      return [
        { id: "", label: "Anyone", hint: "", selected: who === "" },
        { id: "me", label: "Me", hint: root.viewer ? (root.viewer.displayName || root.viewer.name) : "", selected: who === "me" },
        { id: "none", label: "Unassigned", hint: "", selected: who === "none" }
      ].concat(root.members.filter(function(m) { return m.id !== me }).map(function(m) {
        return { id: m.id, label: m.name, hint: m.fullName !== m.name ? m.fullName : "", selected: who === m.id }
      }))
    }
    if (pickers.kind === "view") {
      var sortNow = root.config.sort || "manual", groupNow = root.config.group || "none"
      var lay = root.config.layout || "board"
      return [{ id: "layout:board", label: "Layout: Board", hint: "Ctrl+B", selected: lay === "board" },
        { id: "layout:list", label: "Layout: List", hint: "Ctrl+B", selected: lay === "list" }].concat(
        Issues.SORTS.map(function(o) { return { id: "sort:" + o.id, label: "Sort: " + o.label, hint: "", selected: o.id === sortNow } }))
        .concat(Issues.GROUPS.map(function(o) { return { id: "group:" + o.id, label: "Group: " + o.label, hint: "", selected: o.id === groupNow } }))
        .concat(Linear.DONE_WINDOWS.map(function(o) { return { id: "doneWindow:" + o.id, label: "Completed: " + o.label, hint: "",
          selected: o.id === Linear.doneWindow(root.config.doneWindow).id } }))
    }
    if (pickers.kind === "bulkState")
      return root.states.map(function(st) { return { id: st.id, label: st.name, hint: "", color: st.color, selected: false } })
    if (pickers.kind === "bulkAssignee")
      return [{ id: "", label: "Unassigned", hint: "", selected: false }].concat(root.members.map(function(m) {
        return { id: m.id, label: root.viewer && m.id === root.viewer.id ? "Me" : m.name, hint: "", selected: false }
      }))
    if (pickers.kind === "bulkPriority")
      return Linear.PRIORITIES.map(function(p) { return { id: String(p.value), label: p.label, hint: p.short, selected: false } })
    if (pickers.kind === "bulkLabel") {
      var tg = bulk.actionIds().map(function(id) { return root.issueById(id) }).filter(function(i) { return i })
      return root.labels.map(function(l) {
        var all = tg.length > 0 && tg.every(function(i) { return i.labelIds.indexOf(l.id) >= 0 })
        return { id: l.id, label: l.name, hint: all ? "remove" : "", color: l.color, selected: all }
      })
    }
    if (pickers.kind === "bulkRemind")
      return Dates.REMINDER_OPTIONS.map(function(o) { return { id: o.id, label: o.label, hint: "", selected: false } })
    if (pickers.kind === "bulkMilestone") {
      var pids = {}
      bulk.actionIds().forEach(function(id) { var i = root.issueById(id); if (i) pids[i.projectId || ""] = true })
      var keys = Object.keys(pids)
      var proj = keys.length === 1 ? root.projectById(keys[0]) : null
      return [{ id: "", label: "No milestone", hint: "", selected: false }].concat((proj ? proj.milestones || [] : []).map(function(m) {
        return { id: m.id, label: m.name, hint: m.targetDate, selected: false }
      }))
    }
    if (pickers.kind === "bulkCycle")
      return [{ id: "", label: "No cycle", hint: "", selected: false }].concat(root.cycles.map(function(c) { return { id: c.id, label: Issues.cycleLabel(c), hint: "", selected: false } }))
    if (pickers.kind === "bulkEstimate")
      return [{ id: "", label: "No estimate", hint: "", selected: false }].concat(root.estimateOptions.map(function(o) { return { id: String(o.value), label: o.label, hint: "", selected: false } }))
    if (pickers.kind === "bulkDue")
      return [{ id: "today", label: "Today", hint: "", selected: false }, { id: "tomorrow", label: "Tomorrow", hint: "", selected: false },
        { id: "week", label: "In a week", hint: "", selected: false }, { id: "monday", label: "Next Monday", hint: "", selected: false },
        { id: "none", label: "No due date", hint: "Ctrl+Shift+D", selected: false }]
    if (pickers.kind === "filter")
      return [{ id: "assignee", label: "Assignee…", hint: workspace.assigneeFilterLabel, selected: !!root.config.assignee },
        { id: "priority", label: "Priority…", hint: root.priorityFilter < 0 ? "" : Linear.priority(root.priorityFilter).label, selected: root.priorityFilter >= 0 },
        { id: "labels", label: "Labels…", hint: root.labelFilter.length ? root.labelFilter.length + " picked" : "1 – 9", selected: root.labelFilter.length > 0 },
        { id: "project", label: "Project…", hint: root.currentProject ? root.currentProject.name : "", selected: !!root.currentProject },
        { id: "cycle", label: "Cycle…", hint: root.cycleFilter ? root.cycleFilterLabel : "", selected: root.cycleFilter !== "" },
        { id: "search", label: "Text…", hint: root.query, selected: root.query !== "" },
        { id: "clear", label: "Clear all filters", hint: "Alt+Shift+F", selected: false }]
    if (pickers.kind === "bulkProject")
      return [{ id: "", label: "No project", hint: "", selected: false }].concat(root.projects.map(function(p) {
        return { id: p.id, label: p.name, hint: "", color: p.color, selected: false }
      }))
    if (pickers.kind === "cycle") {
      var cf = root.cycleFilter
      return [{ id: "", label: "Any cycle", hint: "", selected: cf === "" },
        { id: "current", label: "Current cycle", hint: root.activeCycle ? (root.activeCycle.name || "Cycle " + root.activeCycle.number) : "none running", selected: cf === "current" },
        { id: "none", label: "No cycle", hint: "", selected: cf === "none" }].concat(root.cycles.filter(function(c) { return !c.isActive }).map(function(c) {
          return { id: c.id, label: c.name || "Cycle " + c.number, hint: lists.shortDay(c.startsAt) + " – " + lists.shortDay(c.endsAt), selected: cf === c.id }
        }))
    }
    // Every label, also past the ninth (keys 1 – 9 reach only those); a
    // pick toggles it and the menu stays open for the next one.
    if (pickers.kind === "labelFilter")
      return root.labels.map(function(l) { return { id: l.id, label: l.name, hint: "", color: l.color, selected: root.labelFilter.indexOf(l.id) >= 0 } })
    if (pickers.kind === "priority")
      return [{ id: "-1", label: "Any priority", hint: "", selected: root.priorityFilter < 0 }].concat(
        Linear.PRIORITIES.map(function(p) {
          return { id: String(p.value), label: p.label, hint: p.short, selected: root.priorityFilter === p.value }
        }))
    return []
  }

  function openPicker(kind, x, bottom) {
    pickers.kind = kind
    pickers.popupX = x
    pickers.popupBottom = bottom === undefined ? -1 : bottom
    var items = pickers.pickerItems
    pickers.cursor = Math.max(0, items.findIndex(function(i) { return i.selected }))
    root.dialog = "picker"
    keyScope.forceActiveFocus()
    Qt.callLater(pickers.ensurePickerVisible)
  }

  function ensurePickerVisible() {
    var rowH = Style.spacing.popupRowHeight + Style.space(4)
    var top = pickers.cursor * rowH
    if (top < pickerPopup.pickerFlick.contentY) pickerPopup.pickerFlick.contentY = top
    else if (top + rowH > pickerPopup.pickerFlick.contentY + pickerPopup.pickerFlick.height) pickerPopup.pickerFlick.contentY = top + rowH - pickerPopup.pickerFlick.height
  }

  function choosePicker(index) {
    var item = pickers.pickerItems[index]
    var kind = pickers.kind
    pickers.closeDialog()
    if (!item) return
    if (kind === "team") workspace.setTeam(item.id)
    else if (kind === "view") {
      var parts = item.id.split(":")
      var patch = {}
      patch[parts[0]] = parts[1]
      root.setConfig(patch)
      root.clampSelection()
      // Which done issues are loaded changed: load the board again.
      if (parts[0] === "doneWindow") sync.loadTeam()
    }
    else if (kind.indexOf("bulk") === 0) bulk.applyBulk(kind, item.id)
    else if (kind === "filter") {
      if (item.id === "assignee") pickers.openPicker("assignee", boardScreen.assigneeButton.mapToItem(keyScope, 0, 0).x)
      else if (item.id === "priority") pickers.openPicker("priority", boardScreen.priorityButton.mapToItem(keyScope, 0, 0).x)
      else if (item.id === "labels") pickers.openPicker("labelFilter", boardScreen.searchField.mapToItem(keyScope, 0, 0).x)
      else if (item.id === "project") pickers.openPicker("project", boardScreen.projectButton.mapToItem(keyScope, 0, 0).x)
      else if (item.id === "cycle") pickers.openPicker("cycle", boardScreen.cycleButton.mapToItem(keyScope, 0, 0).x)
      else if (item.id === "search") boardScreen.searchField.forceActiveFocus()
      else workspace.clearFilters(true)
    }
    else if (kind === "labelFilter") {
      workspace.toggleLabelFilter(item.id)
      pickers.openPicker("labelFilter", pickers.popupX)
      pickers.cursor = index
      Qt.callLater(pickers.ensurePickerVisible)
    }
    else if (kind === "assignee") workspace.setAssigneeFilter(item.id)
    else if (kind === "priority") workspace.setPriorityFilter(parseInt(item.id))
    else if (kind === "cycle") workspace.setCycleFilter(item.id)
    else if (item.id === "__new") pickers.openSettings("projects")
    else workspace.setProject(item.id)
  }
}
