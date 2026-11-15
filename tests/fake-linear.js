// A stand-in for Linear's API, for trying the board without a Linear account
// and for the failures Linear cannot be made to produce on purpose.
//
//   node tests/fake-linear.js [--port 47123] [--schema path/to/schema.graphql]
//   LINEAR_BOARD_ENDPOINT=http://127.0.0.1:47123/graphql LINEAR_API_KEY=lin_api_fake …
//
// Every request is executed against Linear's published schema (plus the
// [Internal] inbox fields), over made-up data: a team, states, labels,
// projects, cycles, issues and an inbox. Fields are answered from the data
// generically (record.x, record.xId, record.xIds, back references), so new
// queries mostly work without changes here.
//
// Control (JSON over HTTP on the same port):
//   POST /_control/reset                   fresh data, no faults, empty log
//   POST /_control/fault {match, kind, …}  next requests whose operation name
//        matches `match` (a regex) fail: kind "status" (status, body, headers),
//        "ratelimit" (status 400 RATELIMITED or 429, reset ms), "hang" (never
//        answers), "drop" (closes the connection), "garbage" (not JSON),
//        "slow" (ms, then answers); times (default 1, 0 = until cleared)
//   POST /_control/clear-faults
//   POST /_control/internal {on}           answer the [Internal] inbox fields or not
//   POST /_control/notify {…}              a new notification for the viewer
//   POST /_control/set {type, id, fields}  change a record behind the board's back
//   GET  /_log                             every request: {at, op, variables, status}
//   GET  /_db/<Type>                       records of a type
const http = require("http"), fs = require("fs"), path = require("path"), https = require("https")
const g = require("graphql")

const args = process.argv.slice(2)
const opt = name => { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : undefined }
const PORT = Number(opt("port") || process.env.FAKE_LINEAR_PORT || 47123)
const KEY = process.env.FAKE_LINEAR_KEY || "lin_api_fake"
const SCHEMA_URL = "https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql"
const CACHE = path.join(__dirname, ".cache", "schema.graphql")

const INTERNAL_SDL = {
  Query: "notificationsUnreadCount: Int!",
  Notification: "groupingKey: String! title: String! subtitle: String! inboxUrl: String!"
}

function download(url) {
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      let d = ""
      res.on("data", c => d += c)
      res.on("end", () => res.statusCode === 200 ? resolve(d) : reject(new Error(url + ": HTTP " + res.statusCode)))
    }).on("error", reject)
  })
}

async function schemaSource() {
  const p = opt("schema")
  if (p) return fs.readFileSync(p, "utf8")
  if (fs.existsSync(CACHE) && Date.now() - fs.statSync(CACHE).mtimeMs < 86400000) return fs.readFileSync(CACHE, "utf8")
  const sdl = await download(SCHEMA_URL)
  fs.mkdirSync(path.dirname(CACHE), { recursive: true })
  fs.writeFileSync(CACHE, sdl)
  return sdl
}

function withInternal(schema) {
  const sdl = []
  for (const [name, fields] of Object.entries(INTERNAL_SDL)) {
    const t = schema.getType(name)
    if (!t) continue
    const types = [t].concat(g.isInterfaceType(t) ? schema.getPossibleTypes(t) : [])
    for (const x of types) {
      const have = x.getFields()
      const add = fields.match(/\w+: \w+!/g).filter(f => !have[f.split(":")[0]])
      if (add.length) sdl.push("extend " + (g.isInterfaceType(x) ? "interface " : "type ") + x.name + " { " + add.join(" ") + " }")
    }
  }
  return sdl.length ? g.extendSchema(schema, g.parse(sdl.join("\n"))) : schema
}

// ---- data -------------------------------------------------------------------

let db, seq, viewerId

function nowIso() { return new Date().toISOString() }
function daysAgo(d) { return new Date(Date.now() - d * 86400000).toISOString() }
function dateIn(d) { return new Date(Date.now() + d * 86400000).toISOString().slice(0, 10) }
function newId(prefix) { return prefix + "-" + (++seq) }

function put(type, rec) {
  rec.__typename = type
  rec.id = rec.id || newId(type.toLowerCase())
  if (!rec.createdAt) rec.createdAt = nowIso()
  if (!rec.updatedAt) rec.updatedAt = rec.createdAt
  db.byId[rec.id] = rec
  ;(db.types[type] = db.types[type] || []).push(rec)
  return rec
}

function all(type) {
  if (db.types[type]) return db.types[type]
  // An interface or union: every record whose type implements it.
  const t = schema.getType(type)
  if (t && g.isAbstractType(t)) return schema.getPossibleTypes(t).flatMap(x => db.types[x.name] || [])
  return []
}

function remove(rec) {
  delete db.byId[rec.id]
  db.types[rec.__typename] = (db.types[rec.__typename] || []).filter(r => r !== rec)
}

