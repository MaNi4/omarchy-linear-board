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
import "../Edit.js" as Edit
import "../Issues.js" as Issues

// Undo (Ctrl+Z) and the undo toasts.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `undoer`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: undoer
  visible: false

  // ---- undo (Ctrl+Z) ----
  // Each change made on the board leaves a step here: the values to put back
  // (changes: [{ id, input }]), issues to bring back from the archive or
  // trash (restore: ids), a new issue to delete again (remove: id), or its
  // own way back (run: function(ok, fail), for comments and relations).
  property var undoStack: []
  property int undoSeq: 0
  function pushUndo(entry) {
    entry.key = ++undoer.undoSeq
    undoer.undoStack = undoer.undoStack.concat([entry]).slice(-30)
    return entry.key
  }
  // A toast for a change that can be undone: clicking it (or Ctrl+Z) takes it back.
  function notifyUndo(message, key) {
    var k = key || (undoer.undoStack.length ? undoer.undoStack[undoer.undoStack.length - 1].key : 0)
    notices.notifyAction(message + "   ·   Undo: click or Ctrl+Z", function() { undoer.undo(k) }, root.icon.check)
  }
  // Adds to a step that is still there (text typed in one go is one step):
  // fields it already has keep their first value. False when it is gone.
  function extendUndo(key, changes) {
    var e = undoer.undoStack.filter(function(x) { return x.key === key })[0]
    if (!e || !e.changes) return false
    e.changes = Edit.mergeUndo(e.changes, changes)
    undoer.undoStack = undoer.undoStack.slice()
    return true
  }
  function dropUndo(key) { undoer.undoStack = undoer.undoStack.filter(function(e) { return e.key !== key }) }
  // Undo steps for `input` applied to the given issues, from their current values.
  function undoChanges(ids, input) {
    return ids.map(function(id) { var i = root.issueById(id); return i ? { id: id, input: Edit.undoInput(i, input) } : null })
      .filter(function(c) { return c && Object.keys(c.input).length })
  }
  // key: a particular step (from its toast); otherwise the newest one.
  function undo(key) {
    if (!undoer.undoStack.length) { notices.notify("Nothing to undo"); return }
    var e = undoer.undoStack[undoer.undoStack.length - 1]
    if (key) {
      e = undoer.undoStack.filter(function(x) { return x.key === key })[0]
      if (!e) { notices.notify("That change was undone already"); return }
    }
    undoer.undoStack = undoer.undoStack.filter(function(x) { return x.key !== e.key })
    if (editorOps.textSession && editorOps.textSession.key === e.key) editorOps.textSession = null
    // Steps that know how to take themselves back (comments, relations).
    if (e.run) {
      e.run(function() { notices.notify("Undone: " + e.label, false, root.icon.check) },
        function(msg) { notices.notify("Could not undo " + e.label + ": " + msg, true) })
      return
    }
    var failed = function(msg) { notices.notify("Could not undo " + e.label + ": " + msg, true); sync.loadTeam() }
    if (e.changes) {
      var groups = Edit.groupUndo(e.changes), left = 0
      root.editSeq++
      e.changes.forEach(function(c) {
        var i = root.issueById(c.id)
        if (!i) return
        var patch = {}
        for (var k in c.input) {
          if (k === "assigneeId") patch.assignee = c.input[k] ? (root.memberById(c.input[k]) || i.assignee) : null
          else if (k === "parentId") continue
          else if (k === "projectMilestoneId") { patch.milestoneId = c.input[k] || ""; patch.milestoneName = (root.milestoneById(c.input[k]) || {}).name || "" }
          else patch[k] = c.input[k] === null ? (k === "estimate" ? null : "") : c.input[k]
        }
        root.issues = Issues.patchIssue(root.issues, c.id, patch)
        root.extraIssues = Issues.patchIssue(root.extraIssues, c.id, patch)
      })
      // A project change taken back: the issues return to (or leave) the board.
      root.takeBack(e.changes.map(function(c) { return c.id }))
      root.dropMisfits()
      // The open editor shows the values put back (and saves from them).
      var mine = e.changes.filter(function(c) { return c.id === ed.issueId })[0]
      var cur = mine ? root.issueById(ed.issueId) : null
      if (cur) issueOps.fillEditor(cur, "title" in mine.input || "description" in mine.input)
      groups.forEach(function(g) {
        for (var c = 0; c < g.ids.length; c += Linear.BATCH_SIZE) {
          left++
          root.gql(Linear.M_ISSUE_BATCH, { ids: g.ids.slice(c, c + Linear.BATCH_SIZE), input: g.input }, function(d) {
            d.issueBatchUpdate.issues.forEach(function(raw) { root.storeIssue(Linear.toIssue(raw)) })
            if (--left === 0) { notices.notify("Undone: " + e.label, false, root.icon.check); root.saveCache() }
          }, failed)
        }
      })
    } else if (e.restore) {
      root.gql(Linear.unarchiveDocument(e.restore.length), Linear.idVariables(e.restore), function() {
        notices.notify("Undone: " + e.label + " (restored)", false, root.icon.check)
        sync.loadTeam()
      }, function(msg) { notices.notify("Could not restore " + e.label + " (" + msg + "). Linear's archive or trash still has it.", true) })
    } else if (e.remove) {
      root.editSeq++
      root.issues = Issues.removeIssue(root.issues, e.remove)
      root.clampSelection()
      root.gql(Linear.M_ISSUE_DELETE, { id: e.remove }, function() { notices.notify("Undone: " + e.label + " (moved to Linear's trash)", false, root.icon.check); root.saveCache() }, failed)
    }
  }
}
