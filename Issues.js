.pragma library
.import "Dates.js" as Dates
.import "Linear.js" as Linear

// Issues on the board, worked out on this computer: columns, filters,
// search, sorting and grouping, moving cards, comments and history as
// shown, project codes and copying.
// Pure helpers, no QML or network, so tests run them with node.

// Shown when a team has hidden nothing yet: the same default as Linear's board.
var DEFAULT_HIDDEN_TYPES = ["canceled", "duplicate", "triage"]

// hidden: array of state ids, or null to use the default by type.
function isHidden(state, hidden) {
  if (Array.isArray(hidden)) return hidden.indexOf(state.id) >= 0
  return DEFAULT_HIDDEN_TYPES.indexOf(state.type) >= 0
}

function visibleStates(states, hidden) {
  return Linear.sortStates(states).filter(function(s) { return !isHidden(s, hidden) })
}

// The hidden list as explicit ids, for toggling one state from the default.
function hiddenIds(states, hidden) {
  if (Array.isArray(hidden)) return hidden.slice()
  return Linear.sortStates(states).filter(function(s) { return isHidden(s, null) }).map(function(s) { return s.id })
}

function toggleHidden(states, hidden, stateId) {
  var ids = hiddenIds(states, hidden)
  var i = ids.indexOf(stateId)
  if (i >= 0) ids.splice(i, 1)
  else ids.push(stateId)
  return ids
}

function byOrder(a, b) {
  return a.sortOrder - b.sortOrder
}

function issuesIn(issues, stateId) {
  return (issues || []).filter(function(i) { return i.stateId === stateId }).sort(byOrder)
}

// sortOrder that puts an issue at `index` of `column` (the column's issues
// in board order, without the moved issue).
function sortOrderAt(column, index) {
  if (!column.length) return 0
  if (index <= 0) return column[0].sortOrder - 1
  if (index >= column.length) return column[column.length - 1].sortOrder + 1
  return (column[index - 1].sortOrder + column[index].sortOrder) / 2
}

// Plan a move: returns { stateId, sortOrder } or null when nothing changes.
// `toIndex` counts positions in the target column including the moved issue.
function planMove(issues, issueId, toStateId, toIndex) {
  var issue = null
  for (var i = 0; i < issues.length; i++) if (issues[i].id === issueId) issue = issues[i]
  if (!issue) return null
  var column = issuesIn(issues, toStateId)
  var from = -1
  for (var k = 0; k < column.length; k++) if (column[k].id === issueId) from = k
  if (from >= 0) {
    if (toIndex === from || toIndex === from + 1) return null
    if (toIndex > from) toIndex--
    column.splice(from, 1)
  }
  if (toIndex === undefined || toIndex < 0 || toIndex > column.length) toIndex = column.length
  return { stateId: toStateId, sortOrder: sortOrderAt(column, toIndex) }
}

// Return a new issues array with one issue replaced (or patched).
function patchIssue(issues, issueId, patch) {
  return (issues || []).map(function(i) {
    if (i.id !== issueId) return i
    var next = {}
    for (var k in i) next[k] = i[k]
    for (var p in patch) next[p] = patch[p]
    return next
  })
}

function removeIssue(issues, issueId) {
  return (issues || []).filter(function(i) { return i.id !== issueId })
}

function upsertIssue(issues, issue) {
  var found = false
  var out = (issues || []).map(function(i) {
    if (i.id !== issue.id) return i
    found = true
    return issue
  })
  if (!found) out.push(issue)
  return out
}

function labelById(labels, id) {
  for (var i = 0; i < labels.length; i++) if (labels[i].id === id) return labels[i]
  return null
}

function issueMatches(issue, labels, query, labelFilter) {
  if (labelFilter && labelFilter.length) {
    for (var i = 0; i < labelFilter.length; i++) if (issue.labelIds.indexOf(labelFilter[i]) < 0) return false
  }
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  if (issue.title.toLowerCase().indexOf(q) >= 0) return true
  if (issue.identifier.toLowerCase().indexOf(q) >= 0) return true
  var prev = issue.previousIdentifiers || []
  for (var p = 0; p < prev.length; p++) if (prev[p].toLowerCase().indexOf(q) >= 0) return true
  if (issue.description.toLowerCase().indexOf(q) >= 0) return true
  if (issue.assignee && issue.assignee.name.toLowerCase().indexOf(q) >= 0) return true
  for (var j = 0; j < issue.labelIds.length; j++) {
    var l = labelById(labels, issue.labelIds[j])
    if (l && l.name.toLowerCase().indexOf(q) >= 0) return true
  }
  return false
}

