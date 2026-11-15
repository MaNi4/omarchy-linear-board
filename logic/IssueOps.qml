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
import "../Markdown.js" as Markdown
import "../Recur.js" as Recur

// Moving and creating issues, opening the editor, reminders and recurring issues.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `issueOps`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: issueOps
  visible: false

  // ---- issue actions -----------------------------------------------------------------------
  function moveIssue(id, stateId, toIndex) {
    var plan = Issues.planMove(root.issues, id, stateId, toIndex)
    if (!plan) return
    var before = root.issues
    var orig = root.issueById(id)
    var undoKey = undoer.pushUndo({ label: "move of " + (orig ? orig.identifier : "the issue"), changes: undoer.undoChanges([id], plan) })
    root.editSeq++
    root.issues = Issues.patchIssue(root.issues, id, plan)
    root.selectIssue(id)
    var toState = root.stateById(stateId)
    if (orig && plan.stateId !== orig.stateId) undoer.notifyUndo("Moved " + orig.identifier + " to " + (toState ? toState.name : "another column"), undoKey)
    sync.send("Move issue", Linear.M_ISSUE_UPDATE, { id: id, input: plan }, function(data) {
      root.issues = Issues.upsertIssue(root.issues, Linear.toIssue(data.issueUpdate.issue))
      root.saveCache()
    }, function(msg) {
      root.issues = before
      undoer.dropUndo(undoKey)
      notices.notify("Could not move the issue: " + msg, true)
    })
  }

  // Keyboard move: one column left/right, keeping roughly the same height.
  function shiftSelected(dc, di) {
    var picked = bulk.actionIds()
    if (dc !== 0 && picked.length > 1) { issueOps.shiftPicked(picked, dc); return }
    var issue = root.selectedIssue
    if (!issue) return
    root.cursorShown = true
    if (dc !== 0) {
      var c = root.selCol + dc
      if (c < 0 || c >= root.columns.length) return
      var target = root.visibleByColumn[c]
      var idx = Math.min(root.selIdx, target.length)
      var full = Issues.issuesIn(root.issues, root.columns[c].id)
      var real = idx < target.length ? full.map(function(i) { return i.id }).indexOf(target[idx].id) : full.length
      issueOps.moveIssue(issue.id, root.columns[c].id, real)
    } else {
      if (!root.manualOrder) { notices.notify("Reordering works with manual sort (v → Sort: Manual)."); return }
      var col = root.visibleByColumn[root.selCol]
      var j = root.selIdx + di
      if (j < 0 || j >= col.length) return
      var all = Issues.issuesIn(root.issues, issue.stateId).map(function(i) { return i.id })
      var to = all.indexOf(col[j].id)
      issueOps.moveIssue(issue.id, issue.stateId, di > 0 ? to + 1 : to)
    }
  }

  // Shift+←/→ with picked cards: each one goes one column over from its own
  // column, to the end of it, in board order. One undo step for all of them.
  function shiftPicked(ids, dc) {
    var colOf = {}
    root.columns.forEach(function(c, n) { colOf[c.id] = n })
    var plans = {}, targets = {}, moved = []
    root.issues.slice().sort(Issues.byOrder).forEach(function(i) {
      if (ids.indexOf(i.id) < 0 || colOf[i.stateId] === undefined) return
      var to = root.columns[colOf[i.stateId] + dc]
      if (!to) return   // already in the first/last column
      if (!targets[to.id]) targets[to.id] = Issues.issuesIn(root.issues, to.id)
      plans[i.id] = { stateId: to.id, sortOrder: Issues.sortOrderAt(targets[to.id], targets[to.id].length) }
      targets[to.id].push({ id: i.id, sortOrder: plans[i.id].sortOrder })
      moved.push(i.id)
    })
    if (!moved.length) return
    root.cursorShown = true
    var before = root.issues
    var cursorId = root.selectedIssue ? root.selectedIssue.id : ""
    var changes = []
    moved.forEach(function(id) { changes = changes.concat(undoer.undoChanges([id], plans[id])) })
    var undoKey = undoer.pushUndo({ label: "move of " + moved.length + " issues", changes: changes })
    root.editSeq++
    moved.forEach(function(id) { root.issues = Issues.patchIssue(root.issues, id, plans[id]) })
    if (cursorId) root.selectIssue(cursorId)
    undoer.notifyUndo("Moved " + moved.length + " issues", undoKey)
    var failed = false
    moved.forEach(function(id) {
      sync.send("Move issue", Linear.M_ISSUE_UPDATE, { id: id, input: plans[id] }, function(data) {
        root.issues = Issues.upsertIssue(root.issues, Linear.toIssue(data.issueUpdate.issue))
        root.saveCache()
      }, function(msg) {
        if (failed) return
        failed = true
        root.issues = before
        undoer.dropUndo(undoKey)
        notices.notify("Could not move the issues: " + msg, true)
        sync.loadTeam()
      })
    })
  }

  // parent: optional { id, identifier, title } for a new sub-issue.
  function newIssue(colIndex, parent) {
    if (!root.team) return
    if (root.dialog === "issue") editorOps.flush()
    var col = root.columns[colIndex] || root.columns[0] || root.states[0]
    ed.seq++
    ed.issueId = ""
    ed.orig = null
    ed.identifier = ""
    ed.url = ""
    editor.titleField.text = ""
    editor.descField.text = ""
    ed.stateId = col ? col.id : ""
    ed.priority = 0
    ed.labels = root.labelFilter.slice()
    ed.projectId = parent ? ((root.issueById(parent.id) || {}).projectId || root.config.projectId) : root.config.projectId
    ed.assigneeId = root.viewer ? root.viewer.id : ""
    editor.dueField.text = ""
    ed.estimate = null
    ed.cycleId = ""
    ed.parentIssue = parent || null
    ed.milestoneId = ""
    issueOps.resetEditorExtras()
    root.dialog = "issue"
    Qt.callLater(function() { editor.titleField.forceActiveFocus() })
  }

  // Fill the editor from a saved issue; that is not a change to save.
  // withText: the title and description too.
  function fillEditor(issue, withText) {
    editorOps.applying = true
    ed.issueId = issue.id
    ed.orig = issue
    ed.identifier = issue.identifier
    ed.url = issue.url
    if (withText) {
      editor.titleField.text = issue.title
      editor.descField.text = issue.description
    }
    ed.stateId = issue.stateId
    ed.priority = issue.priority
    ed.labels = issue.labelIds.slice()
    ed.projectId = issue.projectId
    ed.assigneeId = issue.assignee ? issue.assignee.id : ""
    editor.dueField.text = issue.dueDate
    ed.estimate = issue.estimate
    ed.cycleId = issue.cycleId
    ed.parentIssue = issue.parent
    ed.milestoneId = issue.milestoneId || ""
    editorOps.applying = false
  }

  function editIssue(id) {
    var issue = root.issueById(id)
    if (!issue) return
    if (root.dialog === "issue") editorOps.flush()
    root.selectIssue(id)
    ed.seq++
    editorOps.savedHere = false
    editorOps.failedHere = false
    issueOps.fillEditor(issue, true)
    issueOps.resetEditorExtras()
    root.dialog = "issue"
    issueOps.loadDetail(issue.id)
    // Like Linear: the board's keys (S, P, A…) work at once; R renames, E edits the description.
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  // Description: rendered preview ⇄ editing.
  function toggleDescPreview() {
    if (ed.descPreview) { ed.descPreview = false; Qt.callLater(function() { editor.descField.forceActiveFocus() }) }
    else if (editor.descField.text.trim()) { ed.descPreview = true; keyScope.forceActiveFocus() }
  }

  function resetEditorExtras() {
    ed.teamData = null
    ed.teamLoading = false
    ed.teamSeq++
    ed.titleError = false
    ed.dueError = false
    ed.comments = []
    ed.subIssues = []
    ed.relations = []
    ed.attachments = []
    ed.history = []
    ed.historyShown = false
    ed.extra = ""
    ed.commentPreview = false
    ed.reactions = []
    ed.issueReactShown = false
    ed.replyTo = null
    ed.reactFor = ""
    ed.editingCommentId = ""
    ed.mention = null
    editorOps.clearSuggest()
    editor.edTimeField.text = ""
    editor.edTimeNote.text = ""
    editor.edTimeDate.text = root.today
    ed.descPreview = !!ed.issueId && editor.descField.text.trim() !== ""
    ed.detailLoading = false
    editor.newLabelField.text = ""
    editor.parentField.text = ""
    editor.commentField.text = ""
    editor.editorFlick.contentY = 0
  }

  // Comments and sub-issues of the issue in the editor.
  function loadDetail(id) {
    var seq = ed.seq
    ed.detailLoading = true
    var left = 5
    var done = function() { if (--left === 0 && seq === ed.seq) ed.detailLoading = false }
    root.gql(Linear.Q_ISSUE_REACTIONS, { id: id }, function(d) {
      if (seq === ed.seq && d.issue) ed.reactions = Linear.toReactions(d.issue.reactions)
      done()
    }, function() { done() })
    root.gql(Linear.Q_RELATIONS, { id: id }, function(d) {
      if (seq === ed.seq) ed.relations = Linear.toRelations(d.issue)
      done()
    }, function(msg) { if (seq === ed.seq) notices.notify(msg, true); done() })
    root.gql(Linear.Q_ATTACHMENTS, { id: id }, function(d) {
      if (seq === ed.seq && d.issue) ed.attachments = d.issue.attachments.nodes.map(Linear.toAttachment)
      done()
    }, function(msg) { if (seq === ed.seq) notices.notify(msg, true); done() })
    var fail = function(msg) { if (seq === ed.seq) { ed.detailLoading = false; notices.notify(msg, true) } }
    sync.gqlAll(Linear.Q_COMMENTS, { id: id }, function(d) { return d.issue ? d.issue.comments : null }, function(nodes) {
      if (seq === ed.seq) ed.comments = Issues.sortComments(nodes.map(Linear.toComment))
      done()
    }, fail)
    sync.gqlAll(Linear.Q_CHILDREN, { id: id }, function(d) { return d.issue ? d.issue.children : null }, function(nodes) {
      if (seq === ed.seq) ed.subIssues = nodes.map(function(c) {
        return { id: c.id, identifier: c.identifier, title: c.title, url: c.url || "",
          stateName: c.state ? c.state.name : "", stateColor: c.state ? c.state.color : "#888888",
          done: !!(c.state && (c.state.type === "completed" || c.state.type === "canceled")) }
      })
      done()
    }, fail)
  }

  // Point the new-issue editor at another team: load its columns, labels,
  // projects, members and cycles, and reset the choices that belong to a team.
  function setEdTeam(teamId) {
    if (ed.issueId || teamId === ed.team.id) return
    var seq = ++ed.teamSeq
    var resetChoices = function() {
      var st = Linear.sortStates(ed.team.states)
      var start = st.filter(function(x) { return x.type === "unstarted" })[0] || st.filter(function(x) { return x.type === "backlog" })[0] || st[0]
      ed.stateId = start ? start.id : ""
      ed.labels = []
      ed.projectId = ""
      ed.cycleId = ""
      ed.estimate = null
      if (ed.assigneeId && !ed.team.members.some(function(m) { return m.id === ed.assigneeId })) ed.assigneeId = ""
    }
    if (root.team && teamId === root.team.id) { ed.teamData = null; resetChoices(); return }
    ed.teamLoading = true
    var got = {}, left = 7, failed = false
    var fail = function(msg) { if (seq === ed.teamSeq && !failed) { failed = true; ed.teamLoading = false; notices.notify(msg, true) } }
    var take = function(key) {
      return function(v) {
        got[key] = v
        if (--left !== 0 || seq !== ed.teamSeq || failed) return
        var t = got.team
        var est = { estimationType: t.issueEstimationType, estimationAllowZero: t.issueEstimationAllowZero, estimationExtended: t.issueEstimationExtended }
        ed.teamData = { id: t.id, key: t.key, name: t.name, states: Linear.sortStates(got.states),
          labels: Linear.mergeLabels(got.labels, got.wsLabels), projects: got.projects.map(Linear.toProject),
          members: Linear.toMembers(got.members, root.viewer ? root.viewer.id : ""), cycles: Linear.toCycles(got.cycles),
          estimateOptions: Linear.estimateOptions(est) }
        ed.teamLoading = false
        resetChoices()
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
  }

  // ---- reminders (Linear's "Remind me") ----
  function remindIssues(ids, option) {
    ids = (ids || []).filter(function(id) { return id })
    if (!ids.length) return
    var at = Dates.reminderAt(option, new Date())
    var vars = Linear.idVariables(ids)
    vars.at = at.toISOString()
    var when = Qt.formatDateTime(at, "ddd d MMM HH:mm")
    root.gql(Linear.reminderDocument(ids.length), vars, function() {
      notices.notify("Reminder set for " + when + ": Linear's inbox will remind you", false, root.icon.check)
    }, function(msg) { notices.notify("Could not set the reminder: " + msg, true) })
  }

  // ---- recurring issues ----
  // Linear's own recurring issues cannot be made through its API, so the board
  // keeps the rules (config.recurring) and creates each copy on its day,
  // checking every minute while the shell runs. Before creating, it asks
  // Linear whether an issue with that title was created that day already, so
  // two computers with the same rules do not both create it.
  function makeRecurring(every) {
    var title = editor.titleField.text.trim()
    if (!title) { notices.notify("Give the issue a title first.", true); return }
    var st = ed.team.states.filter(function(x) { return x.id === ed.stateId })[0]
    if (!st || st.type === "completed" || st.type === "canceled" || st.type === "duplicate")
      st = ed.team.states.filter(function(x) { return x.type === "unstarted" })[0] || ed.team.states.filter(function(x) { return x.type === "backlog" })[0] || st
    var rule = { id: String(Date.now()), issueId: ed.issueId || "", teamId: ed.team.id, teamName: ed.team.name, title: title, description: editor.descField.text,
      priority: ed.priority, labelIds: ed.labels.slice(), projectId: ed.projectId || "", milestoneId: ed.milestoneValid,
      assigneeId: ed.assigneeId || "", estimate: ed.estimate, stateId: st ? st.id : "", every: every,
      start: Recur.recurStart(every, root.today), last: "" }
    root.setConfig({ recurring: (root.config.recurring || []).concat([rule]) })
    ed.extra = ""
    notices.notify(Recur.recurLabel(every) + ": the next copy of “" + title + "” is made on " + rule.start + " (Settings → Recurring)", false, root.icon.check)
  }

  // Open a repeat rule's issue: its newest open one (the copy to work on),
  // else the newest on the board, else the one it was made from, else ask Linear.
  function openRecurring(rule) {
    var series = root.issues.concat(root.extraIssues).filter(function(i) { return Recur.inRecurSeries(rule, i) })
    series.sort(function(a, b) { return String(b.createdAt).localeCompare(String(a.createdAt)) })
    var open = series.filter(function(i) { return i.stateType !== "completed" && i.stateType !== "canceled" })
    var pick = open[0] || series[0]
    if (pick) { root.openIssueAnywhere(pick.id, pick.url); return }
    if (rule.issueId) { root.openIssueAnywhere(rule.issueId, ""); return }
    root.gql(Linear.Q_RECUR_LATEST, { filter: { team: { id: { eq: rule.teamId } }, title: { eq: rule.title },
      project: rule.projectId ? { id: { eq: rule.projectId } } : { null: true } } }, function(d) {
      var n = d.issues.nodes[0]
      if (n) root.openIssueAnywhere(n.id, n.url)
      else notices.notify("No issue “" + rule.title + "” in Linear yet.", true)
    }, function(msg) { notices.notify(msg, true) })
  }

  // A repeating issue was renamed or moved to another project: its rule
  // follows it (it is matched by title and project), and from now on it
  // is tied to this issue. fields: { title?, projectId?, milestoneId? }
  function followRecurring(issue, fields) {
    var rule = Recur.recurRuleFor(root.config.recurring, issue)
    if (!rule) return
    root.setConfig({ recurring: (root.config.recurring || []).map(function(r) {
      if (r.id !== rule.id) return r
      var n = {}
      for (var k in r) n[k] = r[k]
      for (var f in fields) n[f] = fields[f]
      n.issueId = issue.id
      return n
    }) })
  }

  function deleteRecurring(id) {
    root.setConfig({ recurring: (root.config.recurring || []).filter(function(r) { return r.id !== id }) })
  }

  property bool recurBusy: false
  // Rules take the current title and project of their issues (renamed or
  // moved in Linear too). From the issues the board knows, or with fetch
  // from Linear; done() runs after either way.
  function recurFromKnown() {
    var rules = root.config.recurring || [], sources = {}
    if (!rules.length) return
    root.issues.concat(root.extraIssues).forEach(function(i) {
      sources[i.id] = { title: i.title, projectId: i.projectId, milestoneId: i.milestoneId || "" }
    })
    var next = Recur.recurFollow(rules, sources)
    if (next) root.setConfig({ recurring: next })
  }
  function refreshRecurring(done) {
    var ids = (root.config.recurring || []).map(function(r) { return r.issueId }).filter(function(id) { return !!id })
    if (!ids.length || !root.apiKey) { if (done) done(); return }
    root.gql(Linear.Q_RECUR_SOURCES, { ids: ids }, function(d) {
      var sources = {}
      d.issues.nodes.forEach(function(n) {
        sources[n.id] = { title: n.title, projectId: n.project ? n.project.id : "", milestoneId: n.projectMilestone ? n.projectMilestone.id : "" }
      })
      var next = Recur.recurFollow(root.config.recurring || [], sources)
      if (next) root.setConfig({ recurring: next })
      if (done) done()
    }, function() { if (done) done() })
  }
  Connections {
    target: root
    function onIssuesChanged() { issueOps.recurFromKnown() }
    function onSettingsTabChanged() { if (root.settingsTab === "recurring") issueOps.refreshRecurring() }
    function onDialogChanged() { if (root.dialog === "settings" && root.settingsTab === "recurring") issueOps.refreshRecurring() }
  }

  property double recurCheckedAt: 0
  function runRecurring() {
    if (!root.apiKey || !root.viewer || issueOps.recurBusy) return
    // Renames made in Linear reach the rules within 10 minutes.
    if (Date.now() - issueOps.recurCheckedAt > 10 * 60 * 1000) { issueOps.recurCheckedAt = Date.now(); issueOps.refreshRecurring() }
    var today = Dates.isoDate(new Date())
    var rules = root.config.recurring || []
    var rule = null, due = ""
    for (var i = 0; i < rules.length && !rule; i++) { var d = Recur.recurDue(rules[i], today); if (d) { rule = rules[i]; due = d } }
    if (!rule) return
    issueOps.recurBusy = true
    // A copy is due: first take the source issue's current title and project.
    if (!issueOps.recurFresh) {
      issueOps.refreshRecurring(function() { issueOps.recurFresh = true; issueOps.recurBusy = false; issueOps.runRecurring() })
      return
    }
    issueOps.recurFresh = false
    var mark = function() {
      root.setConfig({ recurring: (root.config.recurring || []).map(function(r) {
        if (r.id !== rule.id) return r
        var n = {}
        for (var k in r) n[k] = r[k]
        n.last = due
        return n
      }) })
    }
    var finish = function() { issueOps.recurBusy = false; Qt.callLater(issueOps.runRecurring) }
    // Leave it due: it is tried again next minute. A rule Linear keeps
    // refusing (deleted team or project) is reported once a day at most.
    var refused = function(msg) {
      issueOps.recurBusy = false
      if (issueOps.recurWarned !== rule.id + due) { issueOps.recurWarned = rule.id + due; notices.notify("Could not create the recurring issue “" + rule.title + "”: " + msg, true) }
    }
    root.gql(Linear.Q_RECUR_EXISTS, { filter: Linear.recurExistsFilter(rule, due) }, function(d) {
      if (d.issues.nodes.length) { mark(); finish(); return }
      var input = { id: Recur.recurIssueId(rule.id, due), teamId: rule.teamId, title: rule.title,
        description: Markdown.untickTasks(rule.description || ""), priority: rule.priority || 0, labelIds: rule.labelIds || [] }
      if (rule.stateId) input.stateId = rule.stateId
      if (rule.projectId) input.projectId = rule.projectId
      if (rule.milestoneId) input.projectMilestoneId = rule.milestoneId
      if (rule.assigneeId) input.assigneeId = rule.assigneeId
      if (typeof rule.estimate === "number") input.estimate = rule.estimate
      root.gql(Linear.M_ISSUE_CREATE, { input: input }, function(r) {
        mark()
        var issue = Linear.toIssue(r.issueCreate.issue)
        if (root.team && issue.teamId === root.team.id && (!root.config.projectId || issue.projectId === root.config.projectId))
          root.issues = Issues.upsertIssue(root.issues, issue)
        notices.notify("Recurring issue created: " + issue.identifier + " " + issue.title)
        finish()
      }, function(msg) {
        // Another computer made this copy at the same moment (same id): done.
        root.gql(Linear.Q_ISSUE_REF, { id: input.id }, function(d) {
          if (d.issue) { mark(); finish(); return }
          refused(msg)
        }, function() { refused(msg) })
      })
    }, function() { issueOps.recurBusy = false })
  }
  property string recurWarned: ""
  property bool recurFresh: false
}
