// Run: node tests/api.test.js [path/to/schema.graphql]
// Checks every request the board sends against Linear's current API, so a
// change on Linear's side shows up as a failing test (also every day in CI).
// Needs the `graphql` package (npm install). Without a path, the schema is
// the one Linear publishes (linear/linear packages/sdk/src/schema.graphql);
// with LINEAR_SCHEMA=live and LINEAR_API_KEY set, it is read from the API itself.
//
// It fails when:
//  - a query or mutation is not valid against the schema any more
//  - the board uses a field, argument or enum value Linear marked deprecated
//  - an input field the board sends (title, stateId…) is gone or deprecated
//  - a filter or input the board builds does not fit its type
const fs = require("fs"), path = require("path"), https = require("https")
const g = require("graphql")
const { load, root } = require("./load")

// Linear.js holds every request; Edit.js builds the cycle edit it sends.
const L = load("Linear"), Edit = load("Edit")

const SCHEMA_URL = "https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql"

// What the board puts into each input type (see the gql calls in logic/ and
// ui/). Adding a field to a request means adding it here; a request with an
// input type missing here fails the test.
const INPUTS = {
  IssueCreateInput: ["id", "teamId", "title", "description", "stateId", "priority", "labelIds", "projectId", "assigneeId",
    "dueDate", "estimate", "cycleId", "parentId", "projectMilestoneId"],
  IssueUpdateInput: ["title", "description", "stateId", "sortOrder", "priority", "labelIds", "addedLabelIds",
    "removedLabelIds", "projectId", "assigneeId", "dueDate", "estimate", "cycleId", "parentId", "projectMilestoneId"],
  CommentCreateInput: ["id", "issueId", "body", "parentId"],
  CommentUpdateInput: ["body"],
  IssueRelationCreateInput: ["issueId", "relatedIssueId", "type"],
  TemplateCreateInput: ["type", "name", "teamId", "templateData"],
  WorkflowStateCreateInput: ["teamId", "name", "type", "color", "position"],
  WorkflowStateUpdateInput: ["name", "color", "position"],
  IssueLabelCreateInput: ["teamId", "name", "color"],
  IssueLabelUpdateInput: ["name", "color"],
  ProjectCreateInput: ["name", "teamIds"],
  ProjectUpdateInput: ["name", "targetDate", "statusId"],
  TeamUpdateInput: ["key", "name", "cyclesEnabled", "cycleDuration", "cycleStartDay", "cycleCooldownTime", "upcomingCycleCount"],
  ReactionCreateInput: ["issueId", "commentId", "emoji"],
  ProjectMilestoneCreateInput: ["projectId", "name", "targetDate"],
  ProjectMilestoneUpdateInput: ["name", "targetDate"],
  ProjectUpdateCreateInput: ["projectId", "body", "health"],
  ProjectUpdateUpdateInput: ["body", "health"],
  CycleUpdateInput: ["name", "description", "startsAt", "endsAt"],
  NotificationUpdateInput: []   // declared in Linear.js, not sent yet
}
// Enum values the board sends.
const ENUMS = {
  IssueRelationType: (L.RELATION_KINDS || []).map(k => k.type),
  ProjectUpdateHealthType: ["onTrack", "atRisk", "offTrack"]
}

// Fields Linear marks [Internal]. Since 2026-11-11 they are left out of the
// published schema and the live introspection, but the API still answers
// them. They are added to the schema here when missing (on Notification also
// to every type that implements it); with LINEAR_API_KEY the test asks the
// API for them, so their real removal still fails the test.
const INTERNAL = {
  Query: { notificationsUnreadCount: "Int!" },
  Notification: { groupingKey: "String!", title: "String!", subtitle: "String!", inboxUrl: "String!" }
}
const INTERNAL_PROBE = "query InternalFields { notificationsUnreadCount notifications(first: 1) { nodes { " +
  Object.keys(INTERNAL.Notification).join(" ") + " } } }"

function withInternal(schema) {
  const sdl = []
  for (const [typeName, fields] of Object.entries(INTERNAL)) {
    const type = schema.getType(typeName)
    if (!type) continue   // validation then reports the type as gone
    const types = [type].concat(g.isInterfaceType(type) ? schema.getPossibleTypes(type) : [])
    for (const t of types) {
      const have = t.getFields()
      const add = Object.entries(fields).filter(([f]) => !have[f]).map(([f, ft]) => f + ": " + ft)
      if (add.length) sdl.push("extend " + (g.isInterfaceType(t) ? "interface " : "type ") + t.name + " { " + add.join(" ") + " }")
    }
  }
  return sdl.length ? g.extendSchema(schema, g.parse(sdl.join("\n"))) : schema
}