// Assignee and priority filters. assignee: "" anyone, "me", "none", or a user id.
// priority: -1 any, otherwise a Linear priority number.
function passesFilters(issue, assignee, viewerId, priorityFilter) {
  if (assignee === "me") { if (!issue.assignee || issue.assignee.id !== viewerId) return false }
  else if (assignee === "none") { if (issue.assignee) return false }
  else if (assignee) { if (!issue.assignee || issue.assignee.id !== assignee) return false }
  if (typeof priorityFilter === "number" && priorityFilter >= 0 && issue.priority !== priorityFilter) return false
  return true
}

// Cycle filter: "" any, "none" no cycle, "current" the active cycle
// (activeId), or a cycle id.
function passesCycle(issue, cycleFilter, activeId) {
  if (!cycleFilter) return true
  if (cycleFilter === "none") return !issue.cycleId
  if (cycleFilter === "current") return !!activeId && issue.cycleId === activeId
  return issue.cycleId === cycleFilter
}

// Find a loaded issue by identifier ("eng-12" works too).
function issueByIdentifier(issues, text) {
  var t = String(text || "").trim().toUpperCase()
  if (!t) return null
  for (var i = 0; i < (issues || []).length; i++) {
    if (issues[i].identifier.toUpperCase() === t) return issues[i]
    var prev = issues[i].previousIdentifiers || []
    for (var j = 0; j < prev.length; j++) if (prev[j].toUpperCase() === t) return issues[i]
  }
  return null
}

// Sub-issues of `parentId` among the loaded issues.
function childrenOf(issues, parentId) {
  return (issues || []).filter(function(i) { return i.parent && i.parent.id === parentId })
}

// Issues matching what is typed in a "pick an issue" field: by identifier
// ("349" finds ENG-349) or by words of the title. Best matches first.
function suggestIssues(issues, text, excludeIds, limit) {
  var t = String(text || "").trim().toLowerCase()
  if (!t) return []
  var words = t.split(/\s+/)
  var skip = excludeIds || []
  var scored = []
  var seen = {}
  ;(issues || []).forEach(function(i) {
    if (!i || seen[i.id] || skip.indexOf(i.id) >= 0) return
    seen[i.id] = true
    var ident = i.identifier.toLowerCase(), title = i.title.toLowerCase()
    var num = ident.split("-").pop()
    var olds = (i.previousIdentifiers || []).map(function(x) { return x.toLowerCase() })
    var score = -1
    if (ident === t || num === t || olds.indexOf(t) >= 0) score = 0
    else if (ident.indexOf(t) === 0 || num.indexOf(t) === 0 || olds.some(function(o) { return o.indexOf(t) === 0 })) score = 1
    else if (words.every(function(w) { return title.indexOf(w) >= 0 })) score = title.indexOf(words[0]) === 0 ? 2 : 3
    if (score >= 0) scored.push({ issue: i, score: score })
  })
  scored.sort(function(a, b) { return a.score - b.score || (a.issue.updatedAt < b.issue.updatedAt ? 1 : -1) })
  return scored.slice(0, limit || 6).map(function(x) { return x.issue })
}

// "ENG-12", "eng-12" or a Linear link (https://linear.app/ws/issue/ENG-12/slug)
// → "ENG-12"; "" for anything else.
function parseIssueRef(text) {
  var t = String(text || "").trim()
  var m = /linear\.app\/[^\/\s]+\/issue\/([A-Za-z0-9]+-\d+)/.exec(t)
  if (m) return m[1].toUpperCase()
  m = /^([A-Za-z][A-Za-z0-9]{0,9}-\d+)$/.exec(t)
  return m ? m[1].toUpperCase() : ""
}

// Archived or deleted issues matching typed text: ID (also an old one) or
// words of the title, any order, any case.
function binMatches(issue, text) {
  var words = String(text || "").toLowerCase().split(/\s+/).filter(function(w) { return w })
  if (!words.length) return true
  var hay = [issue.identifier].concat(issue.previousIdentifiers || []).concat([issue.title, issue.projectName, issue.stateName]).join(" ").toLowerCase()
  return words.every(function(w) { return hay.indexOf(w) >= 0 })
}