function seed() {
  db = { byId: {}, types: {} }
  seq = 0
  const me = put("User", { id: "user-me", name: "Test User", displayName: "test", email: "test@example.com", active: true, isMe: true, teamIds: [] })
  const alex = put("User", { id: "user-alex", name: "Alex Other", displayName: "alex", email: "alex@example.com", active: true, teamIds: [] })
  viewerId = me.id
  const team = put("Team", { id: "team-eng", name: "Engineering", key: "ENG", issueEstimationType: "fibonacci", issueEstimationAllowZero: false,
    issueEstimationExtended: false, autoArchivePeriod: 6, triageEnabled: false, cyclesEnabled: true, cycleDuration: 2, cycleStartDay: 1,
    cycleCooldownTime: 0, upcomingCycleCount: 2, issueCount: 0 })
  const ops = put("Team", { id: "team-ops", name: "Operations", key: "OPS", issueEstimationType: "notUsed", autoArchivePeriod: 6, cyclesEnabled: false })
  me.teamIds = [team.id, ops.id]; alex.teamIds = [team.id]
  const st = {}
  ;[["backlog", "Backlog", "#bec2c8", 0], ["unstarted", "Todo", "#e2e2e2", 1], ["started", "In Progress", "#f2c94c", 2],
    ["completed", "Done", "#5e6ad2", 3], ["canceled", "Canceled", "#95a2b3", 4]].forEach(([type, name, color, position]) => {
    st[type] = put("WorkflowState", { id: "state-" + type, name, type, color, position, teamId: team.id })
  })
  ;[["unstarted", "Todo"], ["started", "Doing"], ["completed", "Done"]].forEach(([type, name], i) =>
    put("WorkflowState", { id: "ops-state-" + type, name, type, color: "#888888", position: i, teamId: ops.id }))
  const bug = put("IssueLabel", { id: "label-bug", name: "Bug", color: "#eb5757", isGroup: false, teamId: team.id })
  const feat = put("IssueLabel", { id: "label-feature", name: "Feature", color: "#bb87fc", isGroup: false, teamId: team.id })
  put("IssueLabel", { id: "label-docs", name: "Docs", color: "#4ea7fc", isGroup: false, teamId: null })
  ;[["status-planned", "Planned", "planned", 0], ["status-started", "In Progress", "started", 1], ["status-completed", "Completed", "completed", 2]]
    .forEach(([id, name, type, position]) => put("ProjectStatus", { id, name, type, position, color: "#5e6ad2" }))
  const alpha = put("Project", { id: "project-alpha", name: "Alpha", color: "#26b5ce", teamIds: [team.id], statusId: "status-started",
    url: "https://linear.app/fake/project/alpha", targetDate: dateIn(30), progress: 0.4, health: "onTrack", description: "" })
  const beta = put("Project", { id: "project-beta", name: "Beta", color: "#f2994a", teamIds: [team.id], statusId: "status-planned",
    url: "https://linear.app/fake/project/beta", progress: 0, description: "" })
  put("ProjectMilestone", { id: "milestone-a1", name: "Alpha 1", projectId: alpha.id, targetDate: dateIn(14), sortOrder: 0 })
  const cur = put("Cycle", { id: "cycle-1", number: 1, name: "", teamId: team.id, startsAt: daysAgo(3), endsAt: new Date(Date.now() + 11 * 86400000).toISOString(),
    isActive: true, isNext: false, isFuture: false, isPast: false, progress: 0.2 })
  put("Cycle", { id: "cycle-2", number: 2, name: "", teamId: team.id, startsAt: cur.endsAt, endsAt: new Date(Date.now() + 25 * 86400000).toISOString(),
    isActive: false, isNext: true, isFuture: true, isPast: false, progress: 0 })
  const issues = [
    ["Login page crashes on empty password", "started", 1, me, alpha, [bug.id], cur.id, 3, dateIn(2)],
    ["Add dark mode toggle", "unstarted", 3, me, alpha, [feat.id], cur.id, 2, null],
    ["Write onboarding docs", "backlog", 4, null, beta, [], null, null, null],
    ["Rate limiter for the public API", "unstarted", 2, alex, null, [feat.id], null, 5, dateIn(-1)],
    ["Fix flaky CI job", "started", 2, alex, alpha, [bug.id], cur.id, 1, null],
    ["Upgrade database driver", "backlog", 0, null, null, [], null, null, null],
    ["Release 1.2", "completed", 2, me, alpha, [], cur.id, 2, null],
    ["Old idea we dropped", "canceled", 0, null, null, [], null, null, null],
    ["Profile slow search", "unstarted", 3, me, beta, [], null, 3, dateIn(7)],
    ["Accessibility audit", "backlog", 3, null, beta, [], null, null, null]
  ]
  issues.forEach(([title, type, priority, who, project, labelIds, cycleId, estimate, dueDate], i) => {
    const closed = type === "completed" || type === "canceled"
    put("Issue", { id: "issue-" + (i + 1), number: i + 1, identifier: "ENG-" + (i + 1), title, description: i === 0 ? "Steps:\n\n1. Open login\n2. Submit" : "",
      priority, stateId: st[type].id, teamId: team.id, assigneeId: who ? who.id : null, projectId: project ? project.id : null, labelIds,
      cycleId, estimate, dueDate, sortOrder: i * 10, url: "https://linear.app/fake/issue/ENG-" + (i + 1), branchName: "eng-" + (i + 1),
      previousIdentifiers: [], creatorId: i % 2 ? alex.id : me.id, createdAt: daysAgo(20 - i), updatedAt: daysAgo(10 - i / 2),
      completedAt: type === "completed" ? daysAgo(1) : null, canceledAt: type === "canceled" ? daysAgo(2) : null,
      archivedAt: null, trashed: false, subscriberIds: [me.id] })
  })
  team.issueCount = issues.length
  db.issueNumber = { [team.id]: issues.length, [ops.id]: 0 }
  db.byId["issue-6"].parentId = "issue-5"
  put("Comment", { id: "comment-1", body: "Can reproduce on staging.", issueId: "issue-1", userId: alex.id, createdAt: daysAgo(1) })
  put("IssueRelation", { id: "relation-1", type: "blocks", issueId: "issue-4", relatedIssueId: "issue-9" })
  put("Attachment", { id: "attachment-1", title: "Spec", subtitle: "docs", url: "https://example.com/spec", sourceType: "url", issueId: "issue-1" })
  // The inbox: two notifications on ENG-1 (one row), a mention, a bot, a project, read ones.
  const n = (type, category, issueId, extra) => put("IssueNotification", Object.assign({ type, category, issueId, userId: me.id,
    actorId: alex.id, readAt: null, snoozedUntilAt: null }, extra))
  n("issueAssignedToYou", "assignments", "issue-1", { createdAt: daysAgo(0.5), groupingKey: "issue#issue-1", title: "Login page crashes on empty password",
    subtitle: "Assigned to you by Alex Other", inboxUrl: "https://linear.app/fake/inbox/1" })
  n("issuePriorityUrgent", "statusChanges", "issue-1", { createdAt: daysAgo(0.4), groupingKey: "issue#issue-1", title: "Login page crashes on empty password",
    subtitle: "Marked urgent by Alex Other", inboxUrl: "https://linear.app/fake/inbox/1" })
  n("issueMention", "mentions", "issue-5", { createdAt: daysAgo(0.3), commentId: "comment-1", groupingKey: "issue#issue-5", title: "Fix flaky CI job",
    subtitle: "Mentioned by Alex Other", inboxUrl: "https://linear.app/fake/inbox/5" })
  n("issueStatusChanged", "statusChanges", "issue-4", { createdAt: daysAgo(0.2), actorId: null, botActorName: "Sentry", groupingKey: "issue#issue-4",
    title: "Rate limiter for the public API", subtitle: "Status changed by Sentry", inboxUrl: "https://linear.app/fake/inbox/4" })
  n("issueNewComment", "commentsAndReplies", "issue-9", { createdAt: daysAgo(3), readAt: daysAgo(2), groupingKey: "issue#issue-9", title: "Profile slow search",
    subtitle: "New comment by Alex Other", inboxUrl: "https://linear.app/fake/inbox/9" })
  put("ProjectNotification", { type: "projectUpdateCreated", category: "postsAndUpdates", projectId: alpha.id, userId: me.id, actorId: alex.id,
    readAt: null, snoozedUntilAt: null, createdAt: daysAgo(0.1), groupingKey: "project#project-alpha", title: "Alpha",
    subtitle: "New project update by Alex Other", inboxUrl: "https://linear.app/fake/inbox/p" })
}

