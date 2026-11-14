// Run: node tests/helpers.test.js
// The pure helpers: reading Linear's answers (Linear.js) and what the board
// does on top (Issues, Edit, Recur, Inbox, Markdown, Dates). The requests
// themselves are checked by tests/api.test.js. Every helper is reached
// through L; tests/refs.test.js checks each lives where the QML looks for it.
const assert = require("assert")
const { load } = require("./load")
const L = Object.assign({}, ...["Linear", "Issues", "Edit", "Recur", "Inbox", "Markdown", "Dates"].map(load))
const plain = v => JSON.parse(JSON.stringify(v))

const states = [
  { id: "done", type: "completed", position: 0 },
  { id: "todo", type: "unstarted", position: 0 },
  { id: "back", type: "backlog", position: 0 },
  { id: "prog", type: "started", position: 1 },
  { id: "rev", type: "started", position: 2 },
  { id: "canc", type: "canceled", position: 0 }
]
assert.deepStrictEqual(plain(L.sortStates(states).map(s => s.id)), ["back", "todo", "prog", "rev", "done", "canc"])
assert.deepStrictEqual(plain(L.visibleStates(states, null).map(s => s.id)), ["back", "todo", "prog", "rev", "done"])
const hidden = L.toggleHidden(states, null, "canc")
assert.deepStrictEqual(plain(hidden), [])
assert.deepStrictEqual(plain(L.toggleHidden(states, hidden, "back")), ["back"])
assert.strictEqual(L.positionForNewState(states, "started"), 3)
assert.deepStrictEqual(plain(L.positionSwap(states, "prog", 1)), [{ id: "prog", position: 2 }, { id: "rev", position: 1 }])
assert.strictEqual(L.positionSwap(states, "todo", 1), null) // cannot cross categories

const raw = n => ({ id: "i" + n, identifier: "ENG-" + n, title: "T" + n, priority: 2, sortOrder: n,
  state: { id: "todo" }, labels: { nodes: [{ id: "bug" }] }, assignee: { id: "u", name: "Ann Lee" } })
let issues = [1, 2, 3].map(n => L.toIssue(raw(n)))
assert.strictEqual(issues[0].assignee.initials, "AL")
assert.deepStrictEqual(plain(L.issueFilter("t", "", "")).team, { id: { eq: "t" } })

// move i3 to top of todo
let m = L.planMove(issues, "i3", "todo", 0)
assert.strictEqual(m.sortOrder, 0)
// dropping in place is a no-op
assert.strictEqual(L.planMove(issues, "i2", "todo", 1), null)
assert.strictEqual(L.planMove(issues, "i2", "todo", 2), null)
// move i1 between i2 and i3
m = L.planMove(issues, "i1", "todo", 2)
assert.strictEqual(m.sortOrder, 2.5)
// move to empty column
assert.strictEqual(L.planMove(issues, "i1", "prog", 0).sortOrder, 0)
issues = L.patchIssue(issues, "i1", { stateId: "prog" })
assert.deepStrictEqual(plain(L.issuesIn(issues, "todo").map(i => i.id)), ["i2", "i3"])

const labels = L.mergeLabels([{ id: "bug", name: "Bug", color: "#eb5757" }, { id: "g", name: "Group", isGroup: true }],
  [{ id: "bug", name: "Bug" }, { id: "doc", name: "docs" }])
assert.deepStrictEqual(plain(labels.map(l => l.id)), ["bug", "doc"])
assert.ok(L.issueMatches(issues[1], labels, "bug", []))
assert.ok(L.issueMatches(issues[1], labels, "eng-2", []))
assert.ok(!L.issueMatches(issues[1], labels, "", ["doc"]))
assert.strictEqual(L.errorMessage({ errors: [{ message: "x", extensions: { userPresentableMessage: "Nice" } }] }, 200), "Nice")

// new fields
const full = L.toIssue({ ...raw(9), dueDate: "2026-10-30", estimate: 3, cycle: { id: "c1" },
  parent: { id: "i1", identifier: "ENG-1", title: "T1" } })
assert.strictEqual(full.dueDate, "2026-10-30")
assert.strictEqual(full.estimate, 3)
assert.strictEqual(full.cycleId, "c1")
assert.strictEqual(full.parent.identifier, "ENG-1")
assert.strictEqual(L.toIssue(raw(8)).estimate, null)
assert.deepStrictEqual(plain(L.childrenOf([full].concat(issues), "i1").map(i => i.id)), ["i9"])
assert.strictEqual(L.issueByIdentifier(issues, " eng-2 ").id, "i2")

// assignee / priority filters
const me = { ...issues[0], assignee: { id: "u" } }, nobody = { ...issues[0], assignee: null }
assert.ok(L.passesFilters(me, "me", "u", -1))
assert.ok(!L.passesFilters(nobody, "me", "u", -1))
assert.ok(L.passesFilters(nobody, "none", "u", -1))
assert.ok(!L.passesFilters(me, "none", "u", -1))
assert.ok(L.passesFilters(me, "u", "x", -1))
assert.ok(!L.passesFilters(me, "", "u", 1))
assert.ok(L.passesFilters(me, "", "u", 2))

// members
const members = L.toMembers([{ id: "b", name: "Zed" }, { id: "u", name: "Me Myself" }, { id: "a", name: "Anna", active: false }, { id: "c", name: "Bob" }], "u")
assert.deepStrictEqual(plain(members.map(m => m.id)), ["u", "c", "b"])

// estimates
assert.deepStrictEqual(plain(L.estimateOptions({ estimationType: "notUsed" })), [])
assert.deepStrictEqual(plain(L.estimateOptions({ estimationType: "fibonacci", estimationAllowZero: true }).map(o => o.value)), [0, 1, 2, 3, 5, 8])
assert.deepStrictEqual(plain(L.estimateOptions({ estimationType: "tShirt", estimationExtended: true }).map(o => o.label)), ["XS", "S", "M", "L", "XL", "XXL", "XXXL"])
assert.strictEqual(L.estimateLabel({ estimationType: "linear" }, 1), "1 pt")

// dates
assert.strictEqual(L.parseDate("2026-2-3"), "2026-02-03")
assert.strictEqual(L.parseDate("3.2.2026"), "2026-02-03")
assert.strictEqual(L.parseDate("2026-02-30"), null)
assert.strictEqual(L.parseDate("tomorrow"), null)
assert.strictEqual(L.parseDate(" "), "")
assert.strictEqual(L.isoDate(L.addDays(new Date(2026, 11, 31), 1)), "2027-01-01")
assert.deepStrictEqual(plain(L.dueInfo("2026-10-20", "2026-10-26")), { text: "Oct 20", level: "overdue" })
assert.deepStrictEqual(plain(L.dueInfo("2026-10-26", "2026-10-26")), { text: "Today", level: "today" })
assert.strictEqual(L.dueInfo("2027-01-05", "2026-10-26").text, "Jan 5 2027")

// comments, cycles
const cs = L.sortComments([{ createdAt: "2026-02" }, { createdAt: "2026-01" }].map(c => L.toComment({ id: c.createdAt, ...c })))
assert.deepStrictEqual(plain(cs.map(c => c.id)), ["2026-01", "2026-02"])
assert.strictEqual(L.cycleLabel(L.toCycles([{ id: "c", number: 4, isActive: true }])[0]), "Cycle 4 (current)")

