// Run: LINEAR_TEST_PROJECT=<project id> node tests/e2e/live.js [name filter]
// The board against the real Linear API, in a project kept for testing:
// the same isolated offscreen harness as tests/e2e/run.js, with your key
// (LINEAR_API_KEY, else ~/.config/omarchy-linear-board/api-key). Between
// the board and Linear sits a local proxy that can lose, delay or refuse
// requests, so the failure paths run against Linear's real answers.
//
// Everything it makes has a title or name starting with "[bt]" and lives in
// that project (a label in its team); all of it is deleted at the end, also
// after a failure. Your inbox is only read, never changed.
const http = require("http"), https = require("https"), fs = require("fs"), path = require("path")
const H = require("./run.js")
const { ev, evs, waitFor, sleep, eq, ok } = H

const PROJECT = process.env.LINEAR_TEST_PROJECT
const KEY = (process.env.LINEAR_API_KEY || fs.readFileSync(path.join(process.env.HOME, ".config", "omarchy-linear-board", "api-key"), "utf8")).trim()
const ONLY = process.argv[2] ? new RegExp(process.argv[2], "i") : null
const PROXY = 47201
const TAG = "[bt]"
if (!PROJECT) { console.error("LINEAR_TEST_PROJECT=<project id> is needed"); process.exit(2) }

// ---- Linear, directly (to check what the board did, and to clean up) ----

function api(query, variables) {
  return new Promise((resolve, reject) => {
    const req = https.request("https://api.linear.app/graphql", { method: "POST", headers: { "Content-Type": "application/json", Authorization: KEY } }, res => {
      let d = ""
      res.on("data", c => d += c)
      res.on("end", () => {
        try {
          const j = JSON.parse(d)
          if (j.errors) reject(new Error(JSON.stringify(j.errors).slice(0, 400)))
          else resolve(j.data)
        } catch (e) { reject(new Error("HTTP " + res.statusCode + " " + d.slice(0, 200))) }
      })
    })
    req.on("error", reject)
    req.end(JSON.stringify({ query, variables: variables || {} }))
  })
}

const ISSUE = "id identifier title description priority dueDate estimate trashed archivedAt state { id name } assignee { id } project { id } " +
  "labels { nodes { id } } parent { id } comments { nodes { id body reactions { id emoji } } } " +
  "relations { nodes { id type relatedIssue { id } } } attachments { nodes { id url } }"
async function tagged(includeArchived) {
  const d = await api("query($p: ID, $a: Boolean) { issues(first: 100, includeArchived: $a, filter: { project: { id: { eq: $p } }, title: { startsWith: \"" + TAG + "\" } }) { nodes { " + ISSUE + " } } }",
    { p: PROJECT, a: !!includeArchived })
  return d.issues.nodes
}
async function byTitle(title, includeArchived) { return (await tagged(includeArchived)).filter(i => i.title === title) }
async function one(title) { const l = await byTitle(title); return l.length === 1 ? l[0] : null }

// ---- the proxy: the board's way to Linear ----

let faults = [], seen = []
function proxy() {
  return http.createServer((req, res) => {
    let body = ""
    req.on("data", c => body += c)
    req.on("end", () => {
      let op = ""
      try { op = JSON.parse(body).query.match(/^\s*(?:query|mutation)\s+(\w+)/)[1] } catch (e) {}
      const f = faults.find(x => new RegExp(x.match).test(op))
      if (f && f.times > 0 && --f.times === 0) faults = faults.filter(x => x !== f)
      const entry = { op, fault: f ? f.kind : "" }
      seen.push(entry)
      if (f && f.kind === "drop") return req.socket.destroy()
      if (f && f.kind === "ratelimit") {
        res.writeHead(400, { "Content-Type": "application/json", "X-RateLimit-Requests-Reset": String(Date.now() + (f.resetMs || 3000)) })
        return res.end(JSON.stringify({ errors: [{ message: "Rate limit exceeded", extensions: { code: "RATELIMITED" } }] }))
      }
      const up = https.request("https://api.linear.app/graphql", { method: "POST", headers: { "Content-Type": "application/json", Authorization: req.headers.authorization } }, r => {
        let d = ""
        r.on("data", c => d += c)
        r.on("end", () => {
          entry.status = r.statusCode
          if (f && f.kind === "delayAnswer") entry.answer = d.slice(0, 300)
          if (r.statusCode !== 200 || /"errors"/.test(d)) entry.error = d.slice(0, 300)
          const send = () => { try { res.writeHead(r.statusCode, { "Content-Type": "application/json" }); res.end(d) } catch (e) {} }
          if (f && f.kind === "delayAnswer") setTimeout(send, f.ms); else send()
        })
      })
      up.on("error", () => req.socket.destroy())
      up.end(body)
    })
  }).listen(PROXY, "127.0.0.1")
}