// Made-up data for the README's screenshots (POST /_control/demo): a small
// product team in the middle of a cycle. Nothing here is real.
function seedDemo() {
  db = { byId: {}, types: {} }
  seq = 0
  const user = (id, name, displayName) => put("User", { id, name, displayName, email: displayName + "@example.com", active: true, teamIds: [] })
  const me = user("user-me", "Alex Rivera", "alex")
  const sam = user("user-sam", "Sam Chen", "sam")
  const priya = user("user-priya", "Priya Patel", "priya")
  const jordan = user("user-jordan", "Jordan Lee", "jordan")
  viewerId = me.id
  const team = put("Team", { id: "team-web", name: "Web App", key: "WEB", issueEstimationType: "fibonacci", issueEstimationAllowZero: false,
    issueEstimationExtended: false, autoArchivePeriod: 6, triageEnabled: false, cyclesEnabled: true, cycleDuration: 2, cycleStartDay: 1,
    cycleCooldownTime: 0, upcomingCycleCount: 2 })
  const mob = put("Team", { id: "team-mob", name: "Mobile", key: "MOB", issueEstimationType: "notUsed", autoArchivePeriod: 6, cyclesEnabled: false })
  for (const u of [me, sam, priya, jordan]) u.teamIds = [team.id, mob.id]
  const st = {}
  ;[["backlog", "Backlog", "#bec2c8", 0], ["unstarted", "Todo", "#e2e2e2", 1], ["started", "In Progress", "#f2c94c", 2],
    ["review", "In Review", "#0f783c", 3], ["completed", "Done", "#5e6ad2", 4], ["canceled", "Canceled", "#95a2b3", 5]].forEach(([key, name, color, position]) => {
    st[key] = put("WorkflowState", { id: "state-" + key, name, type: key === "review" ? "started" : key, color, position, teamId: team.id })
  })
  ;[["unstarted", "Todo"], ["started", "Doing"], ["completed", "Done"]].forEach(([type, name], i) =>
    put("WorkflowState", { id: "mob-state-" + type, name, type, color: "#888888", position: i, teamId: mob.id }))
  const L = {}
  ;[["bug", "Bug", "#eb5757"], ["feature", "Feature", "#bb87fc"], ["design", "Design", "#f2994a"], ["perf", "Performance", "#4cb782"],
    ["docs", "Docs", "#4ea7fc"]].forEach(([id, name, color]) => { L[id] = put("IssueLabel", { id: "label-" + id, name, color, isGroup: false, teamId: team.id }) })
  ;[["status-planned", "Planned", "planned", 0], ["status-started", "In Progress", "started", 1], ["status-completed", "Completed", "completed", 2]]
    .forEach(([id, name, type, position]) => put("ProjectStatus", { id, name, type, position, color: "#5e6ad2" }))
  const P = {
    checkout: put("Project", { id: "project-checkout", name: "Checkout v2", color: "#4ea7fc", teamIds: [team.id], statusId: "status-started",
      url: "https://linear.app/demo/project/checkout-v2", targetDate: dateIn(24), progress: 0.58, health: "onTrack", description: "" }),
    onboarding: put("Project", { id: "project-onboarding", name: "Onboarding", color: "#4cb782", teamIds: [team.id], statusId: "status-started",
      url: "https://linear.app/demo/project/onboarding", targetDate: dateIn(40), progress: 0.3, health: "atRisk", description: "" }),
    perf: put("Project", { id: "project-perf", name: "Speed", color: "#f2994a", teamIds: [team.id], statusId: "status-planned",
      url: "https://linear.app/demo/project/speed", progress: 0.1, health: "onTrack", description: "" })
  }
  put("ProjectMilestone", { id: "milestone-beta", name: "Public beta", projectId: P.checkout.id, targetDate: dateIn(10), sortOrder: 0 })
  const cycle = put("Cycle", { id: "cycle-12", number: 12, name: "", teamId: team.id, startsAt: daysAgo(6), endsAt: new Date(Date.now() + 8 * 86400000).toISOString(),
    isActive: true, isNext: false, isFuture: false, isPast: false, progress: 0.46 })
  put("Cycle", { id: "cycle-13", number: 13, name: "", teamId: team.id, startsAt: cycle.endsAt, endsAt: new Date(Date.now() + 22 * 86400000).toISOString(),
    isActive: false, isNext: true, isFuture: true, isPast: false, progress: 0 })
  // [title, state, priority, assignee, project, labels, inCycle, estimate, due (days), description]
  const rows = [
    ["Apple Pay on the payment step", "started", 2, me, "checkout", ["feature"], true, 5, 3,
      "Show Apple Pay next to the card form when the browser supports it.\n\n- [x] Merchant validation endpoint\n- [x] Payment sheet with the order total\n- [ ] Handle a cancelled sheet\n- [ ] Receipt email shows the wallet\n\nDesign: the button sits above the card fields, full width on mobile."],
    ["Coupon field loses focus on mobile Safari", "started", 1, sam, "checkout", ["bug"], true, 2, 1, ""],
    ["Order summary sticky on scroll", "review", 3, priya, "checkout", ["design"], true, 2, null, ""],
    ["Address autocomplete for EU countries", "review", 2, jordan, "checkout", ["feature"], true, 3, 5, ""],
    ["Retry failed card payments once", "unstarted", 2, me, "checkout", ["feature"], true, 3, 6, ""],
    ["Empty cart shows a spinner forever", "unstarted", 1, null, "checkout", ["bug"], true, 1, null, ""],
    ["Welcome checklist after sign-up", "unstarted", 3, priya, "onboarding", ["feature", "design"], true, 5, 9, ""],
    ["Invite teammates step", "backlog", 3, null, "onboarding", ["feature"], false, 3, null, ""],
    ["Sample project for new workspaces", "backlog", 4, null, "onboarding", [], false, 2, null, ""],
    ["Lazy-load product images", "backlog", 2, jordan, "perf", ["perf"], false, 2, null, ""],
    ["Cut the JS bundle below 200 kB", "unstarted", 2, sam, "perf", ["perf"], true, 8, null, ""],
    ["Write the payments runbook", "backlog", 4, null, "checkout", ["docs"], false, 1, null, ""],
    ["Gift cards in checkout", "backlog", 0, null, "checkout", ["feature"], false, null, null, ""],
    ["Tax shown twice on invoices", "completed", 1, sam, "checkout", ["bug"], true, 2, null, ""],
    ["New pricing page", "completed", 2, priya, "onboarding", ["design"], true, 3, null, ""],
    ["Track checkout funnel events", "completed", 3, me, "checkout", ["feature"], true, 2, null, ""]
  ]
  rows.forEach(([title, state, priority, who, project, labels, inCycle, estimate, due, description], i) => {
    const n = 140 + i
    put("Issue", { id: "issue-" + n, number: n, identifier: "WEB-" + n, title, description, priority, stateId: st[state].id, teamId: team.id,
      assigneeId: who ? who.id : null, projectId: P[project] ? P[project].id : null, labelIds: labels.map(l => L[l].id),
      cycleId: inCycle ? cycle.id : null, estimate, dueDate: due === null ? null : dateIn(due), sortOrder: i * 10,
      projectMilestoneId: project === "checkout" && i < 6 ? "milestone-beta" : null,
      url: "https://linear.app/demo/issue/WEB-" + n, branchName: "alex/web-" + n, previousIdentifiers: [], creatorId: me.id,
      createdAt: daysAgo(30 - i), updatedAt: daysAgo(5 - i / 4), completedAt: state === "completed" ? daysAgo(1 + i % 3) : null,
      canceledAt: null, archivedAt: null, trashed: false, subscriberIds: [me.id] })
  })
  db.issueNumber = { [team.id]: 160, [mob.id]: 0 }
  // Sub-issues of the Apple Pay work.
  ;[["Merchant validation endpoint", "completed"], ["Payment sheet with the order total", "completed"], ["Handle a cancelled sheet", "started"]].forEach(([title, state], i) =>
    put("Issue", { id: "issue-sub" + i, number: 161 + i, identifier: "WEB-" + (161 + i), title, description: "", priority: 0, stateId: st[state].id,
      teamId: team.id, assigneeId: me.id, projectId: P.checkout.id, labelIds: [], parentId: "issue-140", sortOrder: 200 + i,
      url: "https://linear.app/demo/issue/WEB-" + (161 + i), branchName: "", previousIdentifiers: [], createdAt: daysAgo(4), updatedAt: daysAgo(1),
      completedAt: state === "completed" ? daysAgo(1) : null, archivedAt: null, trashed: false }))
  db.issueNumber[team.id] = 163
  put("Comment", { id: "comment-d1", body: "Merchant validation works on staging. The domain file is served from `/.well-known/` now.", issueId: "issue-140", userId: sam.id, createdAt: daysAgo(1.2) })
  put("Comment", { id: "comment-d2", body: "Nice. I'll check the cancelled sheet case next.", issueId: "issue-140", userId: me.id, createdAt: daysAgo(1.1) })
  put("Comment", { id: "comment-d3", body: "@alex can you check this on iOS 18? I only have an older phone.", issueId: "issue-141", userId: sam.id, createdAt: daysAgo(0.2) })
  put("IssueRelation", { id: "relation-d1", type: "blocks", issueId: "issue-140", relatedIssueId: "issue-144" })
  put("Attachment", { id: "attachment-d1", title: "Apple Pay on the Web: guidelines", subtitle: "developer.apple.com", url: "https://developer.apple.com/apple-pay/",
    sourceType: "url", issueId: "issue-140" })
  const note = (type, category, issueId, actor, mins, subtitle, extra) => put("IssueNotification", Object.assign({ type, category, issueId, userId: me.id,
    actorId: actor ? actor.id : null, readAt: null, snoozedUntilAt: null, createdAt: new Date(Date.now() - mins * 60000).toISOString(),
    groupingKey: "issue#" + issueId, title: db.byId[issueId].title, subtitle, inboxUrl: "https://linear.app/demo/inbox" }, extra || {}))
  note("issueMention", "mentions", "issue-141", sam, 12, "Mentioned you by Sam Chen", { commentId: "comment-d3" })
  note("issueAssignedToYou", "assignments", "issue-144", jordan, 48, "Assigned to you by Jordan Lee")
  note("issueNewComment", "commentsAndReplies", "issue-140", sam, 95, "New comment by Sam Chen", { commentId: "comment-d1" })
  note("issueStatusChanged", "statusChanges", "issue-142", priya, 180, "Moved to In Review by Priya Patel")
  note("issuePriorityUrgent", "statusChanges", "issue-145", null, 260, "Marked urgent by Sentry", { botActorName: "Sentry" })
  note("issueStatusChanged", "statusChanges", "issue-153", sam, 60 * 26, "Moved to Done by Sam Chen", { readAt: daysAgo(0.9) })
  put("ProjectNotification", { type: "projectUpdateCreated", category: "postsAndUpdates", projectId: P.checkout.id, userId: me.id, actorId: priya.id,
    readAt: null, snoozedUntilAt: null, createdAt: new Date(Date.now() - 300 * 60000).toISOString(), groupingKey: "project#" + P.checkout.id,
    title: "Checkout v2", subtitle: "New project update by Priya Patel", inboxUrl: "https://linear.app/demo/inbox" })
  put("ProjectUpdate", { id: "update-d1", body: "Apple Pay is in review, EU address autocomplete lands this week. Public beta still on track.",
    health: "onTrack", projectId: P.checkout.id, userId: priya.id, createdAt: daysAgo(0.2) })
}