// inbox
const inbox = L.toInbox([
  { id: "a", title: "Old", createdAt: "2026-10-01T10:00:00Z", readAt: null },
  { id: "b", title: "New", createdAt: "2026-10-26T09:00:00Z", readAt: null, actor: { name: "Ann" },
    issue: { id: "i1", identifier: "ENG-1", url: "u", team: { id: "t" } }, comment: { body: "hi\n there" } },
  { id: "c", title: "Snoozed", createdAt: "2026-10-20T10:00:00Z", snoozedUntilAt: "2099-01-01T00:00:00Z" },
  { id: "d", title: "Read", createdAt: "2026-10-25T10:00:00Z", readAt: "2026-10-25T11:00:00Z" }
], "2026-10-26T10:00:00Z")
assert.deepStrictEqual(plain(inbox.map(n => n.id)), ["b", "d", "a"])
assert.strictEqual(inbox[0].identifier, "ENG-1")
assert.strictEqual(inbox[0].snippet, "hi there")
assert.strictEqual(inbox[0].actor, "Ann")
assert.deepStrictEqual(plain(L.newUnread(inbox, "")), [])
assert.deepStrictEqual(plain(L.newUnread(inbox, "2026-10-02T00:00:00Z").map(n => n.id)), ["b"])
assert.strictEqual(L.newestTime(inbox), "2026-10-26T09:00:00Z")
assert.strictEqual(L.ago("2026-10-26T09:00:00Z", new Date("2026-10-26T10:30:00Z")), "1h")
assert.deepStrictEqual(plain(L.markReadVariables(["x", "y"], "T")), { readAt: "T", id0: "x", id1: "y" })

// grouping like Linear's inbox
const grouped = L.toInbox([
  { id: "x1", groupingKey: "g", createdAt: "2", readAt: "r", title: "newest" },
  { id: "x2", groupingKey: "g", createdAt: "1", readAt: null, comment: { body: "c" } },
  { id: "y", groupingKey: "h", createdAt: "3", readAt: "r" }
], "9")
assert.deepStrictEqual(plain(grouped.map(n => [n.id, n.ids, n.read, n.count])), [["y", ["y"], true, 1], ["x1", ["x1", "x2"], false, 2]])
assert.strictEqual(grouped[1].snippet, "c")

// inbox filters
const fin = L.toInbox([
  { id: "1", createdAt: "3", category: "mentions", issue: { id: "i", team: { id: "t1", name: "Web" }, project: { id: "p1", name: "Shop" } } },
  { id: "2", createdAt: "2", category: "assignments", readAt: "x", issue: { id: "j", team: { id: "t2", name: "Ops" } } },
  { id: "3", createdAt: "1", category: "mentions", project: { id: "p1", name: "Shop", url: "pu" } }
], "9")
assert.strictEqual(fin[2].url, "pu")
assert.deepStrictEqual(plain(fin.filter(n => L.inboxMatches(n, { teamId: "", projectId: "p1", category: "" })).map(n => n.id)), ["1", "3"])
assert.deepStrictEqual(plain(fin.filter(n => L.inboxMatches(n, { teamId: "", projectId: "none", category: "" })).map(n => n.id)), ["2"])
assert.deepStrictEqual(plain(fin.filter(n => L.inboxMatches(n, { teamId: "t1", projectId: "", category: "mentions" })).map(n => n.id)), ["1"])
const facets = L.inboxFacets(fin)
assert.deepStrictEqual(plain(facets.teams.map(t => [t.label, t.unread])), [["Ops", 0], ["Web", 1]])
assert.deepStrictEqual(plain(facets.projects.map(p => [p.label, p.total])), [["Shop", 2], ["No project", 1]])
assert.deepStrictEqual(plain(facets.categories.map(c => c.label)), ["Assigned", "Mentions"])
// kinds counted within the chosen project
const inP1 = L.inboxFacets(fin, { projectId: "p1" })
assert.deepStrictEqual(plain(inP1.categories.map(c => [c.label, c.total])), [["Mentions", 2]])
assert.deepStrictEqual(plain(inP1.projects.map(p => p.label)), ["Shop", "No project"])

// relations
const rels = L.toRelations({
  relations: { nodes: [{ id: "r1", type: "blocks", relatedIssue: { id: "o1", identifier: "E-1", title: "a", state: { name: "Todo", type: "unstarted" } } },
    { id: "r2", type: "related", relatedIssue: { id: "o2", identifier: "E-2", title: "b" } }] },
  inverseRelations: { nodes: [{ id: "r3", type: "blocks", issue: { id: "o3", identifier: "E-3", title: "c", state: { name: "Done", type: "completed" } } },
    { id: "r4", type: "related", issue: { id: "o2", identifier: "E-2", title: "b" } }] }
})
assert.deepStrictEqual(plain(rels.map(r => L.relationLabel(r.type, r.inverse) + " " + r.issue.identifier)), ["Blocks E-1", "Blocked by E-3", "Related to E-2"])
assert.ok(rels[1].issue.done)
assert.deepStrictEqual(plain(L.relationInput("blockedBy", "me", "x")), { issueId: "x", relatedIssueId: "me", type: "blocks" })
assert.deepStrictEqual(plain(L.relationInput("duplicate", "me", "x")), { issueId: "me", relatedIssueId: "x", type: "duplicate" })
assert.strictEqual(L.sourceLabel("sentry", ""), "Sentry")
assert.strictEqual(L.sourceLabel("", "https://www.example.com/x"), "example.com")

// history
assert.strictEqual(L.historyText({ actor: { name: "Ann" }, fromState: { name: "Todo" }, toState: { name: "Done" } }), "Ann moved from Todo to Done")
assert.strictEqual(L.historyText({ botActor: { name: "Sentry" }, toPriority: 1, fromPriority: 0 }), "Sentry set priority Urgent")
assert.strictEqual(L.historyText({ actor: { name: "Ann" } }), "")

// markdown and mentions
assert.strictEqual(L.displayMarkdown("see ![shot](https://u/x.png) and https://linear.app/acme/profiles/ann"),
  "see [🖼 shot](https://u/x.png) and [@ann](https://linear.app/acme/profiles/ann)")
assert.strictEqual(L.displayMarkdown("[x](https://linear.app/acme/profiles/ann)"), "[x](https://linear.app/acme/profiles/ann)")
assert.strictEqual(L.displayMarkdown("hi https://linear.app/acme/profiles/ann and [docs](https://d.io/a)", "#ffcc00"),
  'hi <a href="https://linear.app/acme/profiles/ann" style="text-decoration:none"><span style="color:#ffcc00"><b>@ann</b></span></a>' +
  ' and <a href="https://d.io/a"><span style="color:#ffcc00">docs</span></a>')
assert.strictEqual(L.displayMarkdown("see https://x.io/a<b>", "#fff"), 'see <a href="https://x.io/a"><span style="color:#fff">https://x.io/a</span></a>&lt;b>')
// Raw HTML from issue text is shown as text, code is left alone.
assert.strictEqual(L.displayMarkdown('<img src="http://t.io/p.gif"> a < b'), '&lt;img src="http://t.io/p.gif"> a < b')
assert.strictEqual(L.displayMarkdown("use `<div>` here"), "use `<div>` here")
assert.strictEqual(L.displayMarkdown("```\n<b>x</b>\n```\n<b>y</b>"), "```\n<b>x</b>\n```\n&lt;b>y&lt;/b>")
assert.strictEqual(L.displayMarkdown("<https://x.io/a>"), "https://x.io/a")
assert.strictEqual(L.displayMarkdown("[a <i>b</i> & c](https://x.io)", "#fff"), '<a href="https://x.io"><span style="color:#fff">a &lt;i&gt;b&lt;/i&gt; &amp; c</span></a>')
assert.ok(L.openable("https://linear.app/x") && L.openable("mailto:a@b.c") && L.openable("HTTP://x.io"))
assert.ok(!L.openable("file:///etc/passwd") && !L.openable("-x") && !L.openable("javascript:alert(1)") && !L.openable("https://a b") && !L.openable(""))
assert.deepStrictEqual(plain(L.mentionQuery("hi @ma", 6)), { query: "ma", start: 3 })
assert.strictEqual(L.mentionQuery("mail@x", 6), null)
assert.deepStrictEqual(plain(L.mentionMatches([{ name: "ann", fullName: "Ann Lee", url: "u" }, { name: "eva", fullName: "Eva", url: "v" }], "an").map(m => m.name)), ["ann"])