// ---- cleanup ----

async function cleanup() {
  const left = []
  for (const i of await tagged(true)) {
    try { await api("mutation($id: String!) { issueDelete(id: $id, permanentlyDelete: true) { success } }", { id: i.id }) }
    catch (e) { try { await api("mutation($id: String!) { issueDelete(id: $id) { success } }", { id: i.id }); left.push(i.identifier + " (in the trash)") } catch (x) { left.push(i.identifier) } }
  }
  const p = await api("query($id: String!) { project(id: $id) { projectMilestones { nodes { id name } } projectUpdates { nodes { id body } } teams { nodes { id } } } }", { id: PROJECT })
  for (const m of p.project.projectMilestones.nodes.filter(m => m.name.startsWith(TAG)))
    await api("mutation($id: String!) { projectMilestoneDelete(id: $id) { success } }", { id: m.id })
  for (const u of p.project.projectUpdates.nodes.filter(u => u.body.startsWith(TAG)))
    await api("mutation($id: String!) { projectUpdateArchive(id: $id) { success } }", { id: u.id })
  const labels = await api("query { issueLabels(first: 250, filter: { name: { startsWith: \"" + TAG + "\" } }) { nodes { id } } }")
  for (const l of labels.issueLabels.nodes) await api("mutation($id: String!) { issueLabelDelete(id: $id) { success } }", { id: l.id })
  return left
}

// ---- scenarios ----

const tests = []
const test = (name, fn) => tests.push({ name, fn })
let teamId, viewerId, columns

async function start() {
  await H.startBoard({
    config: JSON.stringify({ teamId, projectId: PROJECT, desktopNotify: false }),
    env: { LINEAR_API_KEY: KEY, LINEAR_BOARD_ENDPOINT: "http://127.0.0.1:" + PROXY + "/graphql" }
  })
  await waitFor(() => ev("board.team && board.team.id") === teamId && ev("board.pending") === 0 && !ev("board.loadingTeam"), 20000, "the team")
  ev("board.open('{}')")
  columns = ev("board.columns.map(function(c) { return c.id })")
}

// Opens the editor on a new issue in column `col`, sets the title (and more), saves.
async function createInEditor(title, col, more) {
  ev("m('newIssue').newIssue(" + col + ")")
  await waitFor(() => ev("board.dialog") === "issue", 3000, "the editor")
  await waitFor(() => !ev("p('milestoneValid').teamLoading"), 5000, "the editor's team")
  ev("find('titleField').titleField.text = " + JSON.stringify(title))
  if (more) ev(more)
  ok(ev("m('saveIssue').saveIssue()"), "saveIssue refused: " + H.toast())
  return waitFor(() => one(title), 10000, "“" + title + "” in Linear")
}

async function openEditor(id) {
  ev("m('editIssue').editIssue(" + JSON.stringify(id) + ")")
  await waitFor(() => ev("board.dialog") === "issue" && !ev("p('milestoneValid').detailLoading"), 8000, "the editor with its details")
}