// ---- answering fields from the data ------------------------------------------------

const lcfirst = s => s.charAt(0).toLowerCase() + s.slice(1)
const named = t => g.getNamedType(t)
const isConnection = t => g.isObjectType(t) && /Connection$/.test(t.name) && t.getFields().nodes

// Field → [node type, field on the node that points back], where the
// generic rules guess wrong.
const BACKREFS = {
  "Issue.children": "parentId", "Issue.inverseRelations": "relatedIssueId", "User.assignedIssues": "assigneeId",
  "Issue.subscribers": null, "Team.members": "teamIds", "Project.teams": null
}

function related(parent, parentType, field, nodeType) {
  const key = parentType + "." + field
  const ids = parent[field.replace(/s$/, "") + "Ids"] || parent[field.replace(/ies$/, "y") + "Ids"]
  if (Array.isArray(ids) && !(key in BACKREFS && BACKREFS[key])) return ids.map(id => db.byId[id]).filter(Boolean)
  const back = BACKREFS[key] || lcfirst(parentType) + "Id"
  const many = BACKREFS[key] || lcfirst(parentType) + "Ids"
  return all(nodeType).filter(r => r[back] === parent.id || (Array.isArray(r[many]) && r[many].indexOf(parent.id) >= 0) ||
    (Array.isArray(r[back]) && r[back].indexOf(parent.id) >= 0))
}