// snooze and inbox events
assert.strictEqual(L.snoozeUntil("tomorrow", new Date(2026, 9, 26, 15, 0)).getDate(), 27)
assert.strictEqual(L.snoozeUntil("week", new Date(2026, 9, 26, 15, 0)).getDay(), 1) // Oct 26 2026 is a Monday -> next Monday
assert.strictEqual(L.snoozeUntil("week", new Date(2026, 9, 26, 15, 0)).getDate(), 2)
const ev = L.toInbox([{ id: "a", groupingKey: "g", createdAt: "2", subtitle: "Assigned by Sentry" },
  { id: "b", groupingKey: "g", createdAt: "1", subtitle: "Priority set as urgent by Sentry" }], "9")
assert.strictEqual(L.inboxEventsText(ev[0]), "also: Priority set as urgent")

// inbox without Linear's internal fields (Q_INBOX_PUBLIC): made up the same way
const pub = L.toInbox([
  { id: "p1", type: "issueAssignedToYou", createdAt: "3", actor: { displayName: "ann" }, issue: { id: "i9", title: "Fix login", identifier: "ENG-9" } },
  { id: "p2", type: "issueStatusChanged", createdAt: "2", readAt: "r", issue: { id: "i9", title: "Fix login" } },
  { id: "p3", type: "projectUpdateCreated", createdAt: "1", project: { id: "pr", name: "Shop", url: "pu" } },
  { id: "p4", type: "somethingNewLater", createdAt: "0" }
], "9")
assert.deepStrictEqual(plain(pub.map(n => [n.groupingKey, n.title, n.subtitle, n.ids.length])), [
  ["issue#i9", "Fix login", "Assigned to you by ann", 2],
  ["project#pr", "Shop", "New project update", 1],
  ["p4", "Linear", "Something new later", 1]])
assert.strictEqual(L.inboxEventsText(pub[0]), "also: Status changed")
// the full name, like Linear's own subtitles; a bot by its name
assert.strictEqual(L.toNotification({ id: "n", type: "issueMention", actor: { name: "Ann Smith", displayName: "ann" } }).subtitle, "Mentioned you by Ann Smith")
assert.strictEqual(L.toNotification({ id: "n", type: "issueMention", botActor: { name: "Sentry" } }).subtitle, "Mentioned you by Sentry")
// Linear's own texts win, also an empty subtitle
assert.strictEqual(L.toNotification({ id: "x", subtitle: "", title: "T", groupingKey: "g", type: "issueMention" }).subtitle, "")
assert.strictEqual(L.toNotification(null).title, "Linear")
assert.strictEqual(L.notificationText("issueMention"), "Mentioned you")
assert.strictEqual(L.notificationText(""), "Notification")
assert.strictEqual(L.internalFieldsGone('Cannot query field "notificationsUnreadCount" on type "Query".'), true)
assert.strictEqual(L.internalFieldsGone('Cannot query field "inboxUrl" on type "Notification".'), true)
assert.strictEqual(L.internalFieldsGone('Cannot query field "identifier" on type "Issue".'), false)
assert.strictEqual(L.internalFieldsGone("Cannot reach Linear."), false)

// paging the inbox, a lost check, the bar's view of inbox.json
assert.strictEqual(L.enoughUnread(pub, 1), true)
assert.strictEqual(L.enoughUnread(pub, 4), false)
assert.strictEqual(L.enoughUnread(pub, 0), true)
assert.strictEqual(L.enoughUnread(pub, -1), false)   // no count: never stops early
assert.strictEqual(L.loadStuck(0, 1e12), false)
assert.strictEqual(L.loadStuck(1e12, 1e12 + L.LOAD_GIVE_UP_MS), false)
assert.strictEqual(L.loadStuck(1e12, 1e12 + L.LOAD_GIVE_UP_MS + 1), true)
{
  const now = Date.parse("2026-11-14T12:00:00Z")
  const at = min => new Date(now - min * 60000).toISOString()
  assert.deepStrictEqual(plain(L.barHealth(null, now)), { stale: false, note: "" })
  assert.deepStrictEqual(plain(L.barHealth({ connected: false }, now)), { stale: false, note: "" })
  assert.deepStrictEqual(plain(L.barHealth({ connected: true, checkedAt: at(1) }, now)), { stale: false, note: "" })
  assert.deepStrictEqual(plain(L.barHealth({ connected: true, checkedAt: at(1), error: "Cannot reach Linear." }, now)),
    { stale: false, note: "Last check failed: Cannot reach Linear." })
  assert.deepStrictEqual(plain(L.barHealth({ connected: true, checkedAt: at(12) }, now)), { stale: true, note: "Not updated for 12 min" })
  assert.deepStrictEqual(plain(L.barHealth({ connected: true, checkedAt: at(180), error: "x" }, now)), { stale: true, note: "Not updated for 3 h: x" })
  // an older board (before this version) wrote no times
  assert.strictEqual(L.barHealth({ connected: true }, now).stale, true)
  assert.deepStrictEqual(plain(L.barHealth({ connected: true, startedAt: at(1) }, now)), { stale: false, note: "Loading the inbox…" })
  assert.strictEqual(L.barHealth({ connected: true, startedAt: at(20) }, now).stale, true)
  assert.strictEqual(L.newerWriter({ startedAt: at(5) }, ""), true)
  assert.strictEqual(L.newerWriter({ startedAt: at(5) }, at(1)), false)
  assert.strictEqual(L.newerWriter({ startedAt: at(1) }, at(5)), true)
  assert.strictEqual(L.newerWriter({}, at(5)), true)
}

// rate limit
assert.strictEqual(L.isRateLimited(null, 429), true)
assert.strictEqual(L.isRateLimited({ errors: [{ message: "x", extensions: { code: "RATELIMITED" } }] }, 400), true)
assert.strictEqual(L.isRateLimited({ errors: [{ message: "x" }] }, 400), false)
assert.strictEqual(L.isRateLimited(null, 500), false)
assert.strictEqual(L.rateLimitUntil(String(5e12), null, 1e12), 1e12 + 3600000)   // capped at an hour
assert.strictEqual(L.rateLimitUntil(String(1e12 + 5000), null, 1e12), 1e12 + 5000)
assert.strictEqual(L.rateLimitUntil(null, "30", 1e12), 1e12 + 30000)
assert.strictEqual(L.rateLimitUntil("", "", 1e12), 1e12 + 60000)
assert.strictEqual(L.rateLimitUntil("garbage", null, 1e12), 1e12 + 60000)
assert.strictEqual(L.errorMessage(null, 429), "Linear's rate limit was reached. Trying again in a while.")

