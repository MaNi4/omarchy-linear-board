.pragma library
.import "Dates.js" as Dates

// Changes to issues and cycles: what an edit in the editor sends to Linear,
// what it changes on the board right away, and what puts it back (undo).
// The field names are the ones Linear's inputs use (stateId, labelIds…);
// tests/api.test.js checks what these build against Linear's schema.
// Pure helpers, no QML or network, so tests run them with node.

// ---- issue editor ----

// The same ids, in any order.
function sameSet(a, b) {
  a = a || []; b = b || []
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (b.indexOf(a[i]) < 0) return false
  return true
}

// What the editor shows now, compared with the issue as last saved (orig),
// for one kind of change: "text" (title, description) or "props" (the rest,
// due date included). Only fields that changed are sent, so what someone
// else changed meanwhile in other fields stays.
//   v: { title, description, stateId, priority, labelIds, projectId,
//        assigneeId, due (as typed), estimate, cycleId, parent ({ id… } or
//        null), milestoneId (only one of the chosen project) }
//   ctx: { member(id) → assignee as the board keeps it, milestoneName(id) }
// Returns { input (for issueUpdate), patch (for the board's copy),
// titleMissing (an empty title is not saved; Linear needs one) }.
// A due date still being typed (not a date yet) waits.
function issueChanges(orig, v, kind, ctx) {
  var o = orig, input = {}, patch = {}, titleMissing = false
  ctx = ctx || {}
  var set = function(field, value, local, localValue) {
    input[field] = value
    patch[local || field] = local ? localValue : value
  }
  if (kind === "text") {
    var title = String(v.title || "").trim()
    if (!title) titleMissing = true
    else if (title !== o.title) set("title", title)
    if (String(v.description || "") !== o.description) set("description", String(v.description || ""))
    return { input: input, patch: patch, titleMissing: titleMissing }
  }
  var parentId = v.parent ? v.parent.id : ""
  if (v.stateId !== o.stateId) set("stateId", v.stateId)
  if (v.priority !== o.priority) set("priority", v.priority)
  if (!sameSet(v.labelIds, o.labelIds)) set("labelIds", (v.labelIds || []).slice())
  if ((v.projectId || "") !== (o.projectId || "")) set("projectId", v.projectId || null, "projectId", v.projectId || "")
  if ((v.assigneeId || "") !== (o.assignee ? o.assignee.id : ""))
    set("assigneeId", v.assigneeId || null, "assignee", v.assigneeId ? ((ctx.member && ctx.member(v.assigneeId)) || o.assignee) : null)
  var due = Dates.parseDate(v.due)
  if (due !== null && due !== (o.dueDate || "")) set("dueDate", due || null, "dueDate", due)
  if (v.estimate !== o.estimate) set("estimate", v.estimate)
  if ((v.cycleId || "") !== (o.cycleId || "")) set("cycleId", v.cycleId || null, "cycleId", v.cycleId || "")
  if (parentId !== (o.parent ? o.parent.id : "")) set("parentId", parentId || null, "parent", v.parent || null)
  // A milestone belongs to its project: a new project without one drops it
  // (Linear does that itself, so it is not sent).
  var ms = v.milestoneId || "", projectChanged = input.projectId !== undefined
  if (ms !== (o.milestoneId || "") && !(projectChanged && !ms)) {
    input.projectMilestoneId = ms || null
    patch.milestoneId = ms
    patch.milestoneName = ms ? (ctx.milestoneName && ctx.milestoneName(ms)) || "" : ""
  } else if (projectChanged && !ms && o.milestoneId) { patch.milestoneId = ""; patch.milestoneName = "" }
  return { input: input, patch: patch, titleMissing: false }
}

// The input that creates a new issue from the editor (same v as above, plus
// teamId). { input } or { error: "title" | "due" } for what needs fixing.
function createInput(v) {
  var title = String(v.title || "").trim()
  if (!title) return { error: "title" }
  var due = Dates.parseDate(v.due)
  if (due === null) return { error: "due" }
  var input = { teamId: v.teamId, title: title, description: String(v.description || ""), stateId: v.stateId,
    priority: v.priority || 0, labelIds: (v.labelIds || []).slice() }
  if (v.projectId) input.projectId = v.projectId
  if (v.assigneeId) input.assigneeId = v.assigneeId
  if (due) input.dueDate = due
  if (typeof v.estimate === "number") input.estimate = v.estimate
  if (v.cycleId) input.cycleId = v.cycleId
  if (v.parent && v.parent.id) input.parentId = v.parent.id
  if (v.milestoneId) input.projectMilestoneId = v.milestoneId
  return { input: input }
}

// How toasts and messages name the fields of an input.
var FIELD_LABELS = { title: "title", description: "description", stateId: "status", priority: "priority",
  labelIds: "labels", projectId: "project", assigneeId: "assignee", dueDate: "due date", estimate: "estimate",
  cycleId: "cycle", parentId: "parent", projectMilestoneId: "milestone" }