function defaultFor(type) {
  if (!g.isNonNullType(type)) return null
  const t = type.ofType
  if (g.isListType(t)) return []
  if (g.isEnumType(t)) return t.getValues()[0].value
  switch (t.name) {
    case "String": case "ID": return ""
    case "Boolean": return false
    case "Int": case "Float": return 0
    case "DateTime": return nowIso()
    case "TimelessDate": return dateIn(0)
    case "JSON": case "JSONObject": return {}
  }
  if (g.isObjectType(t) && isConnection(t)) return { __nodes: [] }
  return null
}

// ISO 8601 durations ("-P2W") count from now, as Linear does in filters.
function filterValue(v) {
  if (typeof v !== "string") return v
  const m = /^(-)?P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$/.exec(v)
  if (!m) return v
  const days = (+m[2] || 0) * 365 + (+m[3] || 0) * 30 + (+m[4] || 0) * 7 + (+m[5] || 0)
  return new Date(Date.now() + (m[1] ? -1 : 1) * days * 86400000).toISOString()
}

const warned = new Set()
function warn(msg) { if (!warned.has(msg)) { warned.add(msg); console.warn("fake-linear: " + msg) } }

function compare(value, cmp) {
  for (const [op, raw] of Object.entries(cmp)) {
    const v = filterValue(raw)
    const val = value === undefined ? null : value
    switch (op) {
      case "eq": if (val !== v) return false; break
      case "neq": if (val === v) return false; break
      case "in": if (!v.includes(val)) return false; break
      case "nin": if (v.includes(val)) return false; break
      case "null": if ((val === null) !== v) return false; break
      case "lt": if (val === null || !(val < v)) return false; break
      case "lte": if (val === null || !(val <= v)) return false; break
      case "gt": if (val === null || !(val > v)) return false; break
      case "gte": if (val === null || !(val >= v)) return false; break
      case "contains": if (!String(val || "").includes(v)) return false; break
      case "containsIgnoreCase": if (!String(val || "").toLowerCase().includes(String(v).toLowerCase())) return false; break
      case "startsWith": if (!String(val || "").startsWith(v)) return false; break
      default: warn("filter comparator " + op + " is ignored")
    }
  }
  return true
}

function matches(rec, filter, typeName) {
  if (!filter) return true
  const type = schema.getType(typeName)
  const fields = type && type.getFields ? type.getFields() : {}
  for (const [key, f] of Object.entries(filter)) {
    if (f === null || f === undefined) continue
    if (key === "and") { if (!f.every(x => matches(rec, x, typeName))) return false; continue }
    if (key === "or") { if (!f.some(x => matches(rec, x, typeName))) return false; continue }
    if (key === "isMe") { if (!compare(rec.id === viewerId, f)) return false; continue }
    const field = fields[key]
    const nt = field && named(field.type)
    if (nt && isConnection(nt)) {
      const list = related(rec, typeName, key, named(nt.getFields().nodes.type).name)
      const nodeType = named(nt.getFields().nodes.type).name
      if (f.some && !list.some(x => matches(x, f.some, nodeType))) return false
      if (f.every && !list.every(x => matches(x, f.every, nodeType))) return false
      if (f.none && list.some(x => matches(x, f.none, nodeType))) return false
      continue
    }
    if (nt && g.isObjectType(nt)) {
      const target = db.byId[rec[key + "Id"]] || null
      if ("null" in f && (target === null) !== f.null) return false
      const rest = Object.assign({}, f); delete rest.null
      if (Object.keys(rest).length && (!target || !matches(target, rest, nt.name))) return false
      continue
    }
    if (!field && !(key in rec)) { warn("filter on " + typeName + "." + key + " is ignored"); continue }
    if (!compare(rec[key], f)) return false
  }
  return true
}