// sorting and grouping
const vi = [
  { id: "a", priority: 0, sortOrder: 1, dueDate: "", updatedAt: "1", createdAt: "3", labelIds: [], assignee: null, projectId: "" },
  { id: "b", priority: 1, sortOrder: 2, dueDate: "2026-11-01", updatedAt: "3", createdAt: "1", labelIds: ["bug"], assignee: { id: "u", name: "Zed" }, projectId: "" },
  { id: "c", priority: 3, sortOrder: 3, dueDate: "2026-10-01", updatedAt: "2", createdAt: "2", labelIds: [], assignee: { id: "v", name: "Ann" }, projectId: "" }
]
assert.deepStrictEqual(plain(L.arrange(vi, "priority", "none", {}).map(i => i.id)), ["b", "c", "a"])
assert.deepStrictEqual(plain(L.arrange(vi, "due", "none", {}).map(i => i.id)), ["c", "b", "a"])
assert.deepStrictEqual(plain(L.arrange(vi, "updated", "none", {}).map(i => i.id)), ["b", "c", "a"])
assert.deepStrictEqual(plain(L.arrange(vi, "manual", "assignee", {}).map(i => i.id)), ["c", "b", "a"])
assert.strictEqual(L.groupOf(vi[1], "label", { labels: [{ id: "bug", name: "Bug" }] }).label, "Bug")

// issue autocomplete
const pool = [
  { id: "1", identifier: "ENG-349", title: "Crash in feedback export", updatedAt: "1" },
  { id: "2", identifier: "ENG-34", title: "Login broken", updatedAt: "2" },
  { id: "3", identifier: "ENG-12", title: "Feedback form crashes", updatedAt: "3" }
]
assert.deepStrictEqual(plain(L.suggestIssues(pool, "34", [], 6).map(i => i.id)), ["2", "1"])
assert.deepStrictEqual(plain(L.suggestIssues(pool, "feedback", [], 6).map(i => i.id)), ["3", "1"])
assert.deepStrictEqual(plain(L.suggestIssues(pool, "eng-349", ["1"], 6)), [])
assert.deepStrictEqual(plain(L.suggestIssues(pool, "form crash", [], 6).map(i => i.id)), ["3"])

// project codes
assert.strictEqual(L.projectCode({ id: "a", name: "API" }, {}), "API")
assert.strictEqual(L.projectCode({ id: "a", name: "web-app" }, {}), "WEB-APP")
assert.strictEqual(L.projectCode({ id: "a", name: "Über new web app" }, {}), "ÜNWA")
assert.strictEqual(L.projectCode({ id: "a", name: "Marketplace" }, {}), "MARK")
assert.strictEqual(L.projectCode({ id: "a", name: "API" }, { a: "web" }), "WEB")
assert.strictEqual(L.projectCode(null, {}), "")

// old identifiers (team prefix changed)
const moved = L.toIssue({ ...raw(7), identifier: "ENG-63", previousIdentifiers: ["OPS-63"] })
assert.ok(L.issueMatches(moved, [], "ops-63", []))
assert.ok(L.issueMatches(moved, [], "OPS", []))
assert.strictEqual(L.issueByIdentifier([moved], "ops-63").identifier, "ENG-63")
assert.strictEqual(L.suggestIssues([moved], "OPS-6", [], 6)[0].identifier, "ENG-63")
assert.deepStrictEqual(plain(L.toIssue(raw(1)).previousIdentifiers), [])

// copying, templates, archiving
const ci = { identifier: "ENG-63", title: "Update deps", url: "https://linear.app/acme/issue/ENG-63", branchName: "update-deps-eng-63" }
assert.strictEqual(L.copyText(ci, "id"), "ENG-63")
assert.strictEqual(L.copyText(ci, "branch"), "update-deps-eng-63")
assert.strictEqual(L.copyText(ci, "markdown"), "[ENG-63 Update deps](https://linear.app/acme/issue/ENG-63)")
const tpls = L.issueTemplates([{ id: "1", name: "Deps", type: "issue", team: { id: "t" }, templateData: '{"title":"Update all dependencies"}' },
  { id: "2", name: "Other team", type: "issue", team: { id: "x" }, templateData: {} }, { id: "3", name: "Project", type: "project", templateData: {} },
  { id: "4", name: "All teams", type: "issue", team: null, templateData: { priority: 2 } }], "t")
assert.deepStrictEqual(plain(tpls.map(t => t.name)), ["All teams", "Deps"])
assert.strictEqual(tpls[1].data.title, "Update all dependencies")
assert.deepStrictEqual(plain(L.templateDataFrom({ title: "a", priority: 2, labelIds: ["l"], projectId: "p", estimate: null })),
  { title: "a", description: "", priority: 2, labelIds: ["l"], projectId: "p" })
assert.deepStrictEqual(plain(L.closedBeforeFilter("t", 30)).or[0], { completedAt: { lt: "-P30D" } })

// trash: only trashed ones, newest deletion first, with the day they go
{
  const now = new Date("2026-10-27T12:00:00Z")
  const f = L.trashFilter("t1", now)
  assert.strictEqual(f.team.id.eq, "t1")
  assert.strictEqual(f.archivedAt.gt, "2026-09-27T12:00:00.000Z")
  const node = (id, trashed, archivedAt) => ({ id, identifier: id, title: id, trashed, archivedAt, state: { id: "s", name: "Todo", color: "#fff", type: "unstarted" }, labels: { nodes: [] }, team: { id: "t1", key: "T", name: "T" } })
  const t = L.toTrash([node("A", true, "2026-10-01T10:00:00.000Z"), node("B", false, "2026-10-20T10:00:00.000Z"), node("C", true, "2026-10-25T10:00:00.000Z"), null])
  assert.deepStrictEqual(t.map(i => i.id), ["C", "A"])
  assert.strictEqual(t[1].purgeAt, "2026-10-31T10:00:00.000Z")
}