// Items whose label (or keywords) contain every word of the query, best
// first: label starts with the query, then a word starts with it, then the rest.
function paletteFilter(items, query, limit) {
  var q = String(query || "").toLowerCase().trim()
  var words = q.split(/\s+/).filter(function(w) { return w })
  var scored = []
  ;(items || []).forEach(function(it, i) {
    var label = String(it.label || "").toLowerCase()
    var hay = label + " " + String(it.keywords || "").toLowerCase()
    if (!words.every(function(w) { return hay.indexOf(w) >= 0 })) return
    var score = !q ? 0 : (label.indexOf(q) === 0 ? 0 : ((" " + label).indexOf(" " + words[0]) >= 0 ? 1 : 2))
    scored.push({ item: it, score: score, i: i })
  })
  scored.sort(function(a, b) { return a.score - b.score || a.i - b.i })
  return scored.slice(0, limit || 50).map(function(s) { return s.item })
}

var SORTS = [
  { id: "manual", label: "Manual" }, { id: "priority", label: "Priority" }, { id: "due", label: "Due date" },
  { id: "updated", label: "Last updated" }, { id: "created", label: "Newest" }
]

var GROUPS = [
  { id: "none", label: "No grouping" }, { id: "assignee", label: "Assignee" }, { id: "priority", label: "Priority" },
  { id: "project", label: "Project" }, { id: "label", label: "First label" }
]

function priorityRank(p) { return p === 0 ? 5 : p }

function compareBy(sort) {
  if (sort === "priority") return function(a, b) { return priorityRank(a.priority) - priorityRank(b.priority) || a.sortOrder - b.sortOrder }
  if (sort === "due") return function(a, b) {
    if (a.dueDate === b.dueDate) return a.sortOrder - b.sortOrder
    if (!a.dueDate) return 1
    if (!b.dueDate) return -1
    return a.dueDate < b.dueDate ? -1 : 1
  }
  if (sort === "updated") return function(a, b) { return a.updatedAt < b.updatedAt ? 1 : (a.updatedAt > b.updatedAt ? -1 : 0) }
  if (sort === "created") return function(a, b) { return a.createdAt < b.createdAt ? 1 : (a.createdAt > b.createdAt ? -1 : 0) }
  return byOrder
}

// ctx: { labels, projects } for names. Returns { key, label, rank }.
function groupOf(issue, group, ctx) {
  if (group === "assignee") return issue.assignee
    ? { key: issue.assignee.id, label: issue.assignee.name, rank: issue.assignee.name.toLowerCase() }
    : { key: "", label: "Unassigned", rank: "\uffff" }
  if (group === "priority") return { key: String(issue.priority), label: Linear.priority(issue.priority).label, rank: String(priorityRank(issue.priority)) }
  if (group === "project") {
    var p = null
    ;(ctx.projects || []).forEach(function(x) { if (x.id === issue.projectId) p = x })
    return p ? { key: p.id, label: p.name, rank: p.name.toLowerCase() } : { key: "", label: "No project", rank: "\uffff" }
  }
  if (group === "label") {
    var names = issue.labelIds.map(function(id) { var l = labelById(ctx.labels || [], id); return l ? l.name : "" })
      .filter(function(n) { return n }).sort(function(a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1 })
    return names.length ? { key: names[0], label: names[0], rank: names[0].toLowerCase() } : { key: "", label: "No label", rank: "\uffff" }
  }
  return { key: "", label: "", rank: "" }
}

// A column's issues in view order: by group, then by the chosen sort.
function arrange(list, sort, group, ctx) {
  var cmp = compareBy(sort)
  var out = list.slice()
  if (!group || group === "none") return out.sort(cmp)
  var info = {}
  out.forEach(function(i) { info[i.id] = groupOf(i, group, ctx) })
  return out.sort(function(a, b) {
    var ga = info[a.id], gb = info[b.id]
    if (ga.rank !== gb.rank) return ga.rank < gb.rank ? -1 : 1
    return cmp(a, b)
  })
}

function closedAt(issue) { return issue ? (issue.completedAt || issue.canceledAt || "") : "" }