async function probeInternal() {
  const key = process.env.LINEAR_API_KEY
  if (!key) return []
  const raw = await get(L.ENDPOINT, { "Content-Type": "application/json", Authorization: key }, JSON.stringify({ query: INTERNAL_PROBE }))
  const res = JSON.parse(raw)
  return res.errors ? res.errors.map(e => "internal fields: " + e.message) : []
}

function get(url, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method: body ? "POST" : "GET", headers: headers || {} }, res => {
      let data = ""
      res.on("data", c => data += c)
      res.on("end", () => res.statusCode === 200 ? resolve(data) : reject(new Error(url + ": HTTP " + res.statusCode + " " + data.slice(0, 200))))
    })
    req.on("error", reject)
    req.setTimeout(30000, () => req.destroy(new Error(url + ": timed out")))
    if (body) req.write(body)
    req.end()
  })
}

async function loadSchema() {
  if (process.argv[2]) return { schema: g.buildSchema(fs.readFileSync(process.argv[2], "utf8")), from: process.argv[2] }
  if (process.env.LINEAR_SCHEMA === "live") {
    const key = process.env.LINEAR_API_KEY
    if (!key) throw new Error("LINEAR_SCHEMA=live needs LINEAR_API_KEY")
    const raw = await get(L.ENDPOINT, { "Content-Type": "application/json", Authorization: key },
      JSON.stringify({ query: g.getIntrospectionQuery({ inputValueDeprecation: true }) }))
    const res = JSON.parse(raw)
    if (res.errors) throw new Error(JSON.stringify(res.errors).slice(0, 300))
    return { schema: g.buildClientSchema(res.data), from: "the live API" }
  }
  return { schema: g.buildSchema(await get(SCHEMA_URL)), from: SCHEMA_URL }
}

// Every query and mutation in Linear.js: string constants and the
// *Document(count) builders. Nothing has to be listed by hand.
function documents() {
  const out = []
  for (const name of Object.keys(L)) {
    const v = L[name]
    if (typeof v === "string" && /^\s*(query|mutation)\b/.test(v)) out.push({ name, doc: v })
    else if (typeof v === "function" && /Document$/.test(name)) {
      for (const n of [1, 3]) out.push({ name: name + "(" + n + ")", doc: v(n) })
    }
  }
  return out
}

// Linear.X used by the QML files, so unused constants do not need inputs listed.
function usedNames() {
  const used = new Set()
  const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).forEach(e => {
    const p = path.join(dir, e.name)
    if (e.isDirectory() && !/^(node_modules|tests|\.git)$/.test(e.name)) walk(p)
    else if (/\.qml$/.test(e.name)) for (const m of fs.readFileSync(p, "utf8").matchAll(/\bLinear\.(\w+)/g)) used.add(m[1])
  })
  walk(root)
  return used
}

function coerce(schema, typeName, value) {
  const type = schema.getType(typeName)
  if (!type) return [typeName + " is not in the schema"]
  const errors = []
  g.coerceInputValue(value, type, (p, v, err) => errors.push(typeName + (p.length ? "." + p.join(".") : "") + ": " + err.message))
  return errors
}

