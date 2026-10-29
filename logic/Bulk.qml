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

// Bulk actions on picked cards, archiving and drag and drop.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `bulk`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: bulk

  // Drag and drop
  property bool dragging: false
  property string dragId: ""
  property string dragTitle: ""
  property point dragPoint: Qt.point(0, 0)
  property point dragOffset: Qt.point(0, 0)
  property int dropCol: -1
  property int dropIdx: -1
  visible: false

  // ---- bulk actions -----------------------------------------------------------------------------
  function toggleMulti(id) {
    var m = root.multi.slice()
    var i = m.indexOf(id)
    if (i >= 0) m.splice(i, 1)
    else m.push(id)
    root.multi = m
  }

  function selectAllVisible() {
    var ids = []
    root.visibleByColumn.forEach(function(col) { col.forEach(function(i) { ids.push(i.id) }) })
    root.multi = ids
  }

  function applyBulk(kind, value) {
    var member = root.memberById(value)
    if (kind === "bulkRemind") { issueOps.remindIssues(bulk.actionIds(), value); return }
    if (kind === "bulkMilestone") {
      var ms = root.milestoneById(value)
      bulk.bulkUpdate({ projectMilestoneId: value || null }, function() { return { milestoneId: value, milestoneName: ms ? ms.name : "" } }, "Updated")
      return
    }
    if (kind === "bulkCycle") { bulk.bulkUpdate({ cycleId: value || null }, function() { return { cycleId: value } }, "Updated"); return }
    if (kind === "bulkEstimate") {
      var est = value === "" ? null : parseInt(value)
      bulk.bulkUpdate({ estimate: est }, function() { return { estimate: est } }, "Updated")
      return
    }
    if (kind === "bulkDue") {
      var days = { today: 0, tomorrow: 1, week: 7 }
      var due = value === "none" ? null : (value === "monday"
        ? Dates.isoDate(Dates.addDays(new Date(), (8 - new Date().getDay()) % 7 || 7))
        : Dates.isoDate(Dates.addDays(new Date(), days[value] || 0)))
      bulk.bulkUpdate({ dueDate: due }, function() { return { dueDate: due || "" } }, due ? "Due " + due + ":" : "Removed due date from")
      return
    }
    if (kind === "bulkState") bulk.bulkUpdate({ stateId: value }, function() { return { stateId: value } }, "Moved")
    else if (kind === "bulkAssignee") bulk.bulkUpdate({ assigneeId: value || null }, function() { return { assignee: member } }, value ? "Assigned" : "Unassigned")
    else if (kind === "bulkPriority") bulk.bulkUpdate({ priority: parseInt(value) }, function() { return { priority: parseInt(value) } }, "Updated")
    else if (kind === "bulkLabel") {
      // Toggle: remove it when every target has it already, else add it.
      var hasAll = bulk.actionIds().every(function(id) { var i = root.issueById(id); return i && i.labelIds.indexOf(value) >= 0 })
      if (hasAll) bulk.bulkUpdate({ removedLabelIds: [value] }, function(i) { return { labelIds: i.labelIds.filter(function(x) { return x !== value }) } }, "Removed the label from")
      else bulk.bulkUpdate({ addedLabelIds: [value] }, function(i) {
        return { labelIds: i.labelIds.indexOf(value) >= 0 ? i.labelIds : i.labelIds.concat([value]) }
      }, "Labeled")
    }
    else if (kind === "bulkProject") bulk.bulkUpdate({ projectId: value || null }, function() { return { projectId: value } }, "Updated")
  }

  // One change to every picked issue: shown at once, then sent in batches.
  // The issues a shortcut or the bulk bar acts on: the picked cards, else the
  // card under the cursor (like Linear).
  function actionIds() {
    var picked = root.multi.filter(function(id) { return root.onBoard(id) })
    if (picked.length) return picked
    return root.selectedIssue ? [root.selectedIssue.id] : []
  }

  function bulkUpdate(input, patchFor, verb) {
    var ids = bulk.actionIds()
    if (!ids.length) return
    var before = root.issues
    var one = ids.length === 1 ? root.issueById(ids[0]) : null
    var undoKey = undoer.pushUndo({ label: "change of " + (one ? one.identifier : ids.length + " issues"), changes: undoer.undoChanges(ids, input) })
    // Repeating issues moved to another project: their rules follow.
    if (input.projectId !== undefined) ids.forEach(function(id) {
      var i = root.issueById(id)
      if (i) issueOps.followRecurring(i, { projectId: input.projectId || "", milestoneId: "" })
    })
    root.editSeq++
    root.issues = root.issues.map(function(i) {
      if (ids.indexOf(i.id) < 0) return i
      var next = {}, patch = patchFor(i)
      for (var k in i) next[k] = i[k]
      for (var p in patch) next[p] = patch[p]
      return next
    })
    var beforeExtra = root.extraIssues
    root.dropMisfits()
    var left = 0, failed = false
    for (var c = 0; c < ids.length; c += Linear.BATCH_SIZE) {
      left++
      sync.send("Bulk change", Linear.M_ISSUE_BATCH, { ids: ids.slice(c, c + Linear.BATCH_SIZE), input: input }, function(d) {
        d.issueBatchUpdate.issues.forEach(function(raw) { root.storeIssue(Linear.toIssue(raw)) })
        if (--left === 0 && !failed) { undoer.notifyUndo(verb + " " + (one ? one.identifier : ids.length + " issues"), undoKey); root.saveCache() }
      }, function(msg) {
        if (failed) return
        failed = true
        root.issues = before
        root.extraIssues = beforeExtra
        undoer.dropUndo(undoKey)
        notices.notify("Bulk change failed: " + msg, true)
        sync.loadTeam()
      })
    }
  }

  // A picker for the issues under the cursor or picked; it opens next to the
  // card (or above the bulk bar while cards are picked).
  function openActionPicker(kind) {
    if (!bulk.actionIds().length) { notices.notify("Select a card first (arrows or click)."); return }
    if (root.multi.length && bulkBar.visible) { pickers.openPicker(kind, bulkBar.mapToItem(keyScope, 0, 0).x, bulkBar.mapToItem(keyScope, 0, 0).y - Style.spacing.sm); return }
    if (root.listLayout) { pickers.openPicker(kind, Math.max(0, keyScope.width / 2 - Style.space(150))); return }
    var col = boardScreen.colRepeater.itemAt(root.selCol)
    pickers.openPicker(kind, col ? col.mapToItem(keyScope, 0, 0).x : 0)
  }

  // I: assign to me, or unassign when it is already mine (one card).
  function assignToMe() {
    var ids = bulk.actionIds()
    if (!ids.length || !root.viewer) return
    var me = root.memberById(root.viewer.id) || Linear.toMembers([root.viewer], root.viewer.id)[0]
    var allMine = ids.every(function(id) { var i = root.issueById(id); return i && i.assignee && i.assignee.id === root.viewer.id })
    if (allMine) bulk.bulkUpdate({ assigneeId: null }, function() { return { assignee: null } }, "Unassigned")
    else bulk.bulkUpdate({ assigneeId: root.viewer.id }, function() { return { assignee: me } }, "Assigned to you:")
  }

  function subscribeSelected() {
    var sel = root.selectedIssue
    if (!sel) return
    root.gql(Linear.M_SUBSCRIBE, { id: sel.id }, function() { notices.notify("Subscribed to " + sel.identifier) },
      function(msg) { notices.notify("Could not subscribe: " + msg, true) })
  }

  function copyIssue(issue, kind) {
    if (!issue) { notices.notify("Select a card first."); return }
    var text = Issues.copyText(issue, kind)
    if (!text) { notices.notify("Nothing to copy (reload the board)."); return }
    copyProc.text = text
    copyProc.running = true
    var what = { id: "ID", branch: "git branch", url: "link", markdown: "Markdown link", title: "ID and title" }[kind] || ""
    notices.notify("Copied " + what + ": " + text, false, root.icon.check)
  }

  function jumpToType(type) {
    for (var c = 0; c < root.columns.length; c++)
      if (root.columns[c].type === type) { root.selCol = c; root.selIdx = 0; root.cursorShown = true; root.ensureVisible(); return }
  }

  function editForRename(id) {
    issueOps.editIssue(id)
    Qt.callLater(function() { editor.titleField.forceActiveFocus(); editor.titleField.selectAll() })
  }

  function editForComment(id) {
    issueOps.editIssue(id)
    Qt.callLater(function() {
      editor.commentField.forceActiveFocus()
      editor.editorFlick.contentY = Math.max(0, editor.editorFlick.contentHeight - editor.editorFlick.height)
    })
  }

  function editForRelation(kind) {
    var sel = root.selectedIssue
    if (!sel) return
    issueOps.editIssue(sel.id)
    ed.relKind = kind
    Qt.callLater(function() { editor.relationField.forceActiveFocus() })
  }

  // ---- archive ----
  function archiveIds(ids, label) {
    if (!ids.length) return
    var before = root.issues
    var undoKey = undoer.pushUndo({ label: "archiving " + label, restore: ids.slice() })
    root.editSeq++
    root.issues = root.issues.filter(function(i) { return ids.indexOf(i.id) < 0 })
    root.multi = root.multi.filter(function(id) { return ids.indexOf(id) < 0 })
    root.clampSelection()
    var left = 0, failed = false
    for (var c = 0; c < ids.length; c += Linear.BATCH_SIZE) {
      var chunk = ids.slice(c, c + Linear.BATCH_SIZE)
      left++
      sync.send("Archive", Linear.archiveIssuesDocument(chunk.length), Linear.idVariables(chunk), function() {
        if (--left === 0 && !failed) { undoer.notifyUndo("Archived " + label, undoKey); root.saveCache() }
      }, function(msg) {
        if (failed) return
        failed = true
        root.issues = before
        undoer.dropUndo(undoKey)
        notices.notify("Could not archive: " + msg, true)
        sync.loadTeam()
      })
    }
  }

  // Ctrl+Shift+X: archive the picked cards (or the one under the cursor).
  function archiveTargets() {
    var ids = bulk.actionIds()
    if (!ids.length) return
    var one = ids.length === 1 ? root.issueById(ids[0]) : null
    pickers.ask("Archive " + (one ? one.identifier + " “" + one.title + "”" : ids.length + " issues") + "? Archived issues leave the board and stop counting toward the free plan's issue limit; Linear can restore them.",
      "Archive", function() { bulk.archiveIds(ids, one ? one.identifier : ids.length + " issues") })
  }

  // Ctrl+Shift+C, like Linear: the selected issues go to the running cycle.
  function addToActiveCycle() {
    if (!bulk.actionIds().length) return
    if (!root.activeCycle) { notices.notify("No cycle is running in this team", true); return }
    bulk.applyBulk("bulkCycle", root.activeCycle.id)
  }

  function deleteTargets() {
    if (root.multi.length) bulk.bulkDelete()
    else if (root.selectedIssue) editorOps.deleteIssue(root.selectedIssue.id)
  }

  // Settings → Team: archive every done/canceled issue closed for `days` days.
  function archiveClosedOlderThan(days) {
    days = parseInt(days)
    if (!(days >= 0) || !root.team) { notices.notify("Type a number of days.", true); return }
    sync.gqlAll(Linear.Q_CLOSED_BEFORE, { filter: Linear.closedBeforeFilter(root.team.id, days) }, function(d) { return d.issues }, function(nodes) {
      if (!nodes.length) { notices.notify("No done or canceled issues closed more than " + days + " days ago."); return }
      pickers.ask("Archive " + nodes.length + " done or canceled issues of " + root.team.name + " closed more than " + days + " days ago (e.g. " +
        nodes.slice(0, 3).map(function(n) { return n.identifier }).join(", ") + ")?", "Archive", function() {
        bulk.archiveIds(nodes.map(function(n) { return n.id }), nodes.length + " issues")
      })
    }, function(msg) { notices.notify(msg, true) })
  }

  function bulkDelete() {
    var ids = bulk.actionIds()
    if (!ids.length) return
    pickers.ask("Delete " + ids.length + (ids.length === 1 ? " issue" : " issues") + "? They go to Linear's trash.", "Delete", function() {
      var before = root.issues
      var delKey = undoer.pushUndo({ label: "deleting " + ids.length + (ids.length === 1 ? " issue" : " issues"), restore: ids.slice() })
      root.editSeq++
      root.issues = root.issues.filter(function(i) { return ids.indexOf(i.id) < 0 })
      root.multi = []
      root.clampSelection()
      for (var c = 0; c < ids.length; c += Linear.BATCH_SIZE) {
        var chunk = ids.slice(c, c + Linear.BATCH_SIZE)
        sync.send("Delete issues", Linear.deleteDocument(chunk.length), Linear.idVariables(chunk), function() { root.saveCache() },
          function(msg) { root.issues = before; notices.notify("Could not delete: " + msg, true); sync.loadTeam() })
      }
      undoer.notifyUndo("Deleted " + ids.length + (ids.length === 1 ? " issue" : " issues"), delKey)
    })
  }

  function openBulkPicker(kind, button) {
    var p = button.mapToItem(keyScope, 0, 0)
    pickers.openPicker(kind, p.x, p.y - Style.spacing.sm)
  }

  // ---- drag and drop -------------------------------------------------------------------------
  function startDrag(issue, point, offset) {
    bulk.dragging = true
    bulk.dragId = issue.id
    bulk.dragTitle = (issue.identifier ? issue.identifier + "  " : "") + issue.title
    bulk.dragOffset = offset
    root.cursorShown = false
    bulk.updateDrag(point)
  }

  function updateDrag(point) {
    bulk.dragPoint = point
    var col = -1, idx = -1
    if (root.listLayout) {
      // List: the group under the pointer (or the nearest one), and the row in it.
      var best = -1, bestDist = 1e9
      for (var g = 0; g < boardScreen.listGroups.count; g++) {
        var grp = boardScreen.listGroups.itemAt(g)
        if (!grp) continue
        var q = dragLayer.mapToItem(grp, point.x, point.y)
        var dist = q.y < 0 ? -q.y : (q.y > grp.height ? q.y - grp.height : 0)
        if (dist < bestDist) { bestDist = dist; best = g; idx = grp.dropIndexAt(q.y) }
      }
      bulk.dropCol = best
      bulk.dropIdx = best >= 0 ? idx : -1
      return
    }
    for (var i = 0; i < boardScreen.colRepeater.count; i++) {
      var item = boardScreen.colRepeater.itemAt(i)
      if (!item) continue
      var p = dragLayer.mapToItem(item, point.x, point.y)
      if (p.x >= -root.gap / 2 && p.x <= item.width + root.gap / 2) { col = i; idx = item.dropIndexAt(p.y); break }
    }
    bulk.dropCol = col
    bulk.dropIdx = idx
  }

  function endDrag(drop) {
    if (!bulk.dragging) return
    var id = bulk.dragId, col = bulk.dropCol, idx = bulk.dropIdx
    bulk.dragging = false
    bulk.dragId = ""
    bulk.dropCol = -1
    bulk.dropIdx = -1
    if (!drop || col < 0) return
    var visible = root.visibleByColumn[col]
    var full = Issues.issuesIn(root.issues, root.columns[col].id).map(function(i) { return i.id })
    var real = idx < visible.length ? full.indexOf(visible[idx].id) : (visible.length ? full.indexOf(visible[visible.length - 1].id) + 1 : full.length)
    issueOps.moveIssue(id, root.columns[col].id, real)
  }

  Timer {
    id: autoScroll
    interval: 16
    repeat: true
    running: bulk.dragging
    onTriggered: {
      if (root.listLayout) {
        var lp = dragLayer.mapToItem(boardScreen.listFlick, bulk.dragPoint.x, bulk.dragPoint.y)
        var ledge = Style.space(50), lstep = 0
        if (lp.y < ledge) lstep = -Style.space(14)
        else if (lp.y > boardScreen.listFlick.height - ledge) lstep = Style.space(14)
        if (lstep === 0) return
        var lmax = Math.max(0, boardScreen.listFlick.contentHeight - boardScreen.listFlick.height)
        boardScreen.listFlick.contentY = Math.max(0, Math.min(lmax, boardScreen.listFlick.contentY + lstep))
        bulk.updateDrag(bulk.dragPoint)
        return
      }
      var p = dragLayer.mapToItem(boardScreen.boardFlick, bulk.dragPoint.x, bulk.dragPoint.y)
      var edge = Style.space(60), step = 0
      if (p.x < edge) step = -Style.space(14)
      else if (p.x > boardScreen.boardFlick.width - edge) step = Style.space(14)
      if (step === 0) return
      var max = Math.max(0, boardScreen.boardFlick.contentWidth - boardScreen.boardFlick.width)
      boardScreen.boardFlick.contentX = Math.max(0, Math.min(max, boardScreen.boardFlick.contentX + step))
      bulk.updateDrag(bulk.dragPoint)
    }
  }

  // The text goes to wl-copy on stdin, not in its arguments.
  Process {
    id: copyProc
    property string text: ""
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: { copyProc.write(copyProc.text); copyProc.text = ""; stdinEnabled = false }
    onExited: stdinEnabled = true
  }
}