test("loads the test project and the inbox", async () => {
  await start()
  eq(ev("board.config.projectId"), PROJECT, "project filter")
  await waitFor(() => { const s = H.inboxState(); return s && s.checkedAt }, 15000, "the inbox")
  const s = H.inboxState()
  eq(s.error, "", "inbox error")
  eq(ev("m('loadInbox').publicOnly"), false, "the internal inbox fields still answer")
  const d = await api("query { notificationsUnreadCount }")
  eq(s.unread, d.notificationsUnreadCount, "unread count matches Linear")
  ok(!/TypeError|ReferenceError|Cannot read/.test(H.shellLog()), "QML errors:\n" + H.shellLog())
})

test("a new issue with everything set", async () => {
  // A label of the test team, made through the board (deleted at the end).
  ev("m('addLabel').addLabel('" + TAG + " label', null)")
  await waitFor(() => ev("board.labels.some(function(l) { return l.name === '" + TAG + " label' })"), 8000, "the new label")
  const labelId = ev("board.labels.filter(function(l) { return l.name === '" + TAG + " label' })[0].id")
  const est = ev("board.team.issueEstimationType") !== "notUsed"
  const i = await createInEditor(TAG + " Everything", 1, [
    "find('descField').descField.text = 'Line one\\n\\n- [ ] a task'",
    "find('dueField').dueField.text = '2026-12-24'",
    "p('milestoneValid').priority = 2",
    "p('milestoneValid').assigneeId = board.viewer.id",
    "p('milestoneValid').labels = [" + JSON.stringify(labelId) + "]",
    est ? "p('milestoneValid').estimate = 2" : "0"
  ].join("; "))
  eq(i.priority, 2, "priority")
  eq(i.dueDate, "2026-12-24", "due date")
  eq(i.assignee && i.assignee.id, viewerId, "assignee")
  eq(i.project && i.project.id, PROJECT, "project")
  eq(i.state.id, columns[1], "state (the column it was made in)")
  eq(i.labels.nodes.map(l => l.id), [labelId], "labels")
  ok(/- \[ \] a task/.test(i.description), "description: " + i.description)
  if (est) eq(i.estimate, 2, "estimate")
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card on the board")
})

test("editing in the editor saves by itself", async () => {
  const i = await createInEditor(TAG + " To rename", 0)
  await openEditor(i.id)
  ev("find('titleField').titleField.text = '" + TAG + " Renamed'")
  ev("m('saveChanges').saveChanges('text')")
  ev("p('milestoneValid').priority = 1")
  ev("m('saveChanges').saveChanges('props')")
  await waitFor(async () => { const x = await one(TAG + " Renamed"); return x && x.priority === 1 }, 10000, "title and priority in Linear")
  ev("m('closeDialog').closeDialog()")
})

test("moving a card, and undo", async () => {
  const i = await createInEditor(TAG + " Mover", 0)
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card")
  ev("m('moveIssue').moveIssue('" + i.id + "', '" + columns[2] + "', 0)")
  await waitFor(async () => (await one(TAG + " Mover")).state.id === columns[2], 10000, "the move in Linear")
  await waitFor(() => ev("!!m('clickToast').toastAction"), 3000, "an undo toast")
  ev("m('clickToast').clickToast()")
  await waitFor(async () => (await one(TAG + " Mover")).state.id === columns[0], 10000, "the undo in Linear")
})