async function main() {
  const loaded = await loadSchema()
  const schema = withInternal(loaded.schema), from = loaded.from
  const problems = await probeInternal()
  const deprecated = []
  const docs = documents()
  const used = usedNames()

  for (const { name, doc } of docs) {
    let ast
    try { ast = g.parse(doc) } catch (e) { problems.push(name + ": " + e.message); continue }
    for (const e of g.validate(schema, ast)) problems.push(name + ": " + e.message)
    const info = new g.TypeInfo(schema)
    g.visit(ast, g.visitWithTypeInfo(info, {
      Field() { const f = info.getFieldDef(); if (f && f.deprecationReason) deprecated.push(name + ": field " + f.name + " (" + f.deprecationReason + ")") },
      Argument() { const a = info.getArgument(); if (a && a.deprecationReason) deprecated.push(name + ": argument " + a.name + " (" + a.deprecationReason + ")") }
    }))
    // Input types this request takes must be listed in INPUTS.
    const base = name.replace(/\(\d+\)$/, "")
    if (used.has(base)) for (const m of doc.matchAll(/:\s*\[?(\w+Input)\b/g)) {
      if (!(m[1] in INPUTS)) problems.push(name + ": takes " + m[1] + ", list the fields it sends in INPUTS (tests/api.test.js)")
    }
  }

  for (const [typeName, fields] of Object.entries(INPUTS)) {
    const type = schema.getType(typeName)
    if (!type) { problems.push("input type " + typeName + " is gone"); continue }
    const have = type.getFields()
    for (const f of fields) {
      if (!have[f]) problems.push(typeName + "." + f + " is gone")
      else if (have[f].deprecationReason) deprecated.push(typeName + "." + f + " (" + have[f].deprecationReason + ")")
    }
  }

  for (const [typeName, values] of Object.entries(ENUMS)) {
    const type = schema.getType(typeName)
    if (!type || !type.getValues) { problems.push("enum " + typeName + " is gone"); continue }
    for (const v of values) {
      const ev = type.getValue(v)
      if (!ev) problems.push(typeName + "." + v + " is gone")
      else if (ev.deprecationReason) deprecated.push(typeName + "." + v + " (" + ev.deprecationReason + ")")
    }
  }

  // Values the board builds, checked against their types.
  const now = new Date("2026-10-28T12:00:00Z")
  const built = [
    ...(L.DONE_WINDOWS || []).map(w => ["IssueFilter", L.issueFilter("team", "project", w.id)]),
    ["IssueFilter", L.issueFilter("team", "", "none")],
    ["IssueFilter", L.trashFilter("team", now)],
    ["IssueFilter", L.archivedFilter("team")],
    ["IssueFilter", L.closedBeforeFilter("team", 30)],
    ["IssueFilter", L.recurExistsFilter({ teamId: "t", title: "x", projectId: "p" }, "2026-10-28")],
    ["IssueFilter", L.recurExistsFilter({ teamId: "t", title: "x" }, "2026-10-28")],
    ...(L.RELATION_KINDS || []).map(k => ["IssueRelationCreateInput", L.relationInput(k.id, "a", "b")]),
    ["CycleUpdateInput", Edit.cycleInput({ name: "", description: "", startsAt: "2026-10-01T00:00:00Z", endsAt: "2026-10-15T00:00:00Z" },
      "New", "2026-10-02", "2026-10-16", "About").input]
  ]
  // What the issue editor sends (Edit.js): every field changed at once, then
  // every field cleared, a new issue with everything set, and their undo.
  const issue = L.toIssue({ id: "i", identifier: "ENG-1", title: "Old", description: "", priority: 0, sortOrder: 1, state: { id: "s" },
    labels: { nodes: [] }, assignee: { id: "u" }, project: { id: "p" }, dueDate: "2026-11-01", estimate: 1, cycle: { id: "c" },
    parent: { id: "par" }, projectMilestone: { id: "m" } })
  const every = { teamId: "t", title: "New", description: "Text", stateId: "s2", priority: 1, labelIds: ["l"], projectId: "p2",
    assigneeId: "u2", due: "2026-11-05", estimate: 2, cycleId: "c2", parent: { id: "par2" }, milestoneId: "m2" }
  const none = { title: "New", description: "", stateId: "s", priority: 0, labelIds: [], projectId: "", assigneeId: "",
    due: "", estimate: null, cycleId: "", parent: null, milestoneId: "" }
  const edits = [Edit.issueChanges(issue, every, "text").input, Edit.issueChanges(issue, every, "props").input,
    Edit.issueChanges(issue, none, "props").input]
  for (const input of edits) built.push(["IssueUpdateInput", input], ["IssueUpdateInput", Edit.undoInput(issue, input)])
  built.push(["IssueUpdateInput", Edit.mergeInput(edits[0], edits[1])], ["IssueCreateInput", Edit.createInput(every).input])
  // Every field the editor can send is one of these, so none goes unchecked.
  const sent = new Set(edits.flatMap(Object.keys))
  for (const f of Object.keys(Edit.FIELD_LABELS)) if (!sent.has(f)) problems.push("Edit.issueChanges never sent " + f + " in this test; add it above")

  for (const [typeName, value] of built) for (const e of coerce(schema, typeName, JSON.parse(JSON.stringify(value)))) problems.push(e)

  const all = problems.concat(deprecated.map(d => "deprecated: " + d))
  if (all.length) {
    console.error("Linear API check against " + from + " failed:\n  " + all.join("\n  "))
    process.exit(1)
  }
  console.log("api: " + docs.length + " documents, " + Object.keys(INPUTS).length + " input types and " + built.length +
    " built values fit " + from)
}

main().catch(e => { console.error("api: " + e.message); process.exit(1) })