function page(list, a) {
  let start = 0
  if (a.after) { const i = list.findIndex(r => r.id === a.after); start = i >= 0 ? i + 1 : list.length }
  const n = a.first || a.last || 50
  const nodes = list.slice(start, start + n)
  return { __nodes: nodes, pageInfo: { hasNextPage: start + n < list.length, hasPreviousPage: start > 0,
    endCursor: nodes.length ? nodes[nodes.length - 1].id : null, startCursor: nodes.length ? nodes[0].id : null } }
}

function listFor(list, a, nodeType) {
  let out = list
  if (!a.includeArchived && nodeType !== "IssueHistory") out = out.filter(r => !r.archivedAt)
  if (a.filter) out = out.filter(r => matches(r, a.filter, nodeType))
  if (a.orderBy === "createdAt") out = out.slice().sort((x, y) => x.createdAt < y.createdAt ? 1 : -1)
  return out
}

function rootField(fieldName, a, info) {
  const type = info.returnType
  const nt = named(type)
  if (fieldName === "viewer") return db.byId[viewerId]
  if (fieldName === "notificationsUnreadCount") return all("Notification").filter(n => n.userId === viewerId && !n.readAt && !n.archivedAt &&
    !(n.snoozedUntilAt && n.snoozedUntilAt > nowIso())).length
  if (fieldName === "searchIssues") {
    const term = String(a.term || "").toLowerCase()
    const list = all("Issue").filter(i => !i.archivedAt && (!a.teamId || i.teamId === a.teamId) &&
      (i.title.toLowerCase().includes(term) || i.identifier.toLowerCase() === term))
    return page(list, a)
  }
  if (isConnection(nt)) {
    const nodeType = named(nt.getFields().nodes.type).name
    let list = all(nodeType)
    if (nodeType === "Notification") list = list.filter(n => n.userId === viewerId).sort((x, y) => x.createdAt < y.createdAt ? 1 : -1)
    return page(listFor(list, a, nodeType), a)
  }
  if (g.isListType(g.getNullableType(type))) return all(nt.name)
  if (g.isObjectType(nt) || g.isAbstractType(nt)) {
    if (a.id === undefined) { warn("query field " + fieldName + " has no fake answer"); return null }
    const r = db.byId[a.id] || all(nt.name).find(x => x.identifier === String(a.id).toUpperCase())
    if (!r) throw new g.GraphQLError("Entity not found: " + nt.name, { extensions: { code: "INVALID_INPUT", userPresentableMessage: "Could not find referenced " + nt.name + "." } })
    return r
  }
  warn("query field " + fieldName + " has no fake answer")
  return defaultFor(type)
}

function fieldResolver(source, a, ctx, info) {
  const name = info.fieldName
  if (info.parentType === schema.getQueryType()) return rootField(name, a, info)
  if (info.parentType === schema.getMutationType()) return mutate(name, a, info)
  if (source && source.__nodes && name === "nodes") return source.__nodes
  if (source && source.__nodes && name === "pageInfo") return source.pageInfo || { hasNextPage: false, endCursor: null }
  const type = info.returnType, nt = named(type)
  if (!source) return null
  // Mutation payloads: { success, lastSyncId, <entity> }.
  if (source.__payload) {
    if (name === "success") return true
    if (name === "lastSyncId") return seq
    if (source.records && g.isListType(g.getNullableType(type))) return source.records
    return source.record && (source.record.__typename === nt.name || g.isAbstractType(nt) || name === lcfirst(source.record.__typename)) ? source.record : defaultFor(type)
  }
  if (name === "botActor") return source.botActorName ? { name: source.botActorName, __typename: "ActorBot" } : null
  if (name === "isMe") return source.id === viewerId
  if (name === "trashed" && source.__typename === "Issue") return !!source.trashed
  if (Object.prototype.hasOwnProperty.call(source, name) && !(isConnection(nt))) {
    const v = source[name]
    return v === undefined || v === null ? defaultFor(type) : v
  }
  if (isConnection(nt)) {
    const nodeType = named(nt.getFields().nodes.type).name
    return page(listFor(related(source, source.__typename, name, nodeType), a, nodeType), a)
  }
  if (g.isListType(g.getNullableType(type)) && (g.isObjectType(nt) || g.isAbstractType(nt)))
    return related(source, source.__typename, name, nt.name)
  if (g.isObjectType(nt) || g.isAbstractType(nt)) {
    const id = source[name + "Id"]
    if (id) return db.byId[id] || null
    return defaultFor(type)
  }
  return defaultFor(type)
}

// ---- mutations ------------------------------------------------------------------------

function entityOf(prefix) {
  const t = Object.keys(schema.getTypeMap()).find(n => lcfirst(n) === prefix &&
    (g.isObjectType(schema.getType(n)) || g.isInterfaceType(schema.getType(n))))
  return t || null
}

function applyInput(rec, input) {
  for (const [k, v] of Object.entries(input || {})) {
    if (k === "addedLabelIds") rec.labelIds = Array.from(new Set((rec.labelIds || []).concat(v)))
    else if (k === "removedLabelIds") rec.labelIds = (rec.labelIds || []).filter(id => v.indexOf(id) < 0)
    else if (k === "teamIds" && rec.__typename === "Project") rec.teamIds = v
    else rec[k] = v
  }
  rec.updatedAt = nowIso()
  if (rec.__typename === "Issue" && input && "stateId" in input) {
    const s = db.byId[rec.stateId]
    rec.completedAt = s && s.type === "completed" ? (rec.completedAt || nowIso()) : null
    rec.canceledAt = s && s.type === "canceled" ? (rec.canceledAt || nowIso()) : null
  }
}