// Why an issue opened in the editor is not on the board, in a few words;
// "" when it is there. ctx: { teamId, teamName, projectId, projectName,
// doneWindow, hidden (state ids), shown (on the board, filters applied),
// filtered (passes the filters), now (Date) }.
function offBoardReason(issue, ctx) {
  if (!issue || ctx.shown) return ""
  var day = function(iso) { var d = new Date(iso); return Dates.MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear() }
  if (issue.trashed) return "In Linear's trash (G then X), not on the board."
  if (issue.archivedAt) return "Archived on " + day(issue.archivedAt) + ", so not on boards. Linear can restore it."
  if (ctx.teamId && issue.teamId && issue.teamId !== ctx.teamId) return "In team " + (issue.teamName || "another team") + "; the board shows " + (ctx.teamName || "another team") + "."
  if (ctx.projectId && issue.projectId !== ctx.projectId)
    return (issue.projectName ? "In project " + issue.projectName : "In no project") + "; the board shows " + (ctx.projectName || "one project") + " (O then P: All issues)."
  var closed = closedAt(issue)
  var isClosed = issue.stateType === "completed" || issue.stateType === "canceled" || issue.stateType === "duplicate"
  if (isClosed) {
    var w = Linear.doneWindow(ctx.doneWindow)
    var what = issue.stateType === "completed" ? "Done" : (issue.stateType === "duplicate" ? "Marked duplicate" : "Canceled")
    if (w.id === "none") return what + (closed ? " on " + day(closed) : "") + "; the board shows no done issues (V → Completed)."
    if (w.days !== null && closed && (ctx.now || new Date()).getTime() - new Date(closed).getTime() > w.days * 86400000)
      return what + " on " + day(closed) + "; the board shows done issues of the " + w.label.toLowerCase() + " (V → Completed: All shows every one)."
  }
  if ((ctx.hidden || []).indexOf(issue.stateId) >= 0) return "Its column " + (issue.stateName || "") + " is hidden on this board (Settings → Columns)."
  if (!ctx.filtered) return "Hidden by the board's filters (Alt+Shift+F clears them)."
  return "Not loaded on the board yet (Ctrl+R refreshes)."
}

function cycleLabel(cycle) {
  if (!cycle) return ""
  return (cycle.name ? cycle.name : "Cycle " + cycle.number) + (cycle.isActive ? " (current)" : "")
}

// Counts for the cycle view: done (completed/canceled), started, the rest.
function cycleStats(issues) {
  var s = { total: 0, done: 0, started: 0, todo: 0 }
  ;(issues || []).forEach(function(i) {
    s.total++
    var t = i.stateType || ""
    if (t === "completed" || t === "canceled" || t === "duplicate") s.done++
    else if (t === "started") s.started++
    else s.todo++
  })
  s.percent = s.total ? Math.round(s.done * 100 / s.total) : 0
  return s
}

function sortComments(list) {
  return (list || []).slice().sort(function(a, b) { return a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0) })
}

// Comments as threads: each top-level comment (oldest first) followed by its
// replies (oldest first), with depth 0 or 1. Replies whose parent is gone
// show as top-level.
function threadComments(list) {
  var sorted = sortComments(list), ids = {}, kids = {}, out = []
  sorted.forEach(function(c) { ids[c.id] = true })
  sorted.forEach(function(c) {
    if (c.parentId && ids[c.parentId]) (kids[c.parentId] = kids[c.parentId] || []).push(c)
  })
  sorted.forEach(function(c) {
    if (c.parentId && ids[c.parentId]) return
    out.push({ comment: c, depth: 0 })
    ;(kids[c.id] || []).forEach(function(k) { out.push({ comment: k, depth: 1 }) })
  })
  return out
}

// Reactions grouped by emoji: [{ emoji, count, mine (reaction id or ""), names }].
function reactionSummary(reactions, viewerId) {
  var by = {}, order = []
  ;(reactions || []).forEach(function(r) {
    var key = Linear.emojiName(r.emoji)
    if (!by[key]) { by[key] = { emoji: key, char: Linear.emojiChar(key), count: 0, mine: "", names: [] }; order.push(key) }
    var g = by[key]
    g.count++
    if (r.user) g.names.push(r.user)
    if (r.userId && r.userId === viewerId) g.mine = r.id
  })
  return order.map(function(e) { return by[e] })
}

function priorityName(v) { return typeof v === "number" ? Linear.priority(v).label : "" }