test("comments: post, edit, react, delete", async () => {
  const i = await createInEditor(TAG + " Comments", 0)
  await openEditor(i.id)
  ev("find('commentField').commentField.text = '" + TAG + " first'")
  ev("m('postComment').postComment()")
  await waitFor(async () => (await one(TAG + " Comments")).comments.nodes.some(c => c.body === TAG + " first"), 10000, "the comment in Linear")
  await waitFor(() => ev("p('milestoneValid').comments.length") === 1, 5000, "the comment in the editor")
  evs("var c = p('milestoneValid').comments[0]", "m('startEditComment').startEditComment(c)", "find('commentField').commentField.text = '" + TAG + " edited'", "m('postComment').postComment()", "1")
  await waitFor(async () => (await one(TAG + " Comments")).comments.nodes.some(c => c.body === TAG + " edited"), 10000, "the edit in Linear")
  await waitFor(() => !ev("p('milestoneValid').posting"), 5000, "posting to end")
  evs("m('toggleReaction').toggleReaction(p('milestoneValid').comments[0], '👍')", "1")
  await waitFor(async () => (await one(TAG + " Comments")).comments.nodes[0].reactions.length === 1, 10000, "the reaction in Linear")
  await waitFor(() => ev("p('milestoneValid').comments[0].reactions.length") === 1 && ev("p('milestoneValid').comments[0].reactions[0].id.length") > 0, 5000, "the reaction in the editor")
  evs("m('toggleReaction').toggleReaction(p('milestoneValid').comments[0], '👍')", "1")
  await waitFor(async () => (await one(TAG + " Comments")).comments.nodes[0].reactions.length === 0, 10000, "the reaction removed")
  evs("m('deleteComment').deleteComment(p('milestoneValid').comments[0])", "m('runConfirm').runConfirm()", "1")
  await waitFor(async () => (await one(TAG + " Comments")).comments.nodes.length === 0, 10000, "the comment deleted")
  ev("m('closeDialog').closeDialog()")
})

test("sub-issue, relation and link", async () => {
  const parent = await createInEditor(TAG + " Parent", 0)
  const child = await createInEditor(TAG + " Child", 0,
    "p('milestoneValid').parentIssue = { id: '" + parent.id + "', identifier: '" + parent.identifier + "', title: 'Parent' }")
  eq(child.parent && child.parent.id, parent.id, "parent")
  const other = await createInEditor(TAG + " Related", 0)
  await openEditor(parent.id)
  ev("m('addRelation').addRelation('" + other.identifier + "')")
  await waitFor(async () => (await one(TAG + " Parent")).relations.nodes.some(r => r.relatedIssue.id === other.id), 10000, "the relation in Linear")
  ev("m('addLink').addLink('example.com/bt')")
  await waitFor(async () => (await one(TAG + " Parent")).attachments.nodes.some(a => a.url === "https://example.com/bt"), 10000, "the link in Linear")
  await waitFor(() => ev("p('milestoneValid').relations.length") === 1 && ev("p('milestoneValid').attachments.length") >= 1, 5000, "both in the editor")
  ev("m('removeRelation').removeRelation(p('milestoneValid').relations[0])")
  evs("var a = p('milestoneValid').attachments.filter(function(x) { return x.url === 'https://example.com/bt' })[0]", "m('removeAttachment').removeAttachment(a)", "m('runConfirm').runConfirm()", "1")
  await waitFor(async () => { const x = await one(TAG + " Parent"); return x.relations.nodes.length === 0 && !x.attachments.nodes.some(a => a.url === "https://example.com/bt") }, 10000, "both removed in Linear")
  ev("m('closeDialog').closeDialog()")
})

test("bulk priority change", async () => {
  const a = await createInEditor(TAG + " Bulk A", 0), b = await createInEditor(TAG + " Bulk B", 0)
  await waitFor(() => ev("board.issues.filter(function(x) { return x.id === '" + a.id + "' || x.id === '" + b.id + "' }).length") === 2, 5000, "both cards")
  ev("board.multi = ['" + a.id + "', '" + b.id + "']")
  ev("m('applyBulk').applyBulk('bulkPriority', 4)")
  await waitFor(async () => (await one(TAG + " Bulk A")).priority === 4 && (await one(TAG + " Bulk B")).priority === 4, 10000, "both in Linear")
  ev("board.multi = []")
})

test("delete to the trash, undo, archive", async () => {
  const i = await createInEditor(TAG + " Trash", 0)
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card")
  ev("m('deleteIssue').deleteIssue('" + i.id + "')")
  ev("m('runConfirm').runConfirm()")
  await waitFor(async () => (await byTitle(TAG + " Trash", true))[0].trashed === true, 10000, "trashed in Linear")
  await waitFor(() => /Deleted/.test(H.toast()), 5000, "the undo toast")
  ev("m('clickToast').clickToast()")
  await waitFor(async () => { const x = (await byTitle(TAG + " Trash", true))[0]; return !x.trashed && !x.archivedAt }, 10000, "restored in Linear")
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 8000, "back on the board")
  ev("m('archiveIds').archiveIds(['" + i.id + "'], 'one')")
  await waitFor(async () => { const x = (await byTitle(TAG + " Trash", true))[0]; return x.archivedAt && !x.trashed }, 10000, "archived in Linear")
})

