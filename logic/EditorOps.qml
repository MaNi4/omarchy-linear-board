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
import "../Markdown.js" as Markdown

// The issue editor: saving, templates, comments, reactions, relations, links and autocomplete.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `editorOps`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: editorOps
  visible: false

  // ---- duplicate / templates ----
  readonly property var edTemplates: Linear.issueTemplates(root.templates, ed.team.id)
  readonly property var edTemplatesAll: Linear.issueTemplates(root.templates, root.team ? root.team.id : "")

  function duplicateIssue() {
    var v = { title: editor.titleField.text, description: editor.descField.text, stateId: ed.stateId, priority: ed.priority,
      labels: ed.labels.slice(), projectId: ed.projectId, assigneeId: ed.assigneeId, estimate: ed.estimate,
      cycleId: ed.cycleId, parent: ed.parentIssue, milestoneId: ed.milestoneValid }
    pickers.closeDialog()
    issueOps.newIssue(Math.max(0, root.columnOfState(v.stateId)), v.parent)
    editor.titleField.text = v.title
    editor.descField.text = v.description
    ed.stateId = v.stateId
    ed.priority = v.priority
    ed.labels = v.labels
    ed.projectId = v.projectId
    ed.assigneeId = v.assigneeId
    ed.estimate = v.estimate
    ed.cycleId = v.cycleId
    ed.milestoneId = v.milestoneId
    notices.notify("Copy of the issue: change what you need and create it")
  }

  function applyTemplate(t) {
    var d = t.data || {}
    if (d.title) editor.titleField.text = d.title
    if (d.description) { editor.descField.text = d.description; ed.descPreview = false }
    if (typeof d.priority === "number") ed.priority = d.priority
    if (Array.isArray(d.labelIds)) ed.labels = d.labelIds.filter(function(id) { return ed.team.labels.some(function(l) { return l.id === id }) })
    if (d.stateId && ed.team.states.some(function(x) { return x.id === d.stateId })) ed.stateId = d.stateId
    if (d.projectId && ed.team.projects.some(function(x) { return x.id === d.projectId })) ed.projectId = d.projectId
    if (d.assigneeId) ed.assigneeId = d.assigneeId
    if (typeof d.estimate === "number") ed.estimate = d.estimate
    notices.notify("Template “" + t.name + "” applied")
  }

  function saveAsTemplate() {
    var name = editor.titleField.text.trim()
    if (!name) { notices.notify("Give the issue a title first; it becomes the template's name.", true); return }
    var data = Linear.templateDataFrom({ title: name, description: editor.descField.text, priority: ed.priority, labelIds: ed.labels,
      stateId: ed.stateId, projectId: ed.projectId, assigneeId: ed.assigneeId, estimate: ed.estimate })
    root.gql(Linear.M_TEMPLATE_CREATE, { input: { type: "issue", name: name, teamId: ed.team.id, templateData: data } }, function(d) {
      root.templates = root.templates.concat([d.templateCreate.template])
      notices.notify("Saved template “" + name + "” (also in Linear)")
    }, function(msg) { notices.notify("Could not save the template: " + msg, true) })
  }

  function deleteTemplate(t) {
    pickers.ask("Delete the template “" + t.name + "” in Linear?", "Delete", function() {
      root.templates = root.templates.filter(function(x) { return x.id !== t.id })
      root.gql(Linear.M_TEMPLATE_DELETE, { id: t.id }, null, function(msg) { notices.notify("Could not delete: " + msg, true) })
    })
  }

  // ---- saving ----
  // A new issue is created with Create (Ctrl+Enter). A saved issue saves
  // itself like in Linear: a property change goes to Linear at once (with
  // a toast to undo it), the title and description while you type. Only
  // fields that changed are sent, so edits someone else made to other
  // fields in the meantime are kept.

  // Set while the editor is filled from an issue, so that is not a change.
  property bool applying: false
  // Title and description typed in one go: one undo step, one toast when
  // the field is left. { id, identifier, key, fields: { title, description } }
  property var textSession: null

  Timer { id: propTimer; interval: 500; onTriggered: editorOps.saveChanges("props") }
  Timer { id: textTimer; interval: 500; onTriggered: editorOps.saveChanges("text") }

  // For the editor's footer: "" | waiting (a change about to go) | saving | saved | offline | error.
  property int inFlight: 0
  property bool savedHere: false       // something of this issue was saved since it opened
  property bool failedHere: false
  readonly property string saveStatus: propTimer.running || textTimer.running ? "waiting"
    : editorOps.inFlight > 0 ? (sync.outbox.length ? "offline" : "saving")
    : editorOps.failedHere ? "error" : editorOps.savedHere ? "saved" : ""

  function scheduleProps() { if (ed.orig && ed.issueId && !editorOps.applying) propTimer.restart() }
  function scheduleText() { if (ed.orig && ed.issueId && !editorOps.applying) textTimer.restart() }

  Connections {
    target: ed
    function onStateIdChanged() { editorOps.scheduleProps() }
    function onPriorityChanged() { editorOps.scheduleProps() }
    function onLabelsChanged() { editorOps.scheduleProps() }
    function onProjectIdChanged() { editorOps.scheduleProps() }
    function onAssigneeIdChanged() { editorOps.scheduleProps() }
    function onEstimateChanged() { editorOps.scheduleProps() }
    function onCycleIdChanged() { editorOps.scheduleProps() }
    function onParentIssueChanged() { editorOps.scheduleProps() }
    function onMilestoneIdChanged() { editorOps.scheduleProps() }
  }
  Connections { target: editor.dueField; function onTextChanged() { editorOps.scheduleProps() } }
  Connections {
    target: editor.titleField
    function onTextChanged() { editorOps.scheduleText() }
    function onActiveFocusChanged() { if (!editor.titleField.activeFocus) editorOps.endText() }
  }
  Connections {
    target: editor.descField
    function onTextChanged() { editorOps.scheduleText() }
    function onActiveFocusChanged() { if (!editor.descField.activeFocus) editorOps.endText() }
  }

  // Send whatever is still waiting (before the editor closes or shows another issue).
  function flush() {
    if (propTimer.running) { propTimer.stop(); editorOps.saveChanges("props") }
    editorOps.endText()
  }

  // The title or description field was left: save it now and say so.
  function endText() {
    if (textTimer.running) textTimer.stop()
    editorOps.saveChanges("text")
    // Typing again later is a new undo step. Like Linear, text saves without
    // a toast; the footer says Saved, and Ctrl+Z (outside the field) undoes it.
    editorOps.textSession = null
  }

  // What the editor shows now, as Edit.js takes it.
  function values() {
    return { teamId: ed.team.id, title: editor.titleField.text, description: editor.descField.text, stateId: ed.stateId,
      priority: ed.priority, labelIds: ed.labels, projectId: ed.projectId, assigneeId: ed.assigneeId, due: editor.dueField.text,
      estimate: ed.estimate, cycleId: ed.cycleId, parent: ed.parentIssue, milestoneId: ed.milestoneValid }
  }

  // kind: "props" (status, labels… and the due date) or "text" (title, description).
  function saveChanges(kind) {
    var o = ed.orig
    if (!o || !ed.issueId || o.id !== ed.issueId) return
    // What changed and what to send: Edit.issueChanges (tested in tests/).
    var c = Edit.issueChanges(o, editorOps.values(), kind, {
      member: function(id) { return root.memberById(id) },
      milestoneName: function(id) { return (root.milestoneById(id) || {}).name || "" }
    })
    if (c.titleMissing) ed.titleError = true
    var input = c.input, patch = c.patch
    if (Object.keys(input).length === 0) return

    var id = o.id
    if (input.stateId) {
      input.sortOrder = Issues.sortOrderAt(Issues.issuesIn(root.issues, input.stateId), 0)
      patch.sortOrder = input.sortOrder
    }
    var changes = [{ id: id, input: Edit.undoInput(o, input) }]
    var undoKey
    if (kind === "text") {
      var t = editorOps.textSession
      if (t && t.id === id && undoer.extendUndo(t.key, changes)) undoKey = t.key
      else {
        undoKey = undoer.pushUndo({ label: "edit of " + o.identifier, changes: changes })
        t = { id: id, identifier: o.identifier, key: undoKey, fields: {} }
      }
      for (var f in input) if (f !== "sortOrder") t.fields[f] = true
      editorOps.textSession = t
    } else {
      undoKey = undoer.pushUndo({ label: "change of " + o.identifier, changes: changes })
      undoer.notifyUndo("Saved " + Edit.fieldNames(input) + " of " + o.identifier, undoKey)
    }

    root.editSeq++
    var follow = {}
    if (input.title !== undefined) follow.title = input.title
    if (input.projectId !== undefined) follow.projectId = ed.projectId || ""
    if (input.projectMilestoneId !== undefined || input.projectId !== undefined) follow.milestoneId = ed.milestoneValid || ""
    if (Object.keys(follow).length) issueOps.followRecurring(o, follow)
    var before = root.issues
    var beforeExtra = root.extraIssues
    root.issues = Issues.patchIssue(root.issues, id, patch)
    if (!root.onBoard(id)) root.extraIssues = Issues.patchIssue(root.extraIssues, id, patch)
    root.dropMisfits()
    // What the editor compares with from now on.
    ed.orig = Issues.patchIssue([o], id, patch)[0]
    editorOps.inFlight++
    editorOps.failedHere = false
    var mine = function() { return ed.issueId === id }
    sync.send("Save " + o.identifier, Linear.M_ISSUE_UPDATE, { id: id, input: input }, function(data) {
      editorOps.inFlight = Math.max(0, editorOps.inFlight - 1)
      if (mine()) editorOps.savedHere = true
      root.storeIssue(Linear.toIssue(data.issueUpdate.issue))
      root.saveCache()
    }, function(msg) {
      editorOps.inFlight = Math.max(0, editorOps.inFlight - 1)
      if (mine()) editorOps.failedHere = true
      root.issues = before
      root.extraIssues = beforeExtra
      undoer.dropUndo(undoKey)
      if (editorOps.textSession && editorOps.textSession.key === undoKey) editorOps.textSession = null
      // Back to what Linear has; typed text stays in the field, to try again.
      if (ed.issueId === id) {
        if (kind === "props") issueOps.fillEditor(o, false)
        else ed.orig = o
      }
      notices.notify("Could not save " + Edit.fieldNames(input) + " of " + o.identifier + ": " + msg, true)
    })
  }

  // Ctrl+Enter or the button: a new issue is created; a saved one sends
  // what is still waiting and closes. False when something needs fixing first.
  function saveIssue() {
    var made = Edit.createInput(editorOps.values())
    if (made.error === "title") { ed.titleError = true; editor.titleField.forceActiveFocus(); return false }
    if (made.error === "due") {
      ed.dueError = true
      editor.dueField.forceActiveFocus()
      notices.notify("Due date should look like 2026-10-31 or 31.10.2026", true)
      return false
    }
    var o = ed.orig

    if (!o) {
      if (ed.teamLoading) { notices.notify("Still loading the team, a moment…"); return false }
      var otherTeam = !!ed.teamData
      var teamName = ed.team.name
      var create = made.input
      root.editSeq++
      sync.send("New issue “" + create.title + "”", Linear.M_ISSUE_CREATE, { input: create }, function(data) {
        var issue = Linear.toIssue(data.issueCreate.issue)
        var ck = undoer.pushUndo({ label: "creating " + issue.identifier, remove: issue.id })
        if (otherTeam) { undoer.notifyUndo("Created " + issue.identifier + " in " + teamName, ck); return }
        if (!root.fitsBoard(issue)) {
          var proj = root.projectById(issue.projectId)
          undoer.notifyUndo("Created " + issue.identifier + " in " + (proj ? proj.name : "no project"), ck)
          return
        }
        root.issues = Issues.upsertIssue(root.issues, issue)
        root.selectIssue(issue.id)
        undoer.notifyUndo("Created " + issue.identifier, ck)
        root.saveCache()
      }, function(msg) { notices.notify("Could not create the issue: " + msg, true) })
      var again = ed.createMore ? { teamData: ed.teamData, stateId: create.stateId, projectId: create.projectId || "",
        labels: create.labelIds.slice(), assigneeId: create.assigneeId || "", parent: ed.parentIssue,
        priority: ed.priority, estimate: ed.estimate, cycleId: ed.cycleId || "",
        milestoneId: ed.milestoneId || "", due: editor.dueField.text } : null
      pickers.closeDialog()
      if (again) editorOps.createAnother(again)
      return true
    }

    pickers.closeDialog()
    return true
  }

  // ---- checklists: a click on a box in the rendered text ticks it ----
  // In a saved issue's description it is saved to Linear at once (like
  // Linear does), unless the description has other edits not sent yet:
  // then it goes along with them a moment later.
  function toggleDescTask(line) {
    var before = editor.descField.text
    var text = Markdown.toggleTask(before, line)
    if (text === before) return
    editor.descField.text = text
    var o = ed.orig
    if (!ed.issueId || !o || before !== o.description) return
    var id = o.id
    var setOrig = function(desc) {
      if (ed.issueId !== id || !ed.orig) return
      var n = {}
      for (var k in ed.orig) n[k] = ed.orig[k]
      n.description = desc
      ed.orig = n
    }
    var patchLocal = function(desc) {
      root.issues = Issues.patchIssue(root.issues, id, { description: desc })
      root.extraIssues = Issues.patchIssue(root.extraIssues, id, { description: desc })
    }
    setOrig(text)
    patchLocal(text)
    root.editSeq++
    sync.send("Checklist in " + o.identifier, Linear.M_ISSUE_UPDATE, { id: id, input: { description: text } }, function(d) {
      root.storeIssue(Linear.toIssue(d.issueUpdate.issue))
      root.saveCache()
    }, function(msg) {
      // Put it back only when nothing else changed the text since.
      if (ed.issueId === id && editor.descField.text === text) { editor.descField.text = before; setOrig(before) }
      patchLocal(before)
      notices.notify("Could not save the checklist: " + msg, true)
    })
  }

  // Your own comment: saved at once. A comment being written: just its text.
  function toggleCommentTask(c, line) {
    var body = Markdown.toggleTask(c.body, line)
    if (body === c.body) return
    var swap = function(b) {
      ed.comments = ed.comments.map(function(x) {
        if (x.id !== c.id) return x
        var n = {}
        for (var k in x) n[k] = x[k]
        n.body = b
        return n
      })
    }
    swap(body)
    root.gql(Linear.M_COMMENT_UPDATE, { id: c.id, input: { body: body } }, function(d) {
      var updated = Linear.toComment(d.commentUpdate.comment)
      ed.comments = ed.comments.map(function(x) { return x.id === c.id ? updated : x })
    }, function(msg) { swap(c.body); notices.notify("Could not save the checklist: " + msg, true) })
  }

  function toggleDraftTask(field, line) {
    var text = Markdown.toggleTask(field.text, line)
    if (text !== field.text) field.text = text
  }

  // Typing help for checklists and lists in a Markdown field, like Linear:
  // "[]" or "[ ]" then Space starts a checklist item, Enter continues the
  // list (Enter in an empty item ends it). True when the key was used.
  function markdownKey(field, event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
    if (field.selectedText) return false
    var change = null
    if (event.key === Qt.Key_Space) change = Markdown.taskShortcut(field.text, field.cursorPosition)
    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier))
      change = Markdown.listEnter(field.text, field.cursorPosition)
    if (!change) return false
    if (change.end > change.start) field.remove(change.start, change.end)
    if (change.text) field.insert(change.start, change.text)
    field.cursorPosition = change.start + change.text.length
    return true
  }

  // "Create more": a fresh new issue with the same team, status, project,
  // labels, assignee and parent, ready for the next title.
  function createAnother(k) {
    var col = root.columnOfState(k.stateId)
    issueOps.newIssue(col >= 0 ? col : root.selCol, k.parent)
    // Another team's lists are already loaded: keep them, no reload.
    if (k.teamData) ed.teamData = k.teamData
    ed.stateId = k.stateId
    ed.projectId = k.projectId
    ed.labels = k.labels
    ed.assigneeId = k.assigneeId
    ed.priority = k.priority
    ed.estimate = k.estimate
    ed.cycleId = k.cycleId
    ed.milestoneId = k.milestoneId
    editor.dueField.text = k.due
  }

  // Leave the editor for another issue, saving this one first.
  function saveAndEdit(id, url) {
    if (!editorOps.saveIssue()) return
    root.openIssueAnywhere(id, url)
  }

  function addSubIssue() {
    var parent = { id: ed.issueId, identifier: ed.identifier, title: editor.titleField.text.trim() }
    if (editorOps.saveIssue()) issueOps.newIssue(root.columnOfState(ed.stateId) >= 0 ? root.columnOfState(ed.stateId) : root.selCol, parent)
  }

  // Parent from text like ENG-12: a loaded issue, or looked up in Linear.
  function setParentFromText(text) {
    var t = String(text || "").trim()
    if (!t) return
    var use = function(issue) {
      if (issue.id === ed.issueId) { notices.notify("An issue cannot be its own parent.", true); return }
      ed.parentIssue = { id: issue.id, identifier: issue.identifier, title: issue.title }
      editor.parentField.text = ""
      editorOps.clearSuggest()
    }
    var found = Issues.issueByIdentifier(root.issues.concat(root.extraIssues), t)
    if (found) { use(found); return }
    var seq = ed.seq
    root.gql(Linear.Q_ISSUE_REF, { id: t.toUpperCase() }, function(d) {
      if (seq !== ed.seq) return
      if (d.issue) use(d.issue)
      else notices.notify("No issue " + t + " in Linear.", true)
    }, function() { if (seq === ed.seq) notices.notify("No issue " + t + " in Linear.", true) })
  }

  function postComment() {
    var body = editor.commentField.text.trim()
    if (!body || !ed.issueId || ed.posting) return
    var seq = ed.seq
    ed.posting = true
    if (ed.editingCommentId) {
      var cid = ed.editingCommentId
      var oldBody = (ed.comments.filter(function(x) { return x.id === cid })[0] || {}).body
      var editIssueId = ed.issueId
      root.gql(Linear.M_COMMENT_UPDATE, { id: cid, input: { body: body } }, function(d) {
        ed.posting = false
        if (oldBody !== undefined) {
          var key = undoer.pushUndo({ label: "the comment edit", run: function(ok, fail) {
            root.gql(Linear.M_COMMENT_UPDATE, { id: cid, input: { body: oldBody } }, function() { ok(); editorOps.reloadComments(editIssueId) }, fail)
          } })
          undoer.notifyUndo("Comment saved", key)
        }
        if (seq !== ed.seq) return
        var updated = Linear.toComment(d.commentUpdate.comment)
        ed.comments = ed.comments.map(function(c) { return c.id === cid ? updated : c })
        ed.editingCommentId = ""
        editor.commentField.text = ""
      }, function(msg) { ed.posting = false; notices.notify("Could not save the comment: " + msg, true) })
      return
    }
    var input = { issueId: ed.issueId, body: body }
    if (ed.replyTo) input.parentId = ed.replyTo.id
    var postIssueId = ed.issueId
    sync.send("Comment", Linear.M_COMMENT_CREATE, { input: input }, function(d) {
      ed.posting = false
      var newId = d.commentCreate.comment.id
      var key = undoer.pushUndo({ label: "the comment", run: function(ok, fail) {
        root.gql(Linear.M_COMMENT_DELETE, { id: newId }, function() {
          ok()
          if (ed.issueId === postIssueId) ed.comments = ed.comments.filter(function(x) { return x.id !== newId })
        }, fail)
      } })
      undoer.notifyUndo("Comment added", key)
      if (seq !== ed.seq) return
      ed.comments = ed.comments.concat([Linear.toComment(d.commentCreate.comment)])
      editor.commentField.text = ""
      ed.commentPreview = false
      ed.replyTo = null
      Qt.callLater(function() { editor.editorFlick.contentY = Math.max(0, editor.editorFlick.contentHeight - editor.editorFlick.height) })
    }, function(msg) { ed.posting = false; notices.notify("Could not add the comment: " + msg, true) })
  }

  // Reply in a comment's thread (Linear threads are one level deep, so a
  // reply to a reply joins the same thread).
  function replyTo(c) {
    var top = c.parentId || c.id
    var head = ed.comments.filter(function(x) { return x.id === top })[0] || c
    ed.replyTo = { id: top, author: head.author }
    ed.editingCommentId = ""
    editor.commentField.forceActiveFocus()
    Qt.callLater(function() { editor.editorFlick.contentY = Math.max(0, editor.editorFlick.contentHeight - editor.editorFlick.height) })
  }

  function patchComment(id, f) {
    ed.comments = ed.comments.map(function(c) {
      if (c.id !== id) return c
      var n = {}
      for (var k in c) n[k] = c[k]
      f(n)
      return n
    })
  }

  // Add your reaction, or take it back when it is there already.
  function toggleReaction(c, emoji) {
    ed.reactFor = ""
    if (!root.viewer) return
    var name = Linear.emojiName(emoji)
    var mine = (c.reactions || []).filter(function(r) { return r.emoji === name && r.userId === root.viewer.id })[0]
    if (mine) {
      editorOps.patchComment(c.id, function(n) { n.reactions = n.reactions.filter(function(r) { return r.id !== mine.id }) })
      root.gql(Linear.M_REACTION_DELETE, { id: mine.id }, null, function(msg) { notices.notify("Could not remove the reaction: " + msg, true) })
      return
    }
    var tmp = { id: "tmp-" + Date.now(), emoji: name, userId: root.viewer.id, user: root.viewer.displayName || root.viewer.name }
    editorOps.patchComment(c.id, function(n) { n.reactions = (n.reactions || []).concat([tmp]) })
    root.gql(Linear.M_REACTION_CREATE, { input: { commentId: c.id, emoji: emoji } }, function(d) {
      var r = d.reactionCreate.reaction
      editorOps.patchComment(c.id, function(n) { n.reactions = n.reactions.map(function(x) { return x.id === tmp.id ? { id: r.id, emoji: Linear.emojiName(r.emoji), userId: root.viewer.id, user: tmp.user } : x }) })
    }, function(msg) {
      editorOps.patchComment(c.id, function(n) { n.reactions = n.reactions.filter(function(x) { return x.id !== tmp.id }) })
      notices.notify("Could not react: " + msg, true)
    })
  }

  // Reaction on the issue itself (like the ones under comments).
  function toggleIssueReaction(emoji) {
    ed.issueReactShown = false
    if (!root.viewer || !ed.issueId) return
    var id = ed.issueId, seq = ed.seq
    var name = Linear.emojiName(emoji)
    var mine = ed.reactions.filter(function(r) { return r.emoji === name && r.userId === root.viewer.id })[0]
    if (mine) {
      ed.reactions = ed.reactions.filter(function(r) { return r.id !== mine.id })
      root.gql(Linear.M_REACTION_DELETE, { id: mine.id }, null, function(msg) { notices.notify("Could not remove the reaction: " + msg, true) })
      return
    }
    var tmp = { id: "tmp-" + Date.now(), emoji: name, userId: root.viewer.id, user: root.viewer.displayName || root.viewer.name }
    ed.reactions = ed.reactions.concat([tmp])
    root.gql(Linear.M_REACTION_CREATE, { input: { issueId: id, emoji: emoji } }, function(d) {
      if (seq !== ed.seq) return
      var r = d.reactionCreate.reaction
      ed.reactions = ed.reactions.map(function(x) { return x.id === tmp.id ? { id: r.id, emoji: Linear.emojiName(r.emoji), userId: root.viewer.id, user: tmp.user } : x })
    }, function(msg) {
      if (seq === ed.seq) ed.reactions = ed.reactions.filter(function(x) { return x.id !== tmp.id })
      notices.notify("Could not react: " + msg, true)
    })
  }

  // ---- relations / attachments / history / comment edits (saved issues) ----
  function reloadComments(issueId) {
    if (ed.issueId !== issueId) return
    var seq = ed.seq
    sync.gqlAll(Linear.Q_COMMENTS, { id: issueId }, function(d) { return d.issue ? d.issue.comments : null }, function(nodes) {
      if (seq === ed.seq) ed.comments = Issues.sortComments(nodes.map(Linear.toComment))
    }, function() {})
  }
  function reloadRelations() {
    var seq = ed.seq, id = ed.issueId
    root.gql(Linear.Q_RELATIONS, { id: id }, function(d) { if (seq === ed.seq) ed.relations = Linear.toRelations(d.issue) })
  }

  // Refresh one issue after Linear changed it on its own (marking a duplicate
  // moves it to the Duplicate column).
  function refetchIssue(id) {
    root.gql(Linear.Q_ISSUE, { id: id }, function(d) {
      var issue = Linear.toIssue(d.issue)
      if (!issue) return
      root.storeIssue(issue)
      if (ed.issueId === id && ed.orig) {
        ed.orig = issue
        ed.stateId = issue.stateId
      }
    })
  }

  function createRelation(other) {
    var thisId = ed.issueId, seq = ed.seq, kind = ed.relKind
    if (!other || !thisId) return
    if (other.id === thisId) { notices.notify("An issue cannot relate to itself.", true); return }
    root.gql(Linear.M_RELATION_CREATE, { input: Linear.relationInput(kind, thisId, other.id) }, function(d) {
      var relId = d.issueRelationCreate.issueRelation ? d.issueRelationCreate.issueRelation.id : ""
      if (relId) {
        var key = undoer.pushUndo({ label: "relation to " + other.identifier, run: function(ok, fail) {
          root.gql(Linear.M_RELATION_DELETE, { id: relId }, function() { ok(); if (ed.issueId === thisId) editorOps.reloadRelations() }, fail)
        } })
        undoer.notifyUndo("Relation to " + other.identifier + " added", key)
      }
      if (seq !== ed.seq) return
      editor.relationField.text = ""
      editorOps.clearSuggest()
      editorOps.reloadRelations()
      if (kind === "duplicate") editorOps.refetchIssue(thisId)
    }, function(msg) { notices.notify("Could not add the relation: " + msg, true) })
  }

  function addRelation(text) {
    var t = String(text || "").trim()
    if (!t || !ed.issueId) return
    var create = editorOps.createRelation
    var found = Issues.issueByIdentifier(root.issues.concat(root.extraIssues), t)
    if (found) { create(found); return }
    root.gql(Linear.Q_ISSUE_REF, { id: t.toUpperCase() }, function(d) {
      if (d.issue) create(d.issue)
      else notices.notify("No issue " + t + " in Linear.", true)
    }, function() { notices.notify("No issue " + t + " in Linear.", true) })
  }

  // ---- issue autocomplete (relation and parent fields) ----
  function updateSuggest(kind, text) {
    ed.suggestFor = kind
    if (text !== ed.suggestText) ed.suggestRemote = []
    ed.suggestText = text
    editorOps.recomputeSuggest()
    ed.suggestCursor = 0
    if (String(text).trim().length >= 3) suggestTimer.restart()
  }

  function recomputeSuggest() {
    if (!ed.suggestFor || !ed.suggestText.trim()) { ed.suggestItems = []; return }
    ed.suggestItems = Issues.suggestIssues(root.issues.concat(root.extraIssues, ed.suggestRemote),
      ed.suggestText, ed.issueId ? [ed.issueId] : [], 6)
  }

  function clearSuggest() {
    ed.suggestFor = ""
    ed.suggestText = ""
    ed.suggestItems = []
    ed.suggestRemote = []
  }

  // Also ask Linear, for issues that are not on the board (old, done, other projects).
  Timer {
    id: suggestTimer
    interval: 300
    onTriggered: {
      var text = ed.suggestText.trim()
      if (!text || !root.team) return
      root.gql(Linear.Q_SEARCH, { term: text }, function(d) {
        if (ed.suggestText.trim() !== text) return
        ed.suggestRemote = d.searchIssues.nodes.map(Linear.toIssue)
        editorOps.recomputeSuggest()
      }, function() {})
    }
  }

  function pickSuggestion(issue) {
    if (!issue) return
    var kind = ed.suggestFor
    if (!root.onBoard(issue.id)) root.extraIssues = Issues.upsertIssue(root.extraIssues, issue)
    if (kind === "relation") editorOps.createRelation(issue)
    else if (kind === "time") {
      timeTracker.reportIssue = issue
      timeDialog.timeIssueField.text = issue.identifier + "  " + issue.title
      editorOps.clearSuggest()
    }
    else if (kind === "parent") {
      ed.parentIssue = { id: issue.id, identifier: issue.identifier, title: issue.title }
      editor.parentField.text = ""
      editorOps.clearSuggest()
    }
  }

  // Keys shared by both fields; returns true when handled.
  function suggestKey(event, kind, field) {
    var open = ed.suggestFor === kind && ed.suggestItems.length > 0
    if (event.key === Qt.Key_Down && open) { ed.suggestCursor = Math.min(ed.suggestItems.length - 1, ed.suggestCursor + 1); return true }
    if (event.key === Qt.Key_Up && open) { ed.suggestCursor = Math.max(0, ed.suggestCursor - 1); return true }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) && open) {
      editorOps.pickSuggestion(ed.suggestItems[ed.suggestCursor])
      return true
    }
    if (event.key === Qt.Key_Escape && (open || field.text)) { field.text = ""; editorOps.clearSuggest(); return true }
    return false
  }

  function removeRelation(rel) {
    var thisId = ed.issueId
    ed.relations = ed.relations.filter(function(r) { return r.id !== rel.id })
    root.gql(Linear.M_RELATION_DELETE, { id: rel.id }, function() {
      var key = undoer.pushUndo({ label: "removing the relation to " + rel.issue.identifier, run: function(ok, fail) {
        root.gql(Linear.M_RELATION_CREATE, { input: Linear.relationRestoreInput(rel, thisId) }, function() { ok(); if (ed.issueId === thisId) editorOps.reloadRelations() }, fail)
      } })
      undoer.notifyUndo("Relation to " + rel.issue.identifier + " removed", key)
    }, function(msg) { notices.notify("Could not remove: " + msg, true); editorOps.reloadRelations() })
  }

  function addLink(text) {
    var url = String(text || "").trim()
    if (!url || !ed.issueId) return
    if (!/^https?:\/\//.test(url)) url = "https://" + url
    var seq = ed.seq
    root.gql(Linear.M_ATTACH_URL, { issueId: ed.issueId, url: url }, function(d) {
      if (seq !== ed.seq) return
      editor.linkField.text = ""
      ed.attachments = ed.attachments.concat([Linear.toAttachment(d.attachmentLinkURL.attachment)])
    }, function(msg) { notices.notify("Could not add the link: " + msg, true) })
  }

  function removeAttachment(a) {
    pickers.ask("Remove the link “" + a.title + "” from this issue?", "Remove", function() {
      ed.attachments = ed.attachments.filter(function(x) { return x.id !== a.id })
      root.gql(Linear.M_ATTACHMENT_DELETE, { id: a.id }, null, function(msg) { notices.notify("Could not remove: " + msg, true) })
    })
  }

  function showHistory() {
    if (ed.historyShown) { ed.historyShown = false; return }
    ed.historyShown = true
    if (ed.history.length || !ed.issueId) return
    var seq = ed.seq
    ed.historyLoading = true
    sync.gqlAll(Linear.Q_HISTORY, { id: ed.issueId }, function(d) { return d.issue ? d.issue.history : null }, function(nodes) {
      if (seq !== ed.seq) return
      ed.historyLoading = false
      ed.history = nodes.map(function(h) { return { text: Issues.historyText(h), createdAt: h.createdAt } })
        .filter(function(h) { return h.text }).sort(function(a, b) { return a.createdAt < b.createdAt ? 1 : -1 })
    }, function(msg) { ed.historyLoading = false; notices.notify(msg, true) }, 5)
  }

  function startEditComment(c) {
    ed.editingCommentId = c.id
    editor.commentField.text = c.body
    editor.commentField.forceActiveFocus()
    editor.commentField.cursorPosition = editor.commentField.text.length
  }

  function cancelEditComment() {
    ed.editingCommentId = ""
    editor.commentField.text = ""
  }

  function deleteComment(c) {
    pickers.ask("Delete this comment?", "Delete", function() {
      var issueId = ed.issueId
      ed.comments = ed.comments.filter(function(x) { return x.id !== c.id })
      root.gql(Linear.M_COMMENT_DELETE, { id: c.id }, function() {
        // Linear cannot restore a deleted comment: undo posts it again (as new).
        var key = undoer.pushUndo({ label: "deleting the comment", run: function(ok, fail) {
          var input = { issueId: issueId, body: c.body }
          if (c.parentId) input.parentId = c.parentId
          root.gql(Linear.M_COMMENT_CREATE, { input: input }, function() { ok(); editorOps.reloadComments(issueId) }, fail)
        } })
        undoer.notifyUndo("Comment deleted", key)
      }, function(msg) { notices.notify("Could not delete the comment: " + msg, true); editorOps.reloadComments(issueId) })
    })
  }

  // While typing "@name" in a comment, offer team members; picking one puts
  // their Linear profile link there, which Linear shows as a mention.
  function updateMention() {
    ed.mention = Markdown.mentionQuery(editor.commentField.text, editor.commentField.cursorPosition)
  }

  function insertMention(member) {
    var st = ed.mention
    if (!st || !member) return
    var t = editor.commentField.text
    var end = st.start + 1 + st.query.length
    editor.commentField.text = t.slice(0, st.start) + member.url + " " + t.slice(end)
    editor.commentField.cursorPosition = st.start + member.url.length + 1
    ed.mention = null
    editor.commentField.forceActiveFocus()
  }

  function setDue(days) {
    editor.dueField.text = days === null ? "" : Dates.isoDate(Dates.addDays(new Date(), days))
    ed.dueError = false
  }

  function deleteIssue(id) {
    var issue = root.issueById(id)
    if (!issue) return
    pickers.ask("Delete " + issue.identifier + " “" + issue.title + "”? It goes to Linear's trash.", "Delete", function() {
      var before = root.issues
      var undoKey = undoer.pushUndo({ label: "deleting " + issue.identifier, restore: [id] })
      root.editSeq++
      root.issues = Issues.removeIssue(root.issues, id)
      root.clampSelection()
      if (root.dialog === "issue") pickers.closeDialog()
      sync.send("Delete issue", Linear.M_ISSUE_DELETE, { id: id }, function() { undoer.notifyUndo("Deleted " + issue.identifier, undoKey); root.saveCache() },
        function(msg) { root.issues = before; undoer.dropUndo(undoKey); notices.notify("Could not delete: " + msg, true) })
    })
  }

  // Links come from issue text anyone in the team can write: only web and
  // mail links are opened, never file:// or anything xdg-open could take
  // for an option.
  function openInLinear(url) {
    if (!Markdown.openable(url)) { if (url) notices.notify("Not opened (only http, https and mailto links): " + url, true); return }
    Quickshell.execDetached(["xdg-open", url])
  }
}