// One line describing an issue history entry, or "" for ones not worth showing.
function historyText(h) {
  var who = h.actor ? (h.actor.displayName || h.actor.name) : (h.botActor && h.botActor.name ? h.botActor.name : "Linear")
  var parts = []
  var name = function(x) { return x ? (x.displayName || x.name || "") : "" }
  var cyc = function(c) { return c ? (c.name || "Cycle " + c.number) : "" }
  if (h.fromState || h.toState) parts.push("moved " + (h.fromState ? "from " + h.fromState.name + " " : "") + "to " + (h.toState ? h.toState.name : "?"))
  if (h.fromAssignee || h.toAssignee) parts.push(h.toAssignee ? "assigned " + name(h.toAssignee) : "unassigned " + name(h.fromAssignee))
  if (typeof h.toPriority === "number" && h.toPriority !== h.fromPriority) parts.push("set priority " + priorityName(h.toPriority))
  if (h.toTitle && h.fromTitle) parts.push("renamed to “" + h.toTitle + "”")
  if (h.addedLabels && h.addedLabels.length) parts.push("added " + h.addedLabels.map(function(l) { return l.name }).join(", "))
  if (h.removedLabels && h.removedLabels.length) parts.push("removed " + h.removedLabels.map(function(l) { return l.name }).join(", "))
  if (h.toDueDate !== undefined && h.toDueDate !== h.fromDueDate && (h.toDueDate || h.fromDueDate)) parts.push(h.toDueDate ? "set due " + h.toDueDate : "removed due date")
  if (h.toEstimate !== undefined && h.toEstimate !== h.fromEstimate && (h.toEstimate !== null || h.fromEstimate !== null)) parts.push(h.toEstimate !== null ? "estimated " + h.toEstimate : "removed estimate")
  if (h.fromProject || h.toProject) parts.push(h.toProject ? "moved to project " + h.toProject.name : "removed from project " + h.fromProject.name)
  if (h.fromCycle || h.toCycle) parts.push(h.toCycle ? "added to " + cyc(h.toCycle) : "removed from " + cyc(h.fromCycle))
  if (h.fromParent || h.toParent) parts.push(h.toParent ? "made sub-issue of " + h.toParent.identifier : "removed parent " + h.fromParent.identifier)
  if (h.updatedDescription) parts.push("edited the description")
  if (h.relationChanges && h.relationChanges.length) parts.push("changed relations (" + h.relationChanges.map(function(r) { return r.identifier }).join(", ") + ")")
  if (h.archived) parts.push("archived")
  if (h.trashed) parts.push("deleted")
  if (h.autoClosed) parts.push("auto-closed")
  if (!parts.length) return ""
  return who + " " + parts.join(", ")
}

// Readable name of where an attachment comes from (Sentry, GitHub…).
function sourceLabel(source, url) {
  var s = String(source || "").toLowerCase()
  var known = { sentry: "Sentry", github: "GitHub", gitlab: "GitLab", slack: "Slack", figma: "Figma", zendesk: "Zendesk", intercom: "Intercom", front: "Front" }
  for (var k in known) if (s.indexOf(k) >= 0) return known[k]
  var m = String(url || "").match(/^https?:\/\/([^\/]+)/)
  return m ? m[1].replace(/^www\./, "") : "Link"
}

// A short code for a project (Linear has none; issue ids carry the team key):
// the one set in the board's settings, else made from the name. "API" stays
// "API", "web-app" -> "WEB-APP", "Über new web app" -> "ÜNWA".
function projectCode(project, overrides) {
  if (!project) return ""
  var own = overrides && overrides[project.id]
  if (own) return String(own).toUpperCase()
  var name = String(project.name || "").trim()
  if (!name) return ""
  if (name.length <= 8 && !/\s/.test(name)) return name.toUpperCase()
  var words = name.split(/[\s_\-.]+/).filter(function(w) { return w.length })
  if (words.length > 1) return words.slice(0, 4).map(function(w) { return w[0] }).join("").toUpperCase()
  return name.slice(0, 4).toUpperCase()
}

// What the copy shortcuts put on the clipboard. kind: id | branch | url | markdown | title
function copyText(issue, kind) {
  if (!issue) return ""
  if (kind === "branch") return issue.branchName || ""
  if (kind === "url") return issue.url || ""
  if (kind === "markdown") return "[" + issue.identifier + " " + issue.title + "](" + issue.url + ")"
  if (kind === "title") return issue.identifier + " " + issue.title
  return issue.identifier || ""
}

var COPY_KINDS = [
  { id: "id", label: "ID", keys: "Ctrl+." },
  { id: "branch", label: "Git branch", keys: "Ctrl+Shift+." },
  { id: "url", label: "Link", keys: "Ctrl+Shift+," },
  { id: "markdown", label: "Markdown link", keys: "Ctrl+Alt+," },
  { id: "title", label: "ID + title", keys: "Ctrl+Alt+." }
]

function nextColor(hex) {
  var i = Linear.COLORS.indexOf(String(hex || "").toLowerCase())
  return Linear.COLORS[(i + 1) % Linear.COLORS.length]
}
