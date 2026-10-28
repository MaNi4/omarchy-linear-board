import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Dates.js" as Dates
import "../Help.js" as Help

// Keyboard shortcuts and the per-window shortcut help.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `keyboard`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: keyboard
  visible: false

  // ---- keyboard ---------------------------------------------------------------------------------
  // The board's keys inside the issue editor: the same key, the same thing.
  // Returns true when it handled `t`.
  function boardKey(t) {
    var menus = { s: "status", p: "priority", a: "assignee", t: "labels", P: "project", M: "milestone", C: "cycle", E: "estimate", D: "due" }
    if (menus[t]) { editor.openMenu(menus[t]); return true }
    if (t === "i" && root.viewer) { ed.assigneeId = ed.assigneeId === root.viewer.id ? "" : root.viewer.id; return true }
    if (t === "r") { editor.titleField.forceActiveFocus(); editor.titleField.selectAll(); return true }
    if (t === "e") { ed.descPreview = false; Qt.callLater(function() { editor.descField.forceActiveFocus() }); return true }
    if (t === "T" && ed.issueId) { timeTracker.toggleTimer(ed.orig); return true }
    if (t === "R" && ed.issueId) { editor.openMore(); return true }
    if (t === "?") { keyboard.openHelp("issue"); return true }
    return false
  }

  // Alt + the board's key opens that property's menu in the editor, also
  // while typing. Text fields call it first, or they would type the letter.
  function altMenu(event) {
    var mods = event.modifiers
    if (!(mods & Qt.AltModifier) || (mods & Qt.ControlModifier) || event.key < Qt.Key_A || event.key > Qt.Key_Z) return false
    var menuKeys = (mods & Qt.ShiftModifier) ? { P: "project", M: "milestone", C: "cycle", E: "estimate", D: "due", U: "parent", T: "team" }
      : { S: "status", P: "priority", A: "assignee", T: "labels", M: "milestone", C: "cycle", E: "estimate", D: "due", U: "parent" }
    var which = menuKeys[String.fromCharCode(event.key)]
    if (!which) return false
    editor.openMenu(which)
    event.accepted = true
    return true
  }

  function handleKey(event) {
    var key = event.key
    var t = event.text || ""
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var enter = key === Qt.Key_Return || key === Qt.Key_Enter

    if (keyboard.helpContext) {
      keyboard.closeHelp()
      event.accepted = true
      return
    }
    if (key === Qt.Key_F1) {
      keyboard.openHelp(root.dialog === "picker" || root.dialog === "palette" || !root.dialog ? "board" : root.dialog)
      event.accepted = true
      return
    }
    if (pickers.confirmText) {
      if (key === Qt.Key_Escape) { pickers.confirmText = ""; pickers.refocus() }
      else if (enter || t === "y") pickers.runConfirm()
      event.accepted = true
      return
    }
    if (key === Qt.Key_Escape) {
      if (bulk.dragging) bulk.endDrag(false)
      // In a saved issue, Esc first leaves the text field (back to the shortcuts).
      else if (root.dialog === "issue" && ed.issueId && editor.typing()) keyScope.forceActiveFocus()
      // In the trash, Esc first clears what is picked.
      else if (root.dialog === "search" && lists.isBin && lists.binPicked.length) lists.binPicked = []
      else if (root.dialog === "search" && lists.isBin && lists.binQuery) issueListDialog.binField.text = ""
      else if (root.dialog) pickers.closeDialog()
      else if (root.multi.length) root.multi = []
      else if (root.query || root.labelFilter.length || root.priorityFilter >= 0 || root.cycleFilter) workspace.clearFilters(false)
      event.accepted = true
      return
    }
    if (root.mode !== "board") return
    if (root.dialog === "issue") {
      var cur = ed.orig
      if (enter && ctrl) editorOps.saveIssue()
      else if (ctrl && cur && (key === Qt.Key_Period || key === Qt.Key_Greater))
        bulk.copyIssue(cur, shift || key === Qt.Key_Greater ? "branch" : ((event.modifiers & Qt.AltModifier) ? "title" : "id"))
      else if (ctrl && cur && (key === Qt.Key_Comma || key === Qt.Key_Less)) bulk.copyIssue(cur, (event.modifiers & Qt.AltModifier) ? "markdown" : "url")
      else if (ctrl && key === Qt.Key_M && ed.issueId) { editor.commentField.forceActiveFocus(); editor.editorFlick.contentY = Math.max(0, editor.editorFlick.contentHeight - editor.editorFlick.height) }
      else if (ctrl && shift && key === Qt.Key_D) { editor.dueField.text = ""; ed.dueError = false }
      else if (ctrl && key === Qt.Key_D) editor.openMenu("due")
      else if (ctrl && shift && key === Qt.Key_O && ed.issueId) editorOps.addSubIssue()
      // The issue's own actions, as on the board. Ctrl+Backspace and Delete
      // only outside text fields, where they delete text.
      else if (ed.issueId && !editor.typing() && ((ctrl && key === Qt.Key_Backspace) || (!ctrl && key === Qt.Key_Delete))) editorOps.deleteIssue(ed.issueId)
      else if (ed.issueId && ctrl && shift && key === Qt.Key_X) editor.archiveOpen()
      else if (ctrl && !shift && key === Qt.Key_O && ed.url) editorOps.openInLinear(ed.url)
      // Outside text fields (they undo their own typing): the last change.
      else if (ctrl && !shift && key === Qt.Key_Z && !editor.typing()) { editorOps.flush(); undoer.undo() }
      else if (ctrl && shift && key === Qt.Key_C) {
        var ac = ed.team.cycles.filter(function(c) { return c.isActive })[0]
        if (ac) { ed.cycleId = ac.id; if (!ed.issueId) notices.notify("Cycle: " + (ac.name || "Cycle " + ac.number)) }
        else notices.notify("No cycle is running in this team", true)
      }
      else if (ctrl && shift && key === Qt.Key_P) {
        if (editor.commentField.activeFocus) ed.commentPreview = !ed.commentPreview
        else issueOps.toggleDescPreview()
      }
      else if (ctrl && shift && key === Qt.Key_Up && ed.parentIssue) editorOps.saveAndEdit(ed.parentIssue.id, "")
      else if (ctrl && shift && key === Qt.Key_Down && ed.subIssues.length) editorOps.saveAndEdit(ed.subIssues[0].id, ed.subIssues[0].url)
      // The board's own keys, when no text field takes them (like Linear).
      else if (!ctrl && !(event.modifiers & Qt.AltModifier) && !editor.typing() && boardKey(t)) {}
      // Alt + the board's key opens that property's menu, also while typing.
      else if (altMenu(event)) {}
      else return
      event.accepted = true
      return
    }
    if (root.dialog === "palette") return
    if (t === "?" && (root.dialog === "inbox" || root.dialog === "search" || root.dialog === "time" || root.dialog === "settings" || root.dialog === "project")) {
      keyboard.openHelp(root.dialog)
      event.accepted = true
      return
    }
    if (root.dialog === "time") {
      if (key === Qt.Key_Left || t === "h") timeTracker.reportOffset--
      else if (key === Qt.Key_Right || t === "l") timeTracker.reportOffset = Math.min(0, timeTracker.reportOffset + 1)
      else if (t === "d") { timeTracker.reportKind = "day"; timeTracker.reportOffset = 0 }
      else if (t === "w") { timeTracker.reportKind = "week"; timeTracker.reportOffset = 0 }
      else if (t === "m") { timeTracker.reportKind = "month"; timeTracker.reportOffset = 0 }
      else if (t === "T") timeTracker.stopTimer()
      else return
      event.accepted = true
      return
    }
    if (root.dialog === "search") {
      var res = lists.searchResults
      if (key === Qt.Key_Down || t === "j") lists.searchCursor = Math.min(res.length - 1, lists.searchCursor + 1)
      else if (key === Qt.Key_Up || t === "k") lists.searchCursor = Math.max(0, lists.searchCursor - 1)
      else if (enter) { if (lists.isBin) lists.openBinResult(res[lists.searchCursor]); else lists.openSearchResult(res[lists.searchCursor]) }
      else if (t === "o") { if (res[lists.searchCursor]) editorOps.openInLinear(res[lists.searchCursor].url) }
      else if (lists.listMode === "cycle" && (t === "h" || key === Qt.Key_Left)) lists.stepCycle(-1)
      else if (lists.listMode === "cycle" && (t === "l" || key === Qt.Key_Right)) lists.stepCycle(1)
      else if (lists.listMode === "triage" && t === "a") lists.triageAccept(res[lists.searchCursor])
      else if (lists.listMode === "triage" && t === "d") lists.triageDecline(res[lists.searchCursor])
      else if (lists.listMode === "cycle" && t === "e" && lists.cycleView) lists.cycleEditing = !lists.cycleEditing
      else if (lists.isBin && key === Qt.Key_Tab) lists.switchBin()
      else if (lists.isBin && t === "/") issueListDialog.binField.forceActiveFocus()
      else if (lists.isBin && t === "r") lists.restoreTrashed(res[lists.searchCursor], true)
      // Delete goes one step on: archived → trash, trash → gone.
      else if (lists.listMode === "archived" && key === Qt.Key_Delete) lists.trashArchived(res[lists.searchCursor], true)
      else if (lists.listMode === "trash" && key === Qt.Key_Delete) lists.deleteForever(res[lists.searchCursor], true)
      else if (lists.isBin && (t === "x" || key === Qt.Key_Space)) { lists.toggleBinPick(res[lists.searchCursor]); lists.searchCursor = Math.min(res.length - 1, lists.searchCursor + 1) }
      else if (lists.isBin && ctrl && key === Qt.Key_A) lists.pickAllBin()
      else return
      issueListDialog.searchList.positionViewAtIndex(lists.searchCursor, ListView.Contain)
      event.accepted = true
      return
    }
    if (root.dialog === "inbox") {
      var list = inboxCtl.shown, cur = list[inboxCtl.cursor]
      if (key === Qt.Key_Down || t === "j") inboxCtl.cursor = Math.min(list.length - 1, inboxCtl.cursor + 1)
      else if (key === Qt.Key_Up || t === "k") inboxCtl.cursor = Math.max(0, inboxCtl.cursor - 1)
      else if (enter || t === "o") inboxCtl.openNotification(cur)
      else if (inboxCtl.snoozeId && cur && cur.id === inboxCtl.snoozeId && t >= "1" && t <= "3")
        inboxCtl.snoozeNotification(cur, Dates.SNOOZE_OPTIONS[parseInt(t) - 1].id)
      else if (t === "s") { if (cur) inboxCtl.snoozeId = inboxCtl.snoozeId === cur.id ? "" : cur.id }
      else if (t === "U") inboxCtl.unsubscribeNotification(cur)
      else if (t === "u") { if (cur) inboxCtl.setRead(cur, !cur.read) }
      else if (t === "x" || key === Qt.Key_Delete) inboxCtl.archiveNotification(cur)
      else if (t === "A") inboxCtl.markAllRead()
      else if (t === "a") { inboxCtl.unreadOnly = !inboxCtl.unreadOnly; inboxCtl.clampInboxCursor() }
      else if (t === "i") pickers.closeDialog()
      else return
      inboxDialog.inboxList.positionViewAtIndex(inboxCtl.cursor, ListView.Contain)
      event.accepted = true
      return
    }
    if (root.dialog === "picker") {
      var n = pickers.pickerItems.length
      if (key === Qt.Key_Down || t === "j") { pickers.cursor = (pickers.cursor + 1) % n; pickers.ensurePickerVisible() }
      else if (key === Qt.Key_Up || t === "k") { pickers.cursor = (pickers.cursor - 1 + n) % n; pickers.ensurePickerVisible() }
      else if (enter) pickers.choosePicker(pickers.cursor)
      else if (t >= "1" && t <= "9") pickers.choosePicker(parseInt(t) - 1)
      else return
      event.accepted = true
      return
    }
    if (root.dialog) return

    // Two-key shortcuts like Linear's: G then I (inbox), O then T (team), M then R (relation)…
    if (keyboard.keyPrefix) {
      var pre = keyboard.keyPrefix
      keyboard.keyPrefix = ""
      var lt = t.toLowerCase()
      if (pre === "g") {
        if (lt === "i") inboxCtl.openInbox(inboxCtl.boardFilter)
        else if (lt === "m") workspace.toggleMine()
        else if (lt === "s") pickers.openSettings("columns")
        else if (lt === "p") pickers.openSettings("projects")
        else if (lt === "e") { workspace.setProject(""); workspace.clearFilters(true) }
        else if (lt === "b") bulk.jumpToType("backlog")
        else if (lt === "a") bulk.jumpToType("started")
        else if (lt === "t") { if (lists.triageOn) lists.openTriage(); else notices.notify("This team has no triage (time report: W)") }
        else if (lt === "y") lists.openMyIssues()
        else if (lt === "c" || lt === "v") lists.openCycles()
        else if (lt === "w") lists.openCycles("next")
        else if (lt === "x") lists.openArchived()
        else if (lt === "d") { if (root.dialog) pickers.closeDialog(); if ((root.config.layout || "board") !== "board") workspace.toggleLayout() }
        else if (lt === "u") projectOps.openProject(root.config.projectId)
        else if (lt === "r") { if (lists.triageOn) lists.openTriage(); else notices.notify("This team has no triage") }
      } else if (pre === "o") {
        if (lt === "t") pickers.openPicker("team", boardScreen.teamButton.mapToItem(keyScope, 0, 0).x)
        else if (lt === "p") pickers.openPicker("project", boardScreen.projectButton.mapToItem(keyScope, 0, 0).x)
        else if (lt === "u" || lt === "m") pickers.openPicker("assignee", boardScreen.assigneeButton.mapToItem(keyScope, 0, 0).x)
        else if (lt === "c") pickers.openPicker("cycle", boardScreen.cycleButton.mapToItem(keyScope, 0, 0).x)
      } else if (pre === "m") {
        if (lt === "r") bulk.editForRelation("related")
        else if (lt === "x") bulk.editForRelation("blocks")
        else if (lt === "b") bulk.editForRelation("blockedBy")
      }
      event.accepted = true
      return
    }

    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var sel = root.selectedIssue
    var handled = true
    // ---- moving around (arrows / vim keys); Shift moves the issue ----
    // like vim: h j k l = ← ↓ ↑ →; with Shift (H J K L) the issue moves
    if (key === Qt.Key_Left || (!ctrl && !alt && (t === "h" || t === "H"))) shift || t === "H" ? issueOps.shiftSelected(-1, 0) : root.moveCursor(-1, 0)
    else if (key === Qt.Key_Right || (!ctrl && !alt && (t === "l" || t === "L"))) shift || t === "L" ? issueOps.shiftSelected(1, 0) : root.moveCursor(1, 0)
    else if (key === Qt.Key_Up && ctrl && shift) { if (sel && sel.parent) root.openIssueAnywhere(sel.parent.id, "") }
    else if (key === Qt.Key_Down && ctrl && shift) { if (sel) { var kid = root.issues.filter(function(i) { return i.parent && i.parent.id === sel.id })[0]; if (kid) root.openIssueAnywhere(kid.id, "") } }
    else if (key === Qt.Key_Up || (!ctrl && (t === "k" || t === "K"))) shift || t === "K" ? issueOps.shiftSelected(0, -1) : root.moveCursor(0, -1)
    else if (key === Qt.Key_Down || (!ctrl && (t === "j" || t === "J"))) shift || t === "J" ? issueOps.shiftSelected(0, 1) : root.moveCursor(0, 1)
    // ---- copying (Linear: Ctrl+. ID, Ctrl+Shift+. branch, Ctrl+Shift+, link) ----
    else if (ctrl && (key === Qt.Key_Period || key === Qt.Key_Greater)) bulk.copyIssue(sel, shift || key === Qt.Key_Greater ? "branch" : (alt ? "title" : "id"))
    else if (ctrl && (key === Qt.Key_Comma || key === Qt.Key_Less)) bulk.copyIssue(sel, alt ? "markdown" : "url")
    // ---- other Ctrl shortcuts ----
    else if (ctrl && key === Qt.Key_A) bulk.selectAllVisible()
    else if (ctrl && key === Qt.Key_Z) undoer.undo()
    else if (ctrl && key === Qt.Key_K) commands.openPalette()
    else if (ctrl && key === Qt.Key_B) workspace.toggleLayout()
    else if (ctrl && key === Qt.Key_L) bulk.openActionPicker("bulkLabel")
    else if (ctrl && shift && key === Qt.Key_O) { if (sel) issueOps.newIssue(root.selCol, { id: sel.id, identifier: sel.identifier, title: sel.title }) }
    else if (ctrl && shift && key === Qt.Key_D) bulk.applyBulk("bulkDue", "none")
    else if (ctrl && key === Qt.Key_D) bulk.openActionPicker("bulkDue")
    else if (ctrl && key === Qt.Key_M) { if (sel) bulk.editForComment(sel.id) }
    else if (ctrl && shift && key === Qt.Key_X) bulk.archiveTargets()
    else if (ctrl && shift && key === Qt.Key_C) bulk.addToActiveCycle()
    else if (ctrl && key === Qt.Key_Backspace) bulk.deleteTargets()
    else if (ctrl && key === Qt.Key_O) { if (sel) editorOps.openInLinear(sel.url) }
    else if ((ctrl && key === Qt.Key_R) || key === Qt.Key_F5) sync.refresh()
    else if (ctrl) handled = false
    // ---- single keys (Linear's) ----
    else if (key === Qt.Key_Delete) bulk.deleteTargets()
    else if (t === "c" || t === "n") issueOps.newIssue(root.selCol)
    else if (enter || t === "e") { if (sel) issueOps.editIssue(sel.id) }
    else if (t === "r") { if (sel) bulk.editForRename(sel.id) }
    else if (t === "R") bulk.openActionPicker("bulkRemind")
    else if (t === "M") bulk.openActionPicker("bulkMilestone")
    else if (t === "x" || key === Qt.Key_Space) { if (sel) { root.cursorShown = true; bulk.toggleMulti(sel.id) } }
    else if (t === "s") bulk.openActionPicker("bulkState")
    else if (t === "p") bulk.openActionPicker("bulkPriority")
    else if (t === "a") bulk.openActionPicker("bulkAssignee")
    else if (t === "i") bulk.assignToMe()
    else if (t === "P") bulk.openActionPicker("bulkProject")
    else if (t === "C") bulk.openActionPicker("bulkCycle")
    else if (t === "E") bulk.openActionPicker("bulkEstimate")
    else if (t === "D") bulk.openActionPicker("bulkDue")
    else if (t === "S") bulk.subscribeSelected()
    else if (t === "t") bulk.openActionPicker("bulkLabel")   // labels (Linear's L; l moves right here)
    else if (t === "f") pickers.openPicker("filter", boardScreen.searchField.mapToItem(keyScope, 0, 0).x)
    else if (t === "F") workspace.clearFilters(alt)
    else if (t === "g" || t === "o" || t === "m") { keyboard.keyPrefix = t; prefixTimer.restart() }
    else if (t === "/") boardScreen.searchField.forceActiveFocus()
    else if (t === "v") pickers.openPicker("view", boardScreen.viewButton.mapToItem(keyScope, 0, 0).x)
    else if (t === "T") { if (sel) timeTracker.toggleTimer(sel); else if (timeTracker.running) timeTracker.stopTimer() }
    else if (t === "w") lists.openTimeReport()
    else if (t === "," ) pickers.openSettings("columns")
    else if (t === "?") keyboard.openHelp("board")
    else if (t >= "1" && t <= "9") { var lb = root.labels[parseInt(t) - 1]; if (lb) workspace.toggleLabelFilter(lb.id) }
    else handled = false
    event.accepted = handled
  }

  // ---- shortcut help, per window ----
  // Each window (board, issue editor, inbox…) has its own short list, opened
  // with its ? button, the ? key, or F1 (which also works while typing).
  // In a key list, "then", "+" and "–" are words between keys.
  property string helpContext: ""      // "" = closed
  readonly property var helpTitles: Help.TITLES
  readonly property var helpSections: Help.SECTIONS

  function openHelp(context) {
    if (context === "close") { keyboard.closeHelp(); return }
    keyboard.helpContext = context || "board"
    keyScope.forceActiveFocus()
  }
  function closeHelp() {
    keyboard.helpContext = ""
    pickers.refocus()
  }

  property string keyPrefix: ""
  Timer { id: prefixTimer; interval: 1500; onTriggered: keyboard.keyPrefix = "" }
}