// What Linear answers a create with an id it has (seen 2026-11-14).
function duplicate(type, id) {
  return new g.GraphQLError("conflict on insert of " + type, { extensions: { type: "invalid input", code: "INPUT_ERROR", statusCode: 400,
    userError: true, userPresentableMessage: "Entity " + type + " with id " + id + " already exists" } })
}

function find(type, id) {
  const r = db.byId[id] || (type === "Issue" && all("Issue").find(x => x.identifier === String(id).toUpperCase()))
  if (!r) throw new g.GraphQLError("Entity not found", { extensions: { code: "INVALID_INPUT", userPresentableMessage: "Could not find referenced " + type + "." } })
  return r
}

function createIssue(input) {
  if (input.id && db.byId[input.id]) throw duplicate("Issue", input.id)
  const team = find("Team", input.teamId)
  const n = (db.issueNumber[team.id] || 0) + 1
  db.issueNumber[team.id] = n
  const firstState = all("WorkflowState").filter(s => s.teamId === team.id).sort((a, b) =>
    (a.type === "unstarted" ? -1 : 0) - (b.type === "unstarted" ? -1 : 0))[0]
  const rec = put("Issue", { id: input.id, number: n, identifier: team.key + "-" + n, priority: 0, labelIds: [], sortOrder: -n, previousIdentifiers: [],
    stateId: firstState && firstState.id, creatorId: viewerId, archivedAt: null, trashed: false, description: "", subscriberIds: [viewerId] })
  rec.url = "https://linear.app/fake/issue/" + rec.identifier
  rec.branchName = rec.identifier.toLowerCase()
  applyInput(rec, input)
  return rec
}

function mutate(name, a, info) {
  const m = /^(.+?)(Create|Update|Delete|Archive|Unarchive)$/.exec(name)
  const pay = (record, records) => ({ __payload: true, record, records })
  if (name === "issueBatchUpdate") return pay(null, a.ids.map(id => { const r = find("Issue", id); applyInput(r, a.input); return r }))
  if (name === "attachmentLinkURL") return pay(put("Attachment", { issueId: find("Issue", a.issueId).id, url: a.url, title: a.title || a.url, subtitle: "", sourceType: "url" }))
  if (name === "cycleStartUpcomingCycleToday") { const c = find("Cycle", a.id); c.startsAt = nowIso(); return pay(c) }
  if (name === "fileUpload") return pay({ __typename: "UploadFile", uploadUrl: "http://127.0.0.1:" + PORT + "/_upload/" + (++seq),
    assetUrl: "http://127.0.0.1:" + PORT + "/_asset/" + seq, headers: [], contentType: a.contentType, filename: a.filename, size: a.size })
  if (name === "issueReminder" || name === "issueSubscribe" || name === "issueUnsubscribe" || name === "fileDelete") {
    if (a.id) find("Issue", a.id)
    return pay(null)
  }
  if (!m) { warn("mutation " + name + " has no fake answer"); return pay(null) }
  const type = entityOf(m[1])
  if (!type) { warn("mutation " + name + ": no type " + m[1]); return pay(null) }
  switch (m[2]) {
    case "Create": {
      if (type === "Issue") return pay(createIssue(a.input))
      if (a.input && a.input.id && db.byId[a.input.id]) throw duplicate(type, a.input.id)
      const rec = put(type, { id: a.input && a.input.id })
      applyInput(rec, a.input)
      if (type === "Comment" || type === "Reaction") rec.userId = viewerId
      if (type === "IssueRelation") { find("Issue", rec.issueId); find("Issue", rec.relatedIssueId) }
      return pay(rec)
    }
    case "Update": { const rec = find(type, a.id); applyInput(rec, a.input); return pay(rec) }
    case "Delete": {
      const rec = find(type, a.id)
      if (type === "Issue" && !a.permanentlyDelete) { rec.archivedAt = nowIso(); rec.trashed = true }
      else remove(rec)
      return pay(type === "Issue" ? rec : null)
    }
    case "Archive": { const rec = find(type, a.id); rec.archivedAt = nowIso(); return pay(rec) }
    case "Unarchive": { const rec = find(type, a.id); rec.archivedAt = null; rec.trashed = false; return pay(rec) }
  }
}

// ---- HTTP -------------------------------------------------------------------------------

const AUTH_ERROR = { errors: [{ message: "Authentication required, not authenticated", extensions: { type: "authentication error",
  code: "AUTHENTICATION_ERROR", statusCode: 401, userError: true, userPresentableMessage: "You need to authenticate to access this operation.",
  meta: {}, http: { status: 401 } } }] }

const sockets = new Set()
let schema, fullSchema, publicSchema, internalOn = true, faults = [], log = []

function json(res, status, body, headers) {
  res.writeHead(status, Object.assign({ "Content-Type": "application/json" }, headers || {}))
  res.end(JSON.stringify(body))
}