function fieldNames(input) {
  var out = []
  for (var k in input) if (FIELD_LABELS[k] && out.indexOf(FIELD_LABELS[k]) < 0) out.push(FIELD_LABELS[k])
  return out.join(", ")
}

// Two edits of one issue sent as one (offline, typing): later values win.
function mergeInput(first, later) {
  var out = {}
  for (var a in first || {}) out[a] = first[a]
  for (var b in later || {}) out[b] = later[b]
  return out
}

// Offline outbox: can a change join the last waiting one? Only updates of
// the same issue (typing while offline), and not while the last one is
// already being sent. `updateQuery` is Linear.M_ISSUE_UPDATE.
function outboxJoins(last, query, variables, flushing, updateQuery) {
  return !!(last && !flushing && query === updateQuery && last.query === query
    && last.variables && variables && last.variables.id === variables.id
    && last.variables.input && variables.input)
}

// ---- cycles ----

// A cycle date typed as YYYY-MM-DD (already parsed): same time of day as
// before, on the new day (local time). Returns an ISO string or "".
function moveToDay(iso, day) {
  var m = String(day || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  var d = iso ? new Date(iso) : new Date(+m[1], +m[2] - 1, +m[3])
  if (isNaN(d.getTime())) return ""
  d.setFullYear(+m[1], +m[2] - 1, +m[3])
  return d.toISOString()
}

// Checks a cycle edit. Returns { input } or { error }.
function cycleInput(cycle, name, startDay, endDay, description) {
  var input = {}
  name = String(name || "").trim()
  if (name !== (cycle.name || "")) input.name = name
  description = String(description || "").trim()
  if (description !== (cycle.description || "").trim()) input.description = description
  var starts = cycle.startsAt, ends = cycle.endsAt
  if (startDay && startDay !== Dates.isoDate(new Date(cycle.startsAt))) {
    starts = moveToDay(cycle.startsAt, startDay)
    if (!starts) return { error: "Start should look like 2026-10-31 or 31.10.2026" }
    input.startsAt = starts
  }
  if (endDay && endDay !== Dates.isoDate(new Date(cycle.endsAt))) {
    ends = moveToDay(cycle.endsAt, endDay)
    if (!ends) return { error: "End should look like 2026-10-31 or 31.10.2026" }
    input.endsAt = ends
  }
  if (new Date(ends).getTime() <= new Date(starts).getTime()) return { error: "The cycle has to end after it starts." }
  return { input: input }
}

// ---- undo ----

// The update that puts back what `input` is about to change on `issue`.
function undoInput(issue, input) {
  var out = {}
  for (var k in input) {
    if (k === "stateId") out.stateId = issue.stateId
    else if (k === "sortOrder") out.sortOrder = issue.sortOrder
    else if (k === "priority") out.priority = issue.priority
    else if (k === "assigneeId") out.assigneeId = issue.assignee ? issue.assignee.id : null
    else if (k === "projectId") out.projectId = issue.projectId || null
    else if (k === "cycleId") out.cycleId = issue.cycleId || null
    else if (k === "estimate") out.estimate = issue.estimate
    else if (k === "dueDate") out.dueDate = issue.dueDate || null
    else if (k === "labelIds" || k === "addedLabelIds" || k === "removedLabelIds") out.labelIds = issue.labelIds.slice()
    else if (k === "title") out.title = issue.title
    else if (k === "description") out.description = issue.description
    else if (k === "parentId") out.parentId = issue.parent ? issue.parent.id : null
    else if (k === "projectMilestoneId") out.projectMilestoneId = issue.milestoneId || null
  }
  return out
}

// [{ id, input }] → [{ ids, input }]: issues that go back to the same values
// share one batch update.
function groupUndo(changes) {
  var by = {}, order = []
  ;(changes || []).forEach(function(c) {
    var key = JSON.stringify(c.input)
    if (!by[key]) { by[key] = { ids: [], input: c.input }; order.push(key) }
    by[key].ids.push(c.id)
  })
  return order.map(function(k) { return by[k] })
}

// One undo step grown by more changes ([{ id, input }]): for a field already
// in the step the older value stays, since undo goes back to before the
// first edit. Returns the new list.
function mergeUndo(changes, more) {
  var out = (changes || []).map(function(c) { return { id: c.id, input: mergeInput(c.input, {}) } })
  ;(more || []).forEach(function(c) {
    var have = null
    for (var i = 0; i < out.length; i++) if (out[i].id === c.id) have = out[i]
    if (!have) { out.push({ id: c.id, input: mergeInput(c.input, {}) }); return }
    for (var k in c.input) if (!(k in have.input)) have.input[k] = c.input[k]
  })
  return out
}