// cycles: only what changed is sent; dates keep their time of day
{
  const c = L.toCycle({ id: "c1", number: 7, name: null, description: "", startsAt: "2026-11-02T00:00:00.000Z", endsAt: "2026-11-16T00:00:00.000Z", isNext: true })
  assert.strictEqual(c.name, "")
  assert.strictEqual(c.isNext, true)
  const day = iso => { const d = new Date(iso); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0") }
  assert.deepStrictEqual(JSON.parse(JSON.stringify(L.cycleInput(c, "", day(c.startsAt), day(c.endsAt), "").input)), {})
  assert.deepStrictEqual(JSON.parse(JSON.stringify(L.cycleInput(c, " Sprint 7 ", "", "", "Ship it").input)), { name: "Sprint 7", description: "Ship it" })
  const moved = L.cycleInput(c, "", day(c.startsAt), "2026-11-20", "").input
  assert.strictEqual(moved.startsAt, undefined)
  assert.strictEqual(new Date(moved.endsAt).getHours(), new Date(c.endsAt).getHours())
  assert.strictEqual(day(moved.endsAt), "2026-11-20")
  assert.ok(L.cycleInput(c, "", day(c.startsAt), "2026-10-01", "").error)
  assert.ok(L.cycleInput(c, "", "soon", "", "").error)
  assert.strictEqual(L.moveToDay(c.startsAt, "nope"), "")
}

// done window: what the board loads, and why an issue is not on it
{
  const plainF = w => JSON.parse(JSON.stringify(L.issueFilter("t", "p", w)))
  assert.strictEqual(plainF("2weeks").or[1].completedAt.gt, "-P2W")
  assert.strictEqual(plainF(undefined).or[1].completedAt.gt, "-P2W")
  assert.strictEqual(plainF("month").or[2].canceledAt.gt, "-P1M")
  assert.strictEqual(plainF("all").or, undefined)
  assert.strictEqual(plainF("all").project.id.eq, "p")
  assert.deepStrictEqual(plainF("none").state, { type: { nin: ["completed", "canceled", "duplicate"] } })
  assert.strictEqual(L.doneWindow("bogus").id, "2weeks")

  const now = new Date("2026-10-27T12:00:00Z")
  const base = { teamId: "t", teamName: "Engineering", projectId: "p", projectName: "API", doneWindow: "2weeks", hidden: [], shown: false, filtered: true, now }
  const issue = { id: "i", teamId: "t", teamName: "Engineering", projectId: "p", projectName: "API", stateType: "completed", stateId: "s", stateName: "Done", completedAt: "2026-03-26T15:41:45Z" }
  assert.strictEqual(L.offBoardReason(issue, Object.assign({}, base, { shown: true })), "")
  assert.ok(/^Done on Mar 26, 2026; .*past 2 weeks .*Completed: All/.test(L.offBoardReason(issue, base)))
  assert.ok(/no done issues/.test(L.offBoardReason(issue, Object.assign({}, base, { doneWindow: "none" }))))
  assert.ok(/^Hidden by the board's filters/.test(L.offBoardReason(issue, Object.assign({}, base, { doneWindow: "all", filtered: false }))))
  assert.ok(/^In project Web/.test(L.offBoardReason(Object.assign({}, issue, { projectId: "w", projectName: "Web" }), base)))
  assert.ok(/^In team Other/.test(L.offBoardReason(Object.assign({}, issue, { teamId: "x", teamName: "Other" }), base)))
  assert.ok(/^Archived on/.test(L.offBoardReason(Object.assign({}, issue, { archivedAt: "2026-04-01T00:00:00Z" }), base)))
  assert.ok(/column Done is hidden/.test(L.offBoardReason(Object.assign({}, issue, { stateType: "started" }), Object.assign({}, base, { hidden: ["s"] }))))
}

// archived: only archived and not deleted, newest first; filter by ID or title words
{
  const st = { id: "s", name: "Done", color: "#fff", type: "completed" }
  const node = (id, title, archivedAt, trashed) => ({ id, identifier: id, title, archivedAt, trashed, previousIdentifiers: ["OLD-" + id], state: st, labels: { nodes: [] }, team: { id: "t", key: "T", name: "T" } })
  const a = L.toArchived([node("A-1", "Fix login", "2026-10-01T00:00:00Z", false), node("A-2", "Gone", "2026-10-20T00:00:00Z", true), node("A-3", "Page loads slowly", "2026-10-25T00:00:00Z", null), node("A-4", "Open", null, false)])
  assert.deepStrictEqual(a.map(i => i.identifier), ["A-3", "A-1"])
  assert.ok(L.binMatches(a[1], "a-1"))
  assert.ok(L.binMatches(a[1], "old-a-1"))
  assert.ok(L.binMatches(a[0], "slowly PAGE"))
  assert.ok(!L.binMatches(a[0], "page fast"))
  assert.ok(L.binMatches(a[0], "  "))
  assert.strictEqual(L.archivedFilter("t").archivedAt.null, false)
}

// Checks against Linear's schema are in tests/api.test.js.
// ---- 0.8 helpers ----
assert.deepStrictEqual(plain(L.relationRestoreInput({ type: "blocks", inverse: true, issue: { id: "o" } }, "me")), { issueId: "o", relatedIssueId: "me", type: "blocks" })
assert.deepStrictEqual(plain(L.relationRestoreInput({ type: "related", inverse: false, issue: { id: "o" } }, "me")), { issueId: "me", relatedIssueId: "o", type: "related" })
assert.strictEqual(L.passesCycle({ cycleId: "c1" }, "", ""), true)
assert.strictEqual(L.passesCycle({ cycleId: "c1" }, "current", "c1"), true)
assert.strictEqual(L.passesCycle({ cycleId: "c2" }, "current", "c1"), false)
assert.strictEqual(L.passesCycle({ cycleId: "c1" }, "current", ""), false)
assert.strictEqual(L.passesCycle({ cycleId: "" }, "none", "c1"), true)
assert.strictEqual(L.passesCycle({ cycleId: "c2" }, "c2", "c1"), true)
assert.deepStrictEqual(plain(L.markdownImages("a ![x](https://uploads.linear.app/a/b) b ![y](https://e.com/i.png \"t\") ![x](https://uploads.linear.app/a/b)")),
  ["https://uploads.linear.app/a/b", "https://e.com/i.png"])
assert.deepStrictEqual(plain(L.splitImages("Intro\n\n![shot](https://u/1)\n\nMore text")),
  [{ text: "Intro" }, { image: true, url: "https://u/1", alt: "shot" }, { text: "More text" }])
assert.deepStrictEqual(plain(L.splitImages("plain")), [{ text: "plain" }])
assert.strictEqual(L.removeImage("Intro\n\n![a](https://uploads.linear.app/x/y)\n\nMore ![b](https://uploads.linear.app/x/y) end\n![c](https://other/z)",
  "https://uploads.linear.app/x/y"), "Intro\n\nMore end\n![c](https://other/z)")
assert.strictEqual(L.removeImage("![a](https://u/1.png)", "https://u/1.png"), "")
assert.deepStrictEqual(plain(L.splitImages("")), [{ text: "" }])
assert.strictEqual(L.parseIssueRef("https://linear.app/acme/issue/eng-12/some-title"), "ENG-12")
assert.strictEqual(L.parseIssueRef(" eng-7 "), "ENG-7")
assert.strictEqual(L.parseIssueRef("fix login"), "")
const th = L.threadComments([
  L.toComment({ id: "a", body: "", createdAt: "2026-01-01" }),
  L.toComment({ id: "r1", body: "", createdAt: "2026-01-03", parent: { id: "a" } }),
  L.toComment({ id: "b", body: "", createdAt: "2026-01-02" }),
  L.toComment({ id: "orphan", body: "", createdAt: "2026-01-04", parent: { id: "gone" } })
])
assert.deepStrictEqual(plain(th.map(t => t.comment.id + t.depth)), ["a0", "r11", "b0", "orphan0"])
const rs = L.reactionSummary([{ id: "x", emoji: "👍", userId: "me", user: "M" }, { id: "y", emoji: "👍", userId: "o", user: "O" }, { id: "z", emoji: "🎉", userId: "o" }], "me")
assert.deepStrictEqual(plain(rs.map(r => [r.char, r.count, r.mine])), [["👍", 2, "x"], ["🎉", 1, ""]])
// Linear answers with names: "+1" and "👍" are the same reaction
const rs2 = L.reactionSummary(L.toComment({ id: "c", reactions: [{ id: "a", emoji: "+1", user: { id: "me" } }, { id: "b", emoji: "👍", user: { id: "o" } }] }).reactions, "me")
assert.deepStrictEqual(plain(rs2.map(r => [r.emoji, r.char, r.count, r.mine])), [["+1", "👍", 2, "a"]])
assert.strictEqual(L.emojiChar("unicorn"), ":unicorn:")
const pal = L.paletteFilter([{ label: "Open inbox" }, { label: "New issue", keywords: "create" }, { label: "Toggle list view" }], "iss")
assert.deepStrictEqual(plain(pal.map(p => p.label)), ["New issue"])
assert.deepStrictEqual(plain(L.paletteFilter([{ label: "Go to inbox" }, { label: "Inbox: mark all read" }], "inbox").map(p => p.label)), ["Inbox: mark all read", "Go to inbox"])
const now = new Date(2026, 9, 26, 14, 0) // Monday
assert.strictEqual(L.reminderAt("tomorrow", now).getDate(), 27)
assert.strictEqual(L.reminderAt("monday", now).getDate(), 2)
assert.strictEqual(L.reminderAt("1h", now).getHours(), 15)
const iss = L.toIssue({ id: "i", state: { id: "s1", type: "started" }, priority: 3, sortOrder: 5, labels: { nodes: [{ id: "l1" }] }, projectMilestone: { id: "m1", name: "Beta" } })
assert.strictEqual(iss.milestoneName, "Beta")
assert.deepStrictEqual(plain(L.undoInput(iss, { stateId: "x", sortOrder: 1, addedLabelIds: ["l2"], assigneeId: "u", projectMilestoneId: null })),
  { stateId: "s1", sortOrder: 5, labelIds: ["l1"], assigneeId: null, projectMilestoneId: "m1" })
assert.deepStrictEqual(plain(L.groupUndo([{ id: "a", input: { priority: 1 } }, { id: "b", input: { priority: 2 } }, { id: "c", input: { priority: 1 } }])),
  [{ ids: ["a", "c"], input: { priority: 1 } }, { ids: ["b"], input: { priority: 2 } }])
assert.deepStrictEqual(plain(L.cycleStats([{ stateType: "completed" }, { stateType: "started" }, { stateType: "unstarted" }, { stateType: "canceled" }])),
  { total: 4, done: 2, started: 1, todo: 1, percent: 50 })
// recurring
const wk = { every: "week", start: "2026-10-27", last: "" } // a Tuesday
assert.strictEqual(L.recurDue(wk, "2026-10-26"), "")
assert.strictEqual(L.recurDue(wk, "2026-10-27"), "2026-10-27")
assert.strictEqual(L.recurDue(wk, "2026-10-30"), "2026-10-27")
assert.strictEqual(L.recurDue(Object.assign({}, wk, { last: "2026-10-27" }), "2026-10-30"), "")
assert.strictEqual(L.recurDue(Object.assign({}, wk, { last: "2026-10-27" }), "2026-11-03"), "2026-11-03")
assert.strictEqual(L.recurNext(wk, "2026-10-27"), "2026-11-03")
assert.strictEqual(L.recurNext(wk, "2026-10-01"), "2026-10-27")
const mo = { every: "month", start: "2026-01-31", last: "" }
assert.strictEqual(L.recurDue(mo, "2026-02-28"), "2026-02-28")
assert.strictEqual(L.recurNext(mo, "2026-02-28"), "2026-03-31")
const wd = { every: "weekday", start: "2026-10-27", last: "2026-10-30" }
assert.strictEqual(L.recurDue(wd, "2026-11-01"), "") // weekend, Friday done
assert.strictEqual(L.recurDue(wd, "2026-11-02"), "2026-11-02")
assert.strictEqual(L.recurStart("weekday", "2026-10-30"), "2026-11-02")
assert.strictEqual(L.recurStart("month", "2026-01-31"), "2026-02-28")
assert.strictEqual(L.recurStart("week", "2026-10-26"), "2026-11-02")
assert.strictEqual(L.toProject({ id: "p", projectMilestones: { nodes: [{ id: "b", name: "B", sortOrder: 2 }, { id: "a", name: "A", sortOrder: 1 }] } }).milestones[0].id, "a")

// Checklists
const md = "Intro\n\n- [ ] first\n  - [x] nested **bold**\n- plain\n```\n- [ ] code\n```\n1. [X] numbered"
const ps = plain(L.splitParts(md))
assert.deepStrictEqual(ps.filter(p => p.task).map(p => [p.line, p.checked, p.text, p.level]),
  [[2, false, "first", 0], [3, true, "nested **bold**", 1], [8, true, "numbered", 0]])
assert.ok(ps.some(p => p.text && p.text.indexOf("- [ ] code") >= 0))
assert.strictEqual(L.toggleTask(md, 2).split("\n")[2], "- [x] first")
assert.strictEqual(L.toggleTask(md, 3).split("\n")[3], "  - [ ] nested **bold**")
assert.strictEqual(L.toggleTask(md, 6), md) // code block line
assert.strictEqual(L.toggleTask(md, 0), md)
assert.strictEqual(L.toggleTask("- [ ] a [ ] b", 0), "- [x] a [ ] b")
assert.strictEqual(L.toggleTask("- [ ]\r\nx", 0), "- [x]\r\nx")
assert.deepStrictEqual(plain(L.countTasks(md)), { total: 3, done: 2 })
assert.deepStrictEqual(plain(L.splitParts("![a](https://x/y.png)")), [{ image: true, url: "https://x/y.png", alt: "a" }])
assert.deepStrictEqual(plain(L.splitParts("")), [{ text: "" }])
assert.deepStrictEqual(plain(L.taskShortcut("x\n  []", 6)), { start: 2, end: 6, text: "  - [ ] " })
assert.deepStrictEqual(plain(L.taskShortcut("- [ ]", 5)), { start: 0, end: 5, text: "- [ ] " })
assert.strictEqual(L.taskShortcut("a []", 4), null)
assert.deepStrictEqual(plain(L.listEnter("- [x] done", 10)), { start: 10, end: 10, text: "\n- [ ] " })
assert.deepStrictEqual(plain(L.listEnter("  * item", 8)), { start: 8, end: 8, text: "\n  * " })
assert.deepStrictEqual(plain(L.listEnter("9. item", 7)), { start: 7, end: 7, text: "\n10. " })
assert.deepStrictEqual(plain(L.listEnter("a\n- [ ] ", 8)), { start: 2, end: 8, text: "" })
assert.strictEqual(L.listEnter("plain", 5), null)
assert.strictEqual(L.listEnter("```\n- a", 7), null)

assert.strictEqual(L.untickTasks("- [x] a\n  - [X] b\n```\n- [x] c\n```"), "- [ ] a\n  - [ ] b\n```\n- [x] c\n```")
const rules = [{ id: "r1", issueId: "i9", teamId: "t", title: "Faktúra", every: "month", start: "2026-11-26", last: "" },
  { id: "r2", teamId: "t", title: "Report", every: "week", start: "2026-10-27", last: "" }]
assert.strictEqual(L.recurRuleFor(rules, { id: "i9", teamId: "x", title: "Iné" }).id, "r1")
assert.strictEqual(L.recurRuleFor(rules, { id: "i1", teamId: "t", title: "Report" }).id, "r2")
assert.strictEqual(L.recurRuleFor(rules, { id: "i1", teamId: "u", title: "Report" }), null)
assert.strictEqual(L.recurRuleFor([], { id: "i1" }), null)
assert.strictEqual(L.recurUpcoming(rules[0], "2026-10-26"), "2026-11-26")
assert.strictEqual(L.recurUpcoming(Object.assign({}, rules[0], { last: "2026-11-26" }), "2026-11-26"), "2026-12-26")
// A duplicate in another project is not part of the series.
const pr = [{ id: "a", teamId: "t", projectId: "p1", title: "Faktúra", every: "month", start: "2026-11-26", last: "" },
  { id: "b", issueId: "dup", teamId: "t", projectId: "p2", title: "Faktúra", every: "month", start: "2026-11-27", last: "" }]
assert.strictEqual(L.recurRuleFor(pr, { id: "x", teamId: "t", projectId: "p1", title: "Faktúra" }).id, "a")
assert.strictEqual(L.recurRuleFor(pr, { id: "dup", teamId: "t", projectId: "p2", title: "Faktúra" }).id, "b")
assert.strictEqual(L.recurRuleFor(pr, { id: "y", teamId: "t", projectId: "p2", title: "Faktúra" }).id, "b")
assert.strictEqual(L.recurRuleFor(pr, { id: "z", teamId: "t", projectId: "p3", title: "Faktúra" }), null)
assert.deepStrictEqual(plain(L.recurExistsFilter(pr[0], "2026-11-26").project), { id: { eq: "p1" } })
assert.deepStrictEqual(plain(L.recurExistsFilter({ teamId: "t", title: "x" }, "2026-11-26").project), { null: true })
const fr = [{ id: "a", issueId: "i1", teamId: "t", projectId: "p1", title: "Old" }, { id: "b", teamId: "t", title: "X" }]
assert.strictEqual(L.recurFollow(fr, { i1: { title: "Old", projectId: "p1" } }), null)
const fn = plain(L.recurFollow(fr, { i1: { title: "New", projectId: "p2", milestoneId: "m" } }))
assert.deepStrictEqual([fn[0].title, fn[0].projectId, fn[0].milestoneId, fn[1].title], ["New", "p2", "m", "X"])
// Deleting files: the internal mutation may disappear from Linear.
assert.strictEqual(L.hasMutation({ __type: { fields: [{ name: "fileUpload" }, { name: L.FILE_DELETE_FIELD }] } }, L.FILE_DELETE_FIELD), true)
assert.strictEqual(L.hasMutation({ __type: { fields: [{ name: "fileUpload" }] } }, L.FILE_DELETE_FIELD), false)
assert.strictEqual(L.hasMutation({ __type: null }, L.FILE_DELETE_FIELD), false)
assert.strictEqual(L.hasMutation(null, L.FILE_DELETE_FIELD), false)
assert.strictEqual(L.isSchemaGone('Cannot query field "fileUploadDangerouslyDelete" on type "Mutation".'), true)
assert.strictEqual(L.isSchemaGone("Cannot reach Linear. Check your connection."), false)
assert.strictEqual(L.isSchemaGone(undefined), false)
assert.strictEqual(L.fileDeleted({ fileUploadDangerouslyDelete: { success: true } }), true)
assert.strictEqual(L.fileDeleted({ fileUploadDangerouslyDelete: { success: false } }), false)
assert.strictEqual(L.fileDeleted({}), false)

// ---- Edit.js: what the issue editor saves ----
{
  const E = L
  const orig = E.toIssue({ id: "i1", identifier: "ENG-1", title: "Old", description: "Text", priority: 2, sortOrder: 1,
    state: { id: "todo" }, labels: { nodes: [{ id: "a" }, { id: "b" }] }, assignee: { id: "u1", name: "Ann Lee" },
    project: { id: "p1", name: "P" }, dueDate: "2026-11-01", estimate: 3, cycle: { id: "c1" },
    parent: { id: "par", identifier: "ENG-0", title: "Parent" }, projectMilestone: { id: "m1", name: "M1" } })
  // The editor showing the issue unchanged.
  const same = () => ({ title: "Old", description: "Text", stateId: "todo", priority: 2, labelIds: ["b", "a"], projectId: "p1",
    assigneeId: "u1", due: "2026-11-01", estimate: 3, cycleId: "c1", parent: { id: "par", identifier: "ENG-0" }, milestoneId: "m1" })
  const ctx = { member: id => ({ id, name: "Bob" }), milestoneName: id => id === "m2" ? "M2" : "" }
  const ch = (v, kind) => plain(E.issueChanges(orig, Object.assign(same(), v), kind || "props", ctx))

  // Nothing changed (labels in another order are the same set).
  assert.deepStrictEqual(ch({}), { input: {}, patch: {}, titleMissing: false })
  assert.deepStrictEqual(ch({}, "text"), { input: {}, patch: {}, titleMissing: false })
  // Only what changed is sent; the board's copy gets its own field names.
  assert.deepStrictEqual(ch({ stateId: "done", priority: 1 }).input, { stateId: "done", priority: 1 })
  assert.deepStrictEqual(ch({ assigneeId: "u2" }), { input: { assigneeId: "u2" }, patch: { assignee: { id: "u2", name: "Bob" } }, titleMissing: false })
  assert.deepStrictEqual(ch({ assigneeId: "" }).input, { assigneeId: null })
  assert.deepStrictEqual(ch({ labelIds: ["a"] }).input, { labelIds: ["a"] })
  assert.deepStrictEqual(ch({ cycleId: "" }), { input: { cycleId: null }, patch: { cycleId: "" }, titleMissing: false })
  assert.deepStrictEqual(ch({ estimate: null }).input, { estimate: null })
  assert.deepStrictEqual(ch({ parent: null }), { input: { parentId: null }, patch: { parent: null }, titleMissing: false })
  // Due date: typed as D.M.YYYY, cleared, or still being typed (waits).
  assert.deepStrictEqual(ch({ due: "5.11.2026" }).input, { dueDate: "2026-11-05" })
  assert.deepStrictEqual(ch({ due: "" }), { input: { dueDate: null }, patch: { dueDate: "" }, titleMissing: false })
  assert.deepStrictEqual(ch({ due: "5.11." }).input, {})
  // Milestones: a new one is named on the board; a new project without one
  // drops it on the board only (Linear does that itself).
  assert.deepStrictEqual(ch({ milestoneId: "m2" }).patch, { milestoneId: "m2", milestoneName: "M2" })
  assert.deepStrictEqual(ch({ projectId: "p2", milestoneId: "" }),
    { input: { projectId: "p2" }, patch: { projectId: "p2", milestoneId: "", milestoneName: "" }, titleMissing: false })
  assert.deepStrictEqual(ch({ projectId: "" }).input, { projectId: null })
  assert.deepStrictEqual(ch({ milestoneId: "" }).input, { projectMilestoneId: null })
  // Text: trimmed title, an empty one is not saved but marked; text kinds
  // do not send properties and the other way round.
  assert.deepStrictEqual(ch({ title: "  New  ", stateId: "done" }, "text").input, { title: "New" })
  assert.deepStrictEqual(ch({ title: " ", description: "More" }, "text"), { input: { description: "More" }, patch: { description: "More" }, titleMissing: true })
  assert.deepStrictEqual(ch({ title: "New" }).input, {})

  // New issues: only what is set, errors for a missing title or a bad date.
  assert.deepStrictEqual(plain(E.createInput({ teamId: "t", title: " T ", stateId: "todo", priority: 0, labelIds: [], due: "", estimate: null })),
    { input: { teamId: "t", title: "T", description: "", stateId: "todo", priority: 0, labelIds: [] } })
  assert.deepStrictEqual(plain(E.createInput(Object.assign(same(), { teamId: "t" }))).input,
    { teamId: "t", title: "Old", description: "Text", stateId: "todo", priority: 2, labelIds: ["b", "a"], projectId: "p1", assigneeId: "u1",
      dueDate: "2026-11-01", estimate: 3, cycleId: "c1", parentId: "par", projectMilestoneId: "m1" })
  assert.deepStrictEqual(plain(E.createInput({ title: "" })), { error: "title" })
  assert.deepStrictEqual(plain(E.createInput({ title: "T", due: "31.2.2026" })), { error: "due" })

  assert.strictEqual(E.fieldNames({ stateId: "x", sortOrder: 1, labelIds: [], addedLabelIds: [] }), "status, labels")
  assert.strictEqual(E.sameSet(["a", "b"], ["b", "a"]), true)
  assert.strictEqual(E.sameSet(["a"], ["a", "b"]), false)

  // One undo step for typing in a row: the oldest value of a field stays.
  const step = [{ id: "i1", input: { title: "Old" } }]
  const grown = E.mergeUndo(step, [{ id: "i1", input: { title: "Newer", description: "Text" } }, { id: "i2", input: { priority: 2 } }])
  assert.deepStrictEqual(plain(grown), [{ id: "i1", input: { title: "Old", description: "Text" } }, { id: "i2", input: { priority: 2 } }])
  assert.deepStrictEqual(plain(step), [{ id: "i1", input: { title: "Old" } }])   // the old list is not changed
  // The offline outbox joins updates of one issue in a row, nothing else.
  const U = "mutation IssueUpdate", wait = { query: U, variables: { id: "i1", input: { title: "A" } } }
  assert.strictEqual(E.outboxJoins(wait, U, { id: "i1", input: { title: "B" } }, false, U), true)
  assert.strictEqual(E.outboxJoins(wait, U, { id: "i1", input: { title: "B" } }, true, U), false)    // being sent
  assert.strictEqual(E.outboxJoins(wait, U, { id: "i2", input: { title: "B" } }, false, U), false)   // another issue
  assert.strictEqual(E.outboxJoins(wait, "mutation Other", { id: "i1", input: {} }, false, U), false)
  assert.strictEqual(E.outboxJoins({ query: "mutation Other", variables: wait.variables }, "mutation Other", wait.variables, false, U), false)
  assert.strictEqual(E.outboxJoins(undefined, U, wait.variables, false, U), false)
  assert.strictEqual(E.outboxJoins(wait, U, { id: "i1" }, false, U), false)
  // Two sends of one issue as one: the later values win.
  assert.deepStrictEqual(plain(E.mergeInput({ title: "A", priority: 1 }, { title: "B" })), { title: "B", priority: 1 })
  // A change that timed out and landed late is undone by sending the newer values again.
  const raw = { state: { id: "todo" }, priority: 2, title: "T", labels: { nodes: [{ id: "a" }, { id: "b" }] }, assignee: null }
  assert.deepStrictEqual(plain(E.reassertInput({ stateId: "prog", sortOrder: 5 }, [{ stateId: "todo", sortOrder: 1 }], raw)), { stateId: "prog" })
  assert.strictEqual(E.reassertInput({ stateId: "prog" }, [{ stateId: "todo" }], { state: { id: "prog" } }), null)    // landed in order
  assert.strictEqual(E.reassertInput({ stateId: "prog" }, [{ stateId: "todo" }], { state: { id: "done" } }), null)    // changed elsewhere since
  assert.strictEqual(E.reassertInput({ stateId: "prog" }, [], raw), null)
  assert.strictEqual(E.reassertInput({ priority: 3 }, [{ stateId: "todo" }], raw), null)                              // the stale one did not set it
  assert.deepStrictEqual(plain(E.reassertInput({ labelIds: ["c"] }, [{ labelIds: ["b", "a"] }], raw)), { labelIds: ["c"] })
  assert.deepStrictEqual(plain(E.reassertInput({ assigneeId: "me" }, [{ assigneeId: null }], raw)), { assigneeId: "me" })
  assert.strictEqual(E.reassertInput({ title: "New" }, [{ title: "T" }], raw).title, "New")
  // Creates carry their own id, so a create sent twice makes one issue.
  assert.match(E.newUuid(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
  assert.strictEqual(E.newUuid(() => 0), "00000000-0000-4000-8000-000000000000")
  assert.notStrictEqual(E.newUuid(), E.newUuid())
  const v = { input: { teamId: "t", title: "A" }, other: 1 }
  const withId = E.withClientId(v, () => 0)
  assert.strictEqual(withId.input.id, "00000000-0000-4000-8000-000000000000")
  assert.strictEqual(withId.other, 1)
  assert.strictEqual(v.input.id, undefined)                              // the original is not changed
  assert.strictEqual(E.withClientId(withId), withId)                     // an id is kept
  assert.deepStrictEqual(E.withClientId({ id: "x" }), { id: "x" })       // no input: unchanged
  assert.strictEqual(L.createdLookup(L.M_ISSUE_CREATE).query, L.Q_ISSUE)
  assert.strictEqual(L.createdLookup(L.M_COMMENT_CREATE).field, "comment")
  assert.strictEqual(L.createdLookup(L.M_ISSUE_UPDATE), null)
}
// After a suspend, requests from just before waking to a minute after give up sooner.
assert.strictEqual(L.wokeUp(1000, 3000), false)
assert.strictEqual(L.wokeUp(1000, 40000), true)
assert.strictEqual(L.wokeUp(0, 40000), false)
assert.strictEqual(L.requestTimeout(100000, 0), 30000)
assert.strictEqual(L.requestTimeout(100000, 102000), 8000)      // started 2 s before the wake was noticed
assert.strictEqual(L.requestTimeout(150000, 102000), 8000)
assert.strictEqual(L.requestTimeout(170000, 102000), 30000)     // more than a minute after
assert.strictEqual(L.requestTimeout(90000, 102000), 30000)      // long before
// Requests through curl: the config it reads from stdin, and what it printed.
{
  const q = v => '"' + String(v).replace(/[\r\n]/g, "").replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
  const conf = L.curlConfig("https://api.linear.app/graphql", "lin_api_k", '{"query":"q","variables":{"t":"a\\nb \\"c\\""}}', q)
  assert.match(conf, /^url = "https:\/\/api\.linear\.app\/graphql"$/m)
  assert.match(conf, /^header = "Authorization: lin_api_k"$/m)
  assert.match(conf, /^data-binary = "\{\\"query\\":\\"q\\"/m)
  assert.match(conf, /^write-out = "\\\\n%\{http_code\}"$/m)
  assert.ok(!/@/.test(conf.split("\n").find(l => /^data-binary/.test(l)).slice(15, 16)), "the body is never read as a file")
  assert.deepStrictEqual(plain(L.curlResult(0, '{"data":{}}\n200')), { status: 200, body: '{"data":{}}' })
  assert.deepStrictEqual(plain(L.curlResult(0, 'line1\nline2\n401')), { status: 401, body: "line1\nline2" })
  assert.deepStrictEqual(plain(L.curlResult(28, "")), { status: 0, body: "" })        // timed out
  assert.deepStrictEqual(plain(L.curlResult(0, "no code")), { status: 0, body: "" })
}
// Only a server on this machine may stand in for Linear's API.
assert.strictEqual(L.endpointFor(""), L.ENDPOINT)
assert.strictEqual(L.endpointFor("http://127.0.0.1:47123/graphql"), "http://127.0.0.1:47123/graphql")
assert.strictEqual(L.endpointFor("http://localhost/graphql"), "http://localhost/graphql")
assert.strictEqual(L.endpointFor("https://evil.example/graphql"), L.ENDPOINT)
assert.strictEqual(L.endpointFor("http://127.0.0.1.evil.example/graphql"), L.ENDPOINT)
assert.strictEqual(L.endpointFor("http://localhost@evil.example/graphql"), L.ENDPOINT)
console.log("ok")