test("a create whose answer is lost is made once (real Linear)", async () => {
  faults.push({ match: "^IssueCreate$", kind: "delayAnswer", ms: 35000, times: 1 })
  const t = TAG + " Timeout"
  evs("m('flushOutbox').send('New issue', Linear.M_ISSUE_CREATE, { input: { teamId: '" + teamId + "', projectId: '" + PROJECT + "', title: '" + t + "' } }, null)", "1")
  await waitFor(() => H.outbox() === 1, 50000, "the timed-out create to wait in the outbox")
  await sleep(6000)
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(() => H.outbox() === 0, 15000, "the outbox to empty")
  eq((await byTitle(t)).length, 1, "issues made")
  const retry = seen.filter(e => e.op === "IssueCreate").slice(-1)[0]
  console.log("     Linear's answer to the second create: " + (retry.error || "(no error)"))
  ok(/Back online/.test(H.toast()), "counted as sent, toast: " + H.toast())
})

test("offline and back, through the outbox", async () => {
  const i = await createInEditor(TAG + " Offline", 0)
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card")
  faults.push({ match: ".", kind: "drop", times: 0 })
  ev("m('moveIssue').moveIssue('" + i.id + "', '" + columns[1] + "', 0)")
  await waitFor(() => H.outbox() === 1, 5000, "the outbox")
  ev("m('moveIssue').moveIssue('" + i.id + "', '" + columns[2] + "', 0)")
  await sleep(500)
  eq(H.outbox(), 1, "joined into one")
  faults = []
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(() => H.outbox() === 0, 10000, "the outbox to empty")
  eq((await one(TAG + " Offline")).state.id, columns[2], "the last move in Linear")
})

test("rate limit: changes wait, then go", async () => {
  const i = await createInEditor(TAG + " Limited", 0)
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card")
  faults.push({ match: "^Inbox$", kind: "ratelimit", resetMs: 4000, times: 1 })
  ev("m('loadInbox').loadInbox()")
  await waitFor(() => ev("board.rateLimitedUntil") > Date.now(), 5000, "the limit noted")
  ev("m('moveIssue').moveIssue('" + i.id + "', '" + columns[1] + "', 0)")
  await waitFor(() => H.outbox() === 1, 5000, "the change to wait")
  await sleep(4500)
  ev("m('flushOutbox').flushOutbox()")
  await waitFor(async () => (await one(TAG + " Limited")).state.id === columns[1], 10000, "the change in Linear")
})

test("logged time goes to the issue as a comment", async () => {
  const i = await createInEditor(TAG + " Time", 0)
  await waitFor(() => ev("board.issues.some(function(x) { return x.id === '" + i.id + "' })"), 5000, "the card")
  ok(ev("m('addManualTime').addManualTime(board.issues.filter(function(x) { return x.id === '" + i.id + "' })[0], '15m', '" + new Date().toISOString().slice(0, 10) + "', 'bt note')"), "addManualTime: " + H.toast())
  await waitFor(async () => (await one(TAG + " Time")).comments.nodes.length === 1, 10000, "the time comment")
  console.log("     time comment: " + JSON.stringify((await one(TAG + " Time")).comments.nodes[0].body))
})