function control(req, res, url, body) {
  const p = url.pathname
  if (p === "/_log") return json(res, 200, log)
  if (p === "/_sockets") return json(res, 200, { open: sockets.size, stalled: [...sockets].filter(x => x.stalled).length })
  if (p.startsWith("/_db/")) return json(res, 200, all(p.slice(5)))
  if (p === "/_control/demo") { seedDemo(); faults = []; log = []; internalOn = true; return json(res, 200, { ok: true }) }
  if (p === "/_control/reset") { seed(); faults = []; log = []; internalOn = true; return json(res, 200, { ok: true }) }
  if (p === "/_control/fault") { faults.push(Object.assign({ times: 1, match: "." }, body)); return json(res, 200, { ok: true, faults }) }
  // Like a router after a suspend: connections open now are never answered
  // again (requests on them hang); new connections work.
  if (p === "/_control/stall") { for (const so of sockets) so.stalled = true; return json(res, 200, { ok: true, stalled: sockets.size }) }
  if (p === "/_control/clear-faults") { faults = []; return json(res, 200, { ok: true }) }
  if (p === "/_control/internal") { internalOn = !!body.on; return json(res, 200, { ok: true, internal: internalOn }) }
  if (p === "/_control/set") { const r = db.byId[body.id]; if (!r) return json(res, 404, {}); Object.assign(r, body.fields); return json(res, 200, r) }
  if (p === "/_control/bulk") {
    // Many issues (paging) and many notifications, the unread ones oldest.
    for (let i = 0; i < (body.issues || 0); i++) createIssue({ teamId: "team-eng", title: "Bulk issue " + (i + 1), stateId: "state-backlog" })
    for (let i = 0; i < (body.notifications || 0); i++) {
      const unread = i < (body.unread || 0)
      put("IssueNotification", { type: "issueNewComment", category: "commentsAndReplies", issueId: "issue-2", userId: viewerId, actorId: "user-alex",
        readAt: unread ? null : daysAgo(1), snoozedUntilAt: null, createdAt: daysAgo(30 - i * 0.01), groupingKey: "bulk#" + i,
        title: "Bulk notification " + i, subtitle: "New comment by Alex Other", inboxUrl: "https://linear.app/fake/inbox/b" })
    }
    return json(res, 200, { ok: true })
  }
  if (p === "/_control/notify") {
    const type = body.projectId ? "ProjectNotification" : "IssueNotification"
    const issue = body.issueId && db.byId[body.issueId]
    const rec = put(type, Object.assign({ type: "issueAssignedToYou", category: "assignments", userId: viewerId, actorId: "user-alex",
      readAt: null, snoozedUntilAt: null, groupingKey: issue ? "issue#" + issue.id : "project#" + body.projectId,
      title: issue ? issue.title : "Project", subtitle: "Assigned to you by Alex Other", inboxUrl: "https://linear.app/fake/inbox/x" }, body))
    return json(res, 200, rec)
  }
  json(res, 404, { error: "unknown control " + p })
}

function takeFault(op) {
  const f = faults.find(x => new RegExp(x.match).test(op))
  if (!f) return null
  if (f.times > 0 && --f.times === 0) faults = faults.filter(x => x !== f)
  return f
}

async function handle(req, res) {
  const url = new URL(req.url, "http://localhost")
  let raw = ""
  for await (const c of req) raw += c
  let body = {}
  try { body = raw ? JSON.parse(raw) : {} } catch (e) { return json(res, 400, { errors: [{ message: "Body is not JSON" }] }) }
  if (url.pathname.startsWith("/_")) return control(req, res, url, body)
  if (url.pathname !== "/graphql" || req.method !== "POST") return json(res, 404, {})
  if (req.socket.stalled) { log.push({ at: nowIso(), op: "(on a dead connection)", variables: {}, status: 0 }); return }
  let op = body.operationName || ""
  if (!op) { const m = /^\s*(?:query|mutation)\s+(\w+)/.exec(body.query || ""); op = m ? m[1] : "anonymous" }
  const entry = { at: nowIso(), op, variables: body.variables || {}, status: 0 }
  log.push(entry)
  const finish = (status, out, headers) => { entry.status = status; json(res, status, out, headers) }
  // What Linear answers a wrong or revoked key (checked 2026-11-14).
  if (req.headers.authorization !== KEY) return finish(401, AUTH_ERROR)
  const f = takeFault(op)
  if (f) {
    entry.fault = f.kind
    if (f.kind === "hang") return   // never answers; the board's watchdog has to give up
    if (f.kind === "drop") { entry.status = -1; return req.socket.destroy() }
    if (f.kind === "garbage") { entry.status = 200; res.writeHead(200, { "Content-Type": "text/html" }); return res.end("<html>Bad gateway</html>") }
    if (f.kind === "status") return finish(f.status || 500, f.body || { errors: [{ message: "Internal server error" }] }, f.headers)
    if (f.kind === "ratelimit") {
      const headers = { "X-RateLimit-Requests-Reset": String(Date.now() + (f.resetMs || 60000)) }
      return finish(f.status || 400, { errors: [{ message: "Rate limit exceeded", extensions: { code: "RATELIMITED" } }] }, headers)
    }
    if (f.kind === "slow") await new Promise(r => setTimeout(r, f.ms || 5000))
  }
  const doc = (() => { try { return g.parse(body.query || "") } catch (e) { return e } })()
  if (doc instanceof Error) return finish(400, { errors: [{ message: "Syntax Error: " + doc.message, extensions: { code: "GRAPHQL_PARSE_FAILED" } }] })
  schema = internalOn ? fullSchema : publicSchema
  const errors = g.validate(schema, doc)
  if (errors.length) return finish(400, { errors: errors.map(e => ({ message: e.message, extensions: { code: "GRAPHQL_VALIDATION_FAILED" } })) })
  const result = await g.execute({ schema, document: doc, variableValues: body.variables || {}, fieldResolver,
    typeResolver: v => v.__typename })
  if (result.errors) result.errors.forEach(e => console.warn("fake-linear: " + op + ": " + e.message))
  finish(200, result)
}

async function main() {
  const sdl = await schemaSource()
  publicSchema = g.buildSchema(sdl)
  fullSchema = withInternal(publicSchema)
  schema = fullSchema
  seed()
  const server = http.createServer((req, res) => handle(req, res).catch(e => { console.error(e); try { json(res, 500, { errors: [{ message: String(e) }] }) } catch (x) {} }))
  server.on("connection", so => { sockets.add(so); so.on("close", () => sockets.delete(so)) })
  server.keepAliveTimeout = 600000   // like Linear's edge: idle connections stay open
  server
    .listen(PORT, "127.0.0.1", () => console.log("fake-linear: http://127.0.0.1:" + PORT + "/graphql (key " + KEY + ")"))
}

if (require.main === module) main().catch(e => { console.error(e); process.exit(1) })
module.exports = { main }