test("project: milestones and updates", async () => {
  ev("m('openProject').openProject('" + PROJECT + "')")
  await waitFor(() => ev("m('openProject').projectViewId") === PROJECT && !ev("m('openProject').projectLoading"), 10000, "the project view")
  ev("m('addMilestone').addMilestone('" + TAG + " Milestone', '2026-12-31')")
  const ms = async () => (await api("query($id: String!) { project(id: $id) { projectMilestones { nodes { id name targetDate } } projectUpdates { nodes { id body health archivedAt } } } }", { id: PROJECT })).project
  await waitFor(async () => (await ms()).projectMilestones.nodes.some(m => m.name === TAG + " Milestone" && m.targetDate === "2026-12-31"), 10000, "the milestone")
  const mid = (await ms()).projectMilestones.nodes.find(m => m.name === TAG + " Milestone").id
  await waitFor(() => ev("board.milestoneById('" + mid + "') !== null"), 8000, "the milestone on the board")
  ev("m('updateMilestone').updateMilestone(board.milestoneById('" + mid + "'), '" + TAG + " Milestone 2', '2027-01-15')")
  await waitFor(async () => (await ms()).projectMilestones.nodes.some(m => m.id === mid && m.name === TAG + " Milestone 2" && m.targetDate === "2027-01-15"), 10000, "the renamed milestone")
  evs("m('deleteMilestone').deleteMilestone(board.milestoneById('" + mid + "'))", "m('runConfirm').runConfirm()", "1")
  await waitFor(async () => !(await ms()).projectMilestones.nodes.some(m => m.id === mid), 10000, "the milestone deleted")
  ev("m('postProjectUpdate').postProjectUpdate('" + TAG + " update')")
  await waitFor(async () => (await ms()).projectUpdates.nodes.some(u => u.body === TAG + " update"), 10000, "the update")
  await waitFor(() => ev("m('openProject').projectUpdates.some(function(u) { return u.body === '" + TAG + " update' })"), 8000, "the update in the view")
  evs("var u = m('openProject').projectUpdates.filter(function(u) { return u.body === '" + TAG + " update' })[0]", "m('deleteProjectUpdate').deleteProjectUpdate(u)", "m('runConfirm').runConfirm()", "1")
  await waitFor(async () => !(await ms()).projectUpdates.nodes.some(u => u.body === TAG + " update"), 10000, "the update deleted")
})

async function main() {
  H.setup()
  proxy()
  const me = await api("query($p: String!) { viewer { id } project(id: $p) { name teams { nodes { id key name } } } }", { p: PROJECT })
  viewerId = me.viewer.id
  teamId = me.project.teams.nodes[0].id
  console.log("project “" + me.project.name + "” in team " + me.project.teams.nodes[0].key)
  const before = await tagged(true)
  if (before.length) { console.log("left over from an earlier run, deleting: " + before.map(i => i.identifier).join(", ")); await cleanup() }
  let failed = 0, ran = 0
  try {
    for (const t of tests) {
      if (ONLY && !ONLY.test(t.name)) continue
      if (ran === 0 && !/loads/.test(t.name)) await start()
      ran++
      const t0 = Date.now()
      try {
        await t.fn()
        console.log("ok   " + t.name + "  (" + ((Date.now() - t0) / 1000).toFixed(1) + " s)")
      } catch (e) {
        failed++
        console.log("FAIL " + t.name + "\n     " + String(e.message || e).split("\n").join("\n     "))
        try { console.log("     screenshot: " + await H.shot("live-" + t.name.replace(/\W+/g, "-").slice(0, 40))) } catch (x) {}
        faults = []
        try { ev("m('closeDialog').closeDialog()") } catch (x) {}
      }
    }
  } finally {
    await H.stopBoard()
    const left = await cleanup()
    console.log("cleaned up" + (left.length ? "; could not delete for good: " + left.join(", ") : ""))
  }
  const errs = seen.filter(e => e.error && !e.fault).map(e => e.op + ": " + e.error)
  if (errs.length) console.log("Linear refused:\n  " + errs.join("\n  "))
  console.log((failed ? failed + " of " + ran + " failed" : "all " + ran + " passed") + "  (files in " + H.TMP + ")")
  process.exit(failed ? 1 : 0)
}

main().catch(async e => { console.error(e); try { await H.stopBoard(); await cleanup() } catch (x) {} process.exit(1) })
