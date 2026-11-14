.pragma library

// Everything the board says to Linear's API and how it reads the answers:
// the GraphQL queries and mutations, the filters and inputs they take,
// turning responses into plain objects, Linear's own fixed values
// (priorities, state types, estimate scales…) and its error messages.
// What the board does on top of Linear lives in the other files (Issues.js,
// Edit.js, Recur.js, Inbox.js, Markdown.js, Dates.js). No QML or network
// here; the overlay does the HTTP calls. tests/api.test.js checks every
// request against Linear's published schema.

var ENDPOINT = "https://api.linear.app/graphql"

// LINEAR_BOARD_ENDPOINT points the board at a stand-in for Linear's API
// (tests/fake-linear.js). Only a server on this machine is accepted, so the
// key is never sent anywhere else.
function endpointFor(override) {
  var o = String(override || "")
  return /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//.test(o) ? o : ENDPOINT
}
var KEY_URL = "https://linear.app/settings/account/security"

// ---- GraphQL ----------------------------------------------------------------

var PAGE_INFO = "pageInfo { hasNextPage endCursor }"

var ISSUE_FIELDS = "id identifier previousIdentifiers branchName title description priority sortOrder url createdAt updatedAt dueDate estimate team { id key name } " +
  "state { id name color type } labels { nodes { id } } assignee { id name displayName } project { id name color } cycle { id } " +
  "parent { id identifier title } projectMilestone { id name } completedAt canceledAt archivedAt"

var Q_BOOT = "query Boot { viewer { id name displayName } " +
  "teams(first: 100) { nodes { id name key } } }"

var Q_TEAM = "query Team($teamId: String!) { team(id: $teamId) { id name key " +
  "issueEstimationType issueEstimationAllowZero issueEstimationExtended autoArchivePeriod triageEnabled } }"

// Every list below is paged: the overlay keeps asking with `after` until
// hasNextPage is false, so big teams are not silently cut off.
var Q_STATES = "query States($teamId: String!, $after: String) { team(id: $teamId) { " +
  "states(first: 100, after: $after) { nodes { id name color type position } " + PAGE_INFO + " } } }"
var Q_LABELS = "query Labels($teamId: String!, $after: String) { team(id: $teamId) { " +
  "labels(first: 250, after: $after) { nodes { id name color isGroup } " + PAGE_INFO + " } } }"
var Q_WS_LABELS = "query WorkspaceLabels($after: String) { " +
  "issueLabels(first: 250, after: $after, filter: { team: { null: true } }) { nodes { id name color isGroup } " + PAGE_INFO + " } }"
// Linear limits a query's complexity (10 000; nested lists multiply), so
// projects come 25 per page with up to 25 milestones each.
// A project with what the project overview shows: status, health, target
// date, progress and milestones.
var PROJECT_FIELDS = "id name color url targetDate startDate progress health status { id name color type } " +
  "lead { id name displayName } projectMilestones(first: 25) { nodes { id name targetDate sortOrder } }"
var Q_PROJECTS = "query Projects($teamId: String!, $after: String) { team(id: $teamId) { " +
  "projects(first: 25, after: $after, filter: { status: { type: { nin: [\"completed\", \"canceled\"] } } }) { nodes { " + PROJECT_FIELDS + " } " + PAGE_INFO + " } } }"
var Q_MEMBERS = "query Members($teamId: String!, $after: String) { team(id: $teamId) { " +
  "members(first: 250, after: $after) { nodes { id name displayName active url } " + PAGE_INFO + " } } }"
var Q_CYCLES = "query Cycles($teamId: String!, $after: String) { team(id: $teamId) { " +
  "cycles(first: 50, after: $after, filter: { isPast: { eq: false } }) { nodes { id number name startsAt endsAt isActive } " + PAGE_INFO + " } } }"

var Q_ISSUES = "query Issues($filter: IssueFilter!, $after: String) { issues(first: 100, after: $after, filter: $filter) { nodes { " +
  ISSUE_FIELDS + " } " + PAGE_INFO + " } }"

var COMMENT_FIELDS = "id body createdAt editedAt user { id name displayName } parent { id } reactions { id emoji user { id name displayName } }"
var Q_COMMENTS = "query Comments($id: String!, $after: String) { issue(id: $id) { " +
  "comments(first: 100, after: $after) { nodes { " + COMMENT_FIELDS + " } " + PAGE_INFO + " } } }"
var Q_CHILDREN = "query Children($id: String!, $after: String) { issue(id: $id) { " +
  "children(first: 100, after: $after) { nodes { id identifier title url state { id name color type } } " + PAGE_INFO + " } } }"
// `id` may also be an identifier like ENG-12.
var Q_ISSUE_REF = "query IssueRef($id: String!) { issue(id: $id) { id identifier title team { id } } }"

var M_ISSUE_CREATE = "mutation IssueCreate($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { " + ISSUE_FIELDS + " } } }"
var M_ISSUE_UPDATE = "mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success issue { " + ISSUE_FIELDS + " } } }"
var M_ISSUE_DELETE = "mutation IssueDelete($id: String!) { issueDelete(id: $id) { success } }"
// One issue by id or identifier, for issues that are not on the board.
var Q_ISSUE = "query Issue($id: String!) { issue(id: $id) { " + ISSUE_FIELDS + " } }"

// Full-text search over the whole team, including old done issues.
var Q_SEARCH = "query Search($term: String!, $teamId: String) { searchIssues(term: $term, teamId: $teamId, first: 50) { nodes { " +
  ISSUE_FIELDS + " } } }"

var RELATED_FIELDS = "id identifier title url state { id name color type }"
var Q_RELATIONS = "query Relations($id: String!) { issue(id: $id) { " +
  "relations(first: 100) { nodes { id type relatedIssue { " + RELATED_FIELDS + " } } } " +
  "inverseRelations(first: 100) { nodes { id type issue { " + RELATED_FIELDS + " } } } } }"
var Q_ATTACHMENTS = "query Attachments($id: String!) { issue(id: $id) { " +
  "attachments(first: 100) { nodes { id title subtitle url sourceType } } } }"
var Q_HISTORY = "query History($id: String!, $after: String) { issue(id: $id) { history(first: 100, after: $after) { nodes { " +
  "id createdAt actor { name displayName } botActor { name } " +
  "fromState { name } toState { name } fromAssignee { name displayName } toAssignee { name displayName } " +
  "fromPriority toPriority fromTitle toTitle addedLabels { name } removedLabels { name } " +
  "fromDueDate toDueDate fromEstimate toEstimate fromProject { name } toProject { name } " +
  "fromCycle { number name } toCycle { number name } fromParent { identifier } toParent { identifier } " +
  "updatedDescription archived trashed autoClosed relationChanges { identifier type } } " + PAGE_INFO + " } } }"

var M_ISSUE_BATCH = "mutation IssueBatch($ids: [UUID!]!, $input: IssueUpdateInput!) { issueBatchUpdate(ids: $ids, input: $input) { success issues { " + ISSUE_FIELDS + " } } }"
var M_RELATION_CREATE = "mutation RelationCreate($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success issueRelation { id } } }"
var M_RELATION_DELETE = "mutation RelationDelete($id: String!) { issueRelationDelete(id: $id) { success } }"
var M_ATTACH_URL = "mutation AttachUrl($issueId: String!, $url: String!, $title: String) { attachmentLinkURL(issueId: $issueId, url: $url, title: $title) { success attachment { id title subtitle url sourceType } } }"
var M_ATTACHMENT_DELETE = "mutation AttachmentDelete($id: String!) { attachmentDelete(id: $id) { success } }"
var Q_COMMENT = "query Comment($id: String!) { comment(id: $id) { " + COMMENT_FIELDS + " } }"

// Creates that may wait in the offline outbox carry an id made on this
// machine (Linear takes one in the input). When an answer is lost (a
// timeout after Linear did create it) and the create is sent again, this
// finds what the first try made, so there is never a second issue or comment.
function createdLookup(query) {
  if (query === M_ISSUE_CREATE) return { query: Q_ISSUE, field: "issue", payload: "issueCreate" }
  if (query === M_COMMENT_CREATE) return { query: Q_COMMENT, field: "comment", payload: "commentCreate" }
  return null
}

var M_COMMENT_UPDATE = "mutation CommentUpdate($id: String!, $input: CommentUpdateInput!) { commentUpdate(id: $id, input: $input) { success comment { " + COMMENT_FIELDS + " } } }"
var M_COMMENT_DELETE = "mutation CommentDelete($id: String!) { commentDelete(id: $id) { success } }"
var M_UNSUBSCRIBE = "mutation Unsubscribe($id: String!) { issueUnsubscribe(id: $id) { success } }"
var M_SUBSCRIBE = "mutation Subscribe($id: String!) { issueSubscribe(id: $id) { success } }"

// Deletes several issues in one request.
function deleteDocument(count) {
  var vars = [], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": issueDelete(id: $id" + i + ") { success }")
  }
  return "mutation DeleteMany(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}

// Snoozes (or with until null, unsnoozes) several notifications.
function snoozeDocument(count) {
  var vars = ["$until: DateTime"], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": notificationUpdate(id: $id" + i + ", input: { snoozedUntilAt: $until }) { success }")
  }
  return "mutation Snooze(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}

// Archives several issues in one request (Linear's archive, not the trash).
function archiveIssuesDocument(count) {
  var vars = [], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": issueArchive(id: $id" + i + ") { success }")
  }
  return "mutation ArchiveMany(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}

// Done/canceled issues of a team that have been closed for at least `days`
// days and are not archived yet.
var Q_CLOSED_BEFORE = "query ClosedBefore($filter: IssueFilter!, $after: String) { issues(first: 100, after: $after, filter: $filter) { " +
  "nodes { id identifier title } " + PAGE_INFO + " } }"

function closedBeforeFilter(teamId, days) {
  var cut = "-P" + Math.max(0, Math.round(days)) + "D"
  return { team: { id: { eq: teamId } }, or: [{ completedAt: { lt: cut } }, { canceledAt: { lt: cut } }] }
}

var Q_TEMPLATES = "query Templates { templates { id name type team { id } templateData } }"
var M_TEMPLATE_CREATE = "mutation TemplateCreate($input: TemplateCreateInput!) { templateCreate(input: $input) { success template { id name type team { id } templateData } } }"
var M_TEMPLATE_DELETE = "mutation TemplateDelete($id: String!) { templateDelete(id: $id) { success } }"

// Linear accepts this many issues per batch update.
var BATCH_SIZE = 50

var M_COMMENT_CREATE = "mutation CommentCreate($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { " + COMMENT_FIELDS + " } } }"

var M_STATE_CREATE = "mutation StateCreate($input: WorkflowStateCreateInput!) { workflowStateCreate(input: $input) { success workflowState { id name color type position } } }"
var M_STATE_UPDATE = "mutation StateUpdate($id: String!, $input: WorkflowStateUpdateInput!) { workflowStateUpdate(id: $id, input: $input) { success workflowState { id name color type position } } }"
var M_STATE_ARCHIVE = "mutation StateArchive($id: String!) { workflowStateArchive(id: $id) { success } }"

var M_LABEL_CREATE = "mutation LabelCreate($input: IssueLabelCreateInput!) { issueLabelCreate(input: $input) { success issueLabel { id name color isGroup } } }"
var M_LABEL_UPDATE = "mutation LabelUpdate($id: String!, $input: IssueLabelUpdateInput!) { issueLabelUpdate(id: $id, input: $input) { success issueLabel { id name color isGroup } } }"
var M_LABEL_DELETE = "mutation LabelDelete($id: String!) { issueLabelDelete(id: $id) { success } }"

var M_PROJECT_CREATE = "mutation ProjectCreate($input: ProjectCreateInput!) { projectCreate(input: $input) { success project { id name color } } }"
var M_PROJECT_UPDATE = "mutation ProjectUpdate($id: String!, $input: ProjectUpdateInput!) { projectUpdate(id: $id, input: $input) { success project { id name color } } }"

var M_TEAM_UPDATE = "mutation TeamUpdate($id: String!, $input: TeamUpdateInput!) { teamUpdate(id: $id, input: $input) { success team { id name key } } }"

// ---- inbox (notifications) ----
// The latest notifications plus the exact unread count. Snoozed ones are
// filtered out on the client.
var INBOX_SIZE = 50
// Pages are read until every unread row Linear counts is found (unread ones
// can be old), but never more than this.
var INBOX_PAGES = 20
var INBOX_NODE = "id type category createdAt readAt snoozedUntilAt actor { id name displayName } botActor { name } " +
  "... on IssueNotification { issue { id identifier title url team { id name key } project { id name color } } comment { body } } " +
  "... on ProjectNotification { project { id name color url } }"
// notificationsUnreadCount, groupingKey, title, subtitle and inboxUrl are
// [Internal] in Linear's API: hidden from its schema since 2026-11-11, still
// answered. Should Linear turn them off, the inbox falls back to
// Q_INBOX_PUBLIC and toNotification makes them up from the rest.
var Q_INBOX = "query Inbox($after: String) { notificationsUnreadCount notifications(first: " + INBOX_SIZE + ", after: $after) { nodes { " +
  "groupingKey title subtitle inboxUrl " + INBOX_NODE + " } " + PAGE_INFO + " } }"
var Q_INBOX_PUBLIC = "query InboxPublic($after: String) { notifications(first: " + INBOX_SIZE + ", after: $after) { nodes { " +
  INBOX_NODE + " } " + PAGE_INFO + " } }"
// Without Linear's unread count there is no telling when every unread one
// is in, so the fallback reads only the newest pages.
var INBOX_PUBLIC_PAGES = 4
var INTERNAL_INBOX_FIELDS = ["notificationsUnreadCount", "groupingKey", "title", "subtitle", "inboxUrl"]

// Does this error say Linear no longer answers one of the internal inbox fields?
function internalFieldsGone(msg) {
  var m = /Cannot query field "(\w+)"/.exec(String(msg || ""))
  return !!m && INTERNAL_INBOX_FIELDS.indexOf(m[1]) >= 0
}
var M_NOTIFICATION_UPDATE = "mutation NotificationUpdate($id: String!, $input: NotificationUpdateInput!) { " +
  "notificationUpdate(id: $id, input: $input) { success } }"

// One mutation that marks many notifications read, or unread with readAt null
// (Linear has no "all" for the whole inbox, and an inbox row can hold several).
function markReadDocument(count) {
  var vars = ["$readAt: DateTime"], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": notificationUpdate(id: $id" + i + ", input: { readAt: $readAt }) { success }")
  }
  return "mutation MarkRead(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}

function markReadVariables(ids, readAt) {
  var v = { readAt: readAt }
  for (var i = 0; i < ids.length; i++) v["id" + i] = ids[i]
  return v
}

function archiveDocument(count) {
  var vars = [], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": notificationArchive(id: $id" + i + ") { success }")
  }
  return "mutation Archive(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}

function idVariables(ids) {
  var v = {}
  for (var i = 0; i < ids.length; i++) v["id" + i] = ids[i]
  return v
}

// ---- more requests: archive, uploads, reminders, reactions, milestones,
// project status and updates, cycles, trash, recurring issues ----
var M_ISSUE_UNARCHIVE = "mutation IssueUnarchive($id: String!) { issueUnarchive(id: $id) { success } }"
function unarchiveDocument(count) {
  var vars = [], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": issueUnarchive(id: $id" + i + ") { success }")
  }
  return "mutation UnarchiveMany(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}
// Deletes issues for good (no trash), in one request; workspace admins only.
function deleteForeverDocument(count) {
  var vars = [], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": issueDelete(id: $id" + i + ", permanentlyDelete: true) { success }")
  }
  return "mutation DeleteForeverMany(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}
function reminderDocument(count) {
  var vars = ["$at: DateTime!"], body = []
  for (var i = 0; i < count; i++) {
    vars.push("$id" + i + ": String!")
    body.push("n" + i + ": issueReminder(id: $id" + i + ", reminderAt: $at) { success }")
  }
  return "mutation Remind(" + vars.join(", ") + ") { " + body.join(" ") + " }"
}
var M_FILE_UPLOAD = "mutation FileUpload($contentType: String!, $filename: String!, $size: Int!) { " +
  "fileUpload(contentType: $contentType, filename: $filename, size: $size) { success uploadFile { uploadUrl assetUrl headers { key value } } } }"
// Deletes an uploaded file for good. Linear marks it internal and a last
// resort: anything still showing the file breaks, so the board takes it out
// of the text first.
var M_FILE_DELETE = "mutation FileDelete($assetUrl: String!) { fileUploadDangerouslyDelete(assetUrl: $assetUrl) { success } }"
// Linear may drop that internal mutation without notice, so the board asks
// once whether it still exists before it touches any text.
var FILE_DELETE_FIELD = "fileUploadDangerouslyDelete"
var Q_MUTATIONS = "query Mutations { __type(name: \"Mutation\") { fields { name } } }"
function hasMutation(data, name) {
  var t = data && data.__type
  return !!(t && Array.isArray(t.fields) && t.fields.some(function(f) { return f && f.name === name }))
}
// Linear's answer when a query names something its schema no longer has.
function isSchemaGone(msg) {
  return /Cannot query field|Unknown argument|Unknown type/i.test(String(msg || ""))
}
// The delete counts only when Linear says success.
function fileDeleted(data) {
  return !!(data && data.fileUploadDangerouslyDelete && data.fileUploadDangerouslyDelete.success)
}
var Q_ISSUE_REACTIONS = "query IssueReactions($id: String!) { issue(id: $id) { reactions { id emoji user { id name displayName } } } }"
var M_REACTION_CREATE = "mutation ReactionCreate($input: ReactionCreateInput!) { reactionCreate(input: $input) { success reaction { id emoji user { id name displayName } } } }"
var M_REACTION_DELETE = "mutation ReactionDelete($id: String!) { reactionDelete(id: $id) { success } }"
var M_MILESTONE_CREATE = "mutation MilestoneCreate($input: ProjectMilestoneCreateInput!) { projectMilestoneCreate(input: $input) { success projectMilestone { id name targetDate sortOrder } } }"
var M_MILESTONE_UPDATE = "mutation MilestoneUpdate($id: String!, $input: ProjectMilestoneUpdateInput!) { projectMilestoneUpdate(id: $id, input: $input) { success projectMilestone { id name targetDate sortOrder } } }"
var M_MILESTONE_DELETE = "mutation MilestoneDelete($id: String!) { projectMilestoneDelete(id: $id) { success } }"
var Q_PROJECT_STATUSES = "query ProjectStatuses { projectStatuses(first: 50) { nodes { id name color type position } } }"
var M_PROJECT_SAVE = "mutation ProjectSave($id: String!, $input: ProjectUpdateInput!) { projectUpdate(id: $id, input: $input) { success project { " + PROJECT_FIELDS + " } } }"
var UPDATE_FIELDS = "id body health createdAt url user { id name displayName }"
var Q_PROJECT_UPDATES = "query ProjectUpdates($id: String!) { project(id: $id) { " + PROJECT_FIELDS + " projectUpdates(first: 20) { nodes { " + UPDATE_FIELDS + " } } } }"
var M_PROJECT_UPDATE_EDIT = "mutation ProjectUpdateEdit($id: String!, $input: ProjectUpdateUpdateInput!) { projectUpdateUpdate(id: $id, input: $input) { success projectUpdate { " + UPDATE_FIELDS + " } } }"
// Linear's "Delete" on an update archives it (projectUpdateDelete is deprecated).
var M_PROJECT_UPDATE_ARCHIVE = "mutation ProjectUpdateArchive($id: String!) { projectUpdateArchive(id: $id) { success } }"
var M_PROJECT_UPDATE_CREATE = "mutation ProjectUpdateCreate($input: ProjectUpdateCreateInput!) { projectUpdateCreate(input: $input) { success projectUpdate { " + UPDATE_FIELDS + " } } }"
// Every cycle of a team (past ones too), for the cycle view.
var CYCLE_FIELDS = "id number name description startsAt endsAt isActive isNext isFuture isPast completedAt progress"
var Q_ALL_CYCLES = "query AllCycles($teamId: String!, $after: String) { team(id: $teamId) { " +
  "cycles(first: 100, after: $after) { nodes { " + CYCLE_FIELDS + " } " + PAGE_INFO + " } } }"
// Linear makes cycles itself from the team's settings (creating one through
// the API is not supported), so "new cycles" means these settings.
var TEAM_CYCLE_FIELDS = "id cyclesEnabled cycleDuration cycleStartDay cycleCooldownTime upcomingCycleCount"
var Q_TEAM_CYCLES = "query TeamCycles($teamId: String!) { team(id: $teamId) { " + TEAM_CYCLE_FIELDS + " } }"
var M_TEAM_CYCLES = "mutation TeamCycles($id: String!, $input: TeamUpdateInput!) { teamUpdate(id: $id, input: $input) { success team { " + TEAM_CYCLE_FIELDS + " } } }"
var M_CYCLE_UPDATE = "mutation CycleUpdate($id: String!, $input: CycleUpdateInput!) { cycleUpdate(id: $id, input: $input) { success cycle { " + CYCLE_FIELDS + " } } }"
var M_CYCLE_ARCHIVE = "mutation CycleArchive($id: String!) { cycleArchive(id: $id) { success } }"
var M_CYCLE_START_TODAY = "mutation CycleStartToday($id: String!) { cycleStartUpcomingCycleToday(id: $id) { success cycle { " + CYCLE_FIELDS + " } } }"

// ---- trash ----
// Linear keeps deleted issues 30 days. They are archived issues with
// trashed set; the filter has no "trashed", so archived ones of that time
// are fetched and the rest is dropped (toTrash).
var TRASH_DAYS = 30
var Q_TRASH = "query Trash($filter: IssueFilter!, $after: String) { issues(first: 100, after: $after, includeArchived: true, filter: $filter) { nodes { " +
  ISSUE_FIELDS + " trashed } " + PAGE_INFO + " } }"
var M_ISSUE_DELETE_FOREVER = "mutation IssueDeleteForever($id: String!) { issueDelete(id: $id, permanentlyDelete: true) { success } }"

// Archived issues (not deleted): Linear keeps them for good, out of
// boards and out of the Free plan's issue count.
var Q_ARCHIVED = "query Archived($filter: IssueFilter!, $after: String) { issues(first: 100, after: $after, includeArchived: true, filter: $filter) { nodes { " +
  ISSUE_FIELDS + " trashed } " + PAGE_INFO + " } }"
function archivedFilter(teamId) { return { team: { id: { eq: teamId } }, archivedAt: { null: false } } }
function toArchived(nodes) {
  return (nodes || []).filter(function(n) { return n && n.archivedAt && n.trashed !== true }).map(function(n) {
    var i = toIssue(n)
    i.archivedAt = n.archivedAt
    return i
  }).sort(function(a, b) { return a.archivedAt < b.archivedAt ? 1 : (a.archivedAt > b.archivedAt ? -1 : 0) })
}

// Issues that count toward the Free plan's limit: every one not archived
// (deleted ones are archived too), in all teams. Only ids, 250 a page.
var FREE_PLAN_ISSUES = 250
var Q_ACTIVE_IDS = "query ActiveIds($after: String) { issues(first: 250, after: $after) { nodes { id } " + PAGE_INFO + " } }"

function trashFilter(teamId, now) {
  var since = new Date((now || new Date()).getTime() - TRASH_DAYS * 86400000)
  return { team: { id: { eq: teamId } }, archivedAt: { gt: since.toISOString() } }
}

// Trashed issues, newest deletion first, with the day they leave the trash.
function toTrash(nodes) {
  return (nodes || []).filter(function(n) { return n && n.trashed === true }).map(function(n) {
    var i = toIssue(n)
    i.deletedAt = n.archivedAt || ""
    i.purgeAt = n.archivedAt ? new Date(new Date(n.archivedAt).getTime() + TRASH_DAYS * 86400000).toISOString() : ""
    return i
  }).sort(function(a, b) { return a.deletedAt < b.deletedAt ? 1 : (a.deletedAt > b.deletedAt ? -1 : 0) })
}

function toCycle(c) {
  return { id: c.id, number: c.number, name: c.name || "", description: c.description || "", startsAt: c.startsAt || "", endsAt: c.endsAt || "",
    isActive: !!c.isActive, isNext: !!c.isNext, isFuture: !!c.isFuture, isPast: !!c.isPast, completedAt: c.completedAt || "", progress: c.progress || 0 }
}

var Q_CYCLE_ISSUES = "query CycleIssues($id: String!, $after: String) { cycle(id: $id) { issues(first: 100, after: $after) { nodes { " +
  ISSUE_FIELDS + " } " + PAGE_INFO + " } } }"
// Open issues assigned to you in every team.
var Q_MY_ISSUES = "query MyIssues($after: String) { issues(first: 100, after: $after, filter: { assignee: { isMe: { eq: true } }, " +
  "state: { type: { nin: [\"completed\", \"canceled\", \"duplicate\"] } } }) { nodes { " + ISSUE_FIELDS + " } " + PAGE_INFO + " } }"
// Has a recurring issue for this date been created already (maybe on another computer)?
var Q_RECUR_SOURCES = "query RecurSources($ids: [ID!]) { issues(first: 100, filter: { id: { in: $ids } }) { nodes { id title project { id } projectMilestone { id } } } }"
var Q_RECUR_LATEST = "query RecurLatest($filter: IssueFilter!) { issues(first: 1, filter: $filter, orderBy: createdAt) { nodes { id url } } }"
var Q_RECUR_EXISTS = "query RecurExists($filter: IssueFilter!) { issues(first: 1, filter: $filter) { nodes { id identifier } } }"

// Stops a runaway pager (Linear bug, cursor loop) after this many pages.
var MAX_PAGES = 100

// How long done and canceled issues stay on the board (V → Completed),
// like "Completed issues" in Linear's display options. days: null = all.
var DONE_WINDOWS = [
  { id: "none", label: "None", days: 0, duration: "" },
  { id: "week", label: "Past week", days: 7, duration: "-P1W" },
  { id: "2weeks", label: "Past 2 weeks", days: 14, duration: "-P2W" },
  { id: "month", label: "Past month", days: 31, duration: "-P1M" },
  { id: "quarter", label: "Past 3 months", days: 92, duration: "-P3M" },
  { id: "all", label: "All", days: null, duration: "" }
]
var DEFAULT_DONE_WINDOW = "2weeks"
function doneWindow(id) {
  for (var i = 0; i < DONE_WINDOWS.length; i++) if (DONE_WINDOWS[i].id === id) return DONE_WINDOWS[i]
  return doneWindow(DEFAULT_DONE_WINDOW)
}

function issueFilter(teamId, projectId, windowId) {
  var w = doneWindow(windowId)
  var f = { team: { id: { eq: teamId } } }
  var open = { state: { type: { nin: ["completed", "canceled", "duplicate"] } } }
  if (w.id === "none") f.state = open.state
  else if (w.duration) f.or = [open, { completedAt: { gt: w.duration } }, { canceledAt: { gt: w.duration } }]
  if (projectId) f.project = { id: { eq: projectId } }
  return f
}

// ---- workflow states ------------------------------------------------

// Linear's fixed state categories, in board order. `label` is what the UI
// shows when adding a column, so nobody has to know Linear's internal names.
var STATE_TYPES = [
  { type: "triage", label: "Triage" },
  { type: "backlog", label: "Backlog" },
  { type: "unstarted", label: "To do" },
  { type: "started", label: "In progress" },
  { type: "completed", label: "Done" },
  { type: "canceled", label: "Canceled" }
]

function typeRank(type) {
  for (var i = 0; i < STATE_TYPES.length; i++) if (STATE_TYPES[i].type === type) return i
  return STATE_TYPES.length
}

function typeLabel(type) {
  for (var i = 0; i < STATE_TYPES.length; i++) if (STATE_TYPES[i].type === type) return STATE_TYPES[i].label
  return type
}

function sortStates(states) {
  return (states || []).slice().sort(function(a, b) {
    var t = typeRank(a.type) - typeRank(b.type)
    return t !== 0 ? t : (a.position || 0) - (b.position || 0)
  })
}

// Position for a new state at the end of its category.
function positionForNewState(states, type) {
  var same = (states || []).filter(function(s) { return s.type === type })
  if (same.length === 0) {
    var all = (states || []).map(function(s) { return s.position || 0 })
    return all.length ? Math.max.apply(null, all) + 1 : 0
  }
  return Math.max.apply(null, same.map(function(s) { return s.position || 0 })) + 1
}

// Swap position with the neighbour of the same category (Linear keeps
// categories in fixed order, so a state can only move inside its own).
function positionSwap(states, stateId, delta) {
  var sorted = sortStates(states)
  var i = -1
  for (var k = 0; k < sorted.length; k++) if (sorted[k].id === stateId) i = k
  var j = i + delta
  if (i < 0 || j < 0 || j >= sorted.length || sorted[j].type !== sorted[i].type) return null
  var a = sorted[i], b = sorted[j]
  var pa = a.position || 0, pb = b.position || 0
  if (pa === pb) pb = pa + delta
  return [{ id: a.id, position: pb }, { id: b.id, position: pa }]
}

// ---- issues ---------------------------------------------------------------------

// Linear priority numbers: 0 none, 1 urgent, 2 high, 3 medium, 4 low.
var PRIORITIES = [
  { value: 0, label: "No priority", short: "", color: "muted" },
  { value: 1, label: "Urgent", short: "!!!", color: "red" },
  { value: 2, label: "High", short: "↑↑", color: "orange" },
  { value: 3, label: "Medium", short: "↑", color: "yellow" },
  { value: 4, label: "Low", short: "↓", color: "blue" }
]

function priority(value) {
  for (var i = 0; i < PRIORITIES.length; i++) if (PRIORITIES[i].value === value) return PRIORITIES[i]
  return PRIORITIES[0]
}

// Flatten an issue from the API into what the board uses.
function toIssue(raw) {
  if (!raw) return null
  var a = raw.assignee
  return {
    id: raw.id,
    identifier: raw.identifier || "",
    // Old ids (team prefix changed, issue moved between teams) still find it.
    previousIdentifiers: Array.isArray(raw.previousIdentifiers) ? raw.previousIdentifiers : [],
    branchName: raw.branchName || "",
    title: raw.title || "",
    description: raw.description || "",
    priority: typeof raw.priority === "number" ? raw.priority : 0,
    sortOrder: typeof raw.sortOrder === "number" ? raw.sortOrder : 0,
    url: raw.url || "",
    updatedAt: raw.updatedAt || "",
    completedAt: raw.completedAt || "",
    canceledAt: raw.canceledAt || "",
    archivedAt: raw.archivedAt || "",
    trashed: raw.trashed === true,
    createdAt: raw.createdAt || "",
    teamId: raw.team ? raw.team.id : "",
    teamKey: raw.team ? raw.team.key || "" : "",
    teamName: raw.team ? raw.team.name || "" : "",
    stateName: raw.state ? raw.state.name || "" : "",
    stateColor: raw.state ? raw.state.color || "" : "",
    stateId: raw.state ? raw.state.id : "",
    stateType: raw.state ? raw.state.type || "" : "",
    labelIds: raw.labels && raw.labels.nodes ? raw.labels.nodes.map(function(l) { return l.id }) : [],
    assignee: toAssignee(a),
    projectId: raw.project ? raw.project.id : "",
    projectName: raw.project ? raw.project.name || "" : "",
    projectColor: raw.project ? raw.project.color || "" : "",
    dueDate: raw.dueDate || "",
    estimate: typeof raw.estimate === "number" ? raw.estimate : null,
    cycleId: raw.cycle ? raw.cycle.id : "",
    parent: raw.parent ? { id: raw.parent.id, identifier: raw.parent.identifier || "", title: raw.parent.title || "" } : null,
    milestoneId: raw.projectMilestone ? raw.projectMilestone.id : "",
    milestoneName: raw.projectMilestone ? raw.projectMilestone.name || "" : ""
  }
}

// A user (issue assignee or team member) as the board shows it.
function toAssignee(u) {
  if (!u) return null
  return { id: u.id, name: u.displayName || u.name || "", fullName: u.name || u.displayName || "",
    initials: initials(u.name || u.displayName), url: u.url || "" }
}

// Active team members, viewer first, then by name.
function toMembers(nodes, viewerId) {
  return (nodes || []).filter(function(u) { return u && u.active !== false }).map(toAssignee).sort(function(a, b) {
    if (a.id === viewerId) return -1
    if (b.id === viewerId) return 1
    return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1
  })
}

function toComment(raw) {
  return { id: raw.id, body: raw.body || "", createdAt: raw.createdAt || "", edited: !!raw.editedAt,
    authorId: raw.user ? raw.user.id : "",
    author: raw.user ? (raw.user.displayName || raw.user.name || "") : "Linear",
    parentId: raw.parent ? raw.parent.id : "",
    reactions: toReactions(raw.reactions) }
}

function toReactions(list) {
  return (list || []).map(function(r) {
    return { id: r.id, emoji: emojiName(r.emoji), userId: r.user ? r.user.id : "", user: r.user ? (r.user.displayName || r.user.name || "") : "" }
  })
}

// Quick reactions offered under a comment (Linear's defaults).
var REACTION_EMOJIS = ["👍", "❤️", "🎉", "😄", "👀", "🚀", "👎"]

// Linear stores reactions by name ("+1"), but accepts the emoji itself.
var EMOJI_NAMES = { "+1": "👍", "-1": "👎", heart: "❤️", tada: "🎉", smile: "😄", eyes: "👀", rocket: "🚀",
  joy: "😂", fire: "🔥", white_check_mark: "✅", pray: "🙏", laughing: "😆", thinking_face: "🤔", raised_hands: "🙌",
  "100": "💯", clap: "👏", heart_eyes: "😍", muscle: "💪", ok_hand: "👌", wave: "👋", sob: "😭", slightly_smiling_face: "🙂" }
function emojiName(e) {
  for (var k in EMOJI_NAMES) if (EMOJI_NAMES[k] === e) return k
  return e
}
function emojiChar(e) {
  if (EMOJI_NAMES[e]) return EMOJI_NAMES[e]
  return /^[a-z0-9_+-]+$/.test(e) ? ":" + e + ":" : e
}

function initials(name) {
  var parts = String(name || "").trim().split(/\s+/).filter(function(p) { return p.length })
  if (parts.length === 0) return "?"
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

// Labels of the team plus workspace labels, groups left out (they cannot be
// put on an issue).
function mergeLabels(teamLabels, workspaceLabels) {
  var seen = {}
  var out = []
  ;(teamLabels || []).concat(workspaceLabels || []).forEach(function(l) {
    if (!l || l.isGroup || seen[l.id]) return
    seen[l.id] = true
    out.push({ id: l.id, name: l.name, color: l.color || "#bec2c8" })
  })
  return out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
}

// ---- estimates ----------------------------------------------------------------------

// Linear's estimate scales. tShirt sizes are stored as the fibonacci numbers.
var ESTIMATE_SCALES = {
  exponential: { base: [1, 2, 4, 8, 16], extended: [32, 64] },
  fibonacci: { base: [1, 2, 3, 5, 8], extended: [13, 21] },
  linear: { base: [1, 2, 3, 4, 5], extended: [6, 7] },
  tShirt: { base: [1, 2, 3, 5, 8], extended: [13, 21], names: { 0: "–", 1: "XS", 2: "S", 3: "M", 5: "L", 8: "XL", 13: "XXL", 21: "XXXL" } }
}

// team: { estimationType, estimationAllowZero, estimationExtended }. Empty when estimates are off.
function estimateOptions(team) {
  var scale = team && ESTIMATE_SCALES[team.estimationType]
  if (!scale) return []
  var values = (team.estimationAllowZero ? [0] : []).concat(scale.base, team.estimationExtended ? scale.extended : [])
  return values.map(function(v) { return { value: v, label: estimateLabel(team, v) } })
}

function estimateLabel(team, value) {
  if (typeof value !== "number") return ""
  var scale = team && ESTIMATE_SCALES[team.estimationType]
  if (scale && scale.names && scale.names[value] !== undefined) return scale.names[value]
  return String(value) + (value === 1 ? " pt" : " pts")
}

// ---- inbox ---------------------------------------------------------------------------

// Flatten a notification. Snoozed ones (until a future time) are dropped by `toInbox`.
// What happened, for notifications that come without Linear's subtitle
// (Q_INBOX_PUBLIC): from the type, "issueStatusChanged" -> "Status changed".
var NOTIFICATION_TEXTS = {
  issueAssignedToYou: "Assigned to you", issueUnassignedFromYou: "Unassigned from you", issueMention: "Mentioned you",
  issueCommentMention: "Mentioned you in a comment", issueNewComment: "New comment", issueCommentReaction: "Reacted to a comment",
  issueEmojiReaction: "Reacted", issueStatusChanged: "Status changed", issuePriorityUrgent: "Marked urgent",
  issueDue: "Due soon", issueBlocking: "Blocking changed", issueCreated: "Created", issueSubscribed: "Subscribed you",
  issueReminder: "Reminder", projectUpdateCreated: "New project update", projectUpdateMentionPrompt: "Mentioned you in an update"
}

function notificationText(type) {
  if (NOTIFICATION_TEXTS[type]) return NOTIFICATION_TEXTS[type]
  var words = String(type || "").replace(/^(issue|project|document|initiative|post)(?=[A-Z])/, "").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : "Notification"
}

function toNotification(raw) {
  raw = raw || {}
  var issue = raw.issue || null
  var project = (issue && issue.project) || raw.project || null
  var actor = raw.actor ? (raw.actor.displayName || raw.actor.name || "") : (raw.botActor && raw.botActor.name ? String(raw.botActor.name) : "")
  var body = raw.comment && raw.comment.body ? String(raw.comment.body).replace(/\s+/g, " ").trim() : ""
  // Linear's own grouping key is "issue#<id>"; the same is made up without it.
  var groupingKey = raw.groupingKey || (issue && issue.id ? "issue#" + issue.id : (raw.project && raw.project.id ? "project#" + raw.project.id : raw.id))
  var title = raw.title || (issue && issue.title) || (raw.project && raw.project.name) || "Linear"
  var subtitle = raw.subtitle !== undefined && raw.subtitle !== null ? String(raw.subtitle)
    : notificationText(raw.type) + (actor ? " by " + actor : "")
  return {
    id: raw.id, ids: [raw.id], count: 1, events: [{ subtitle: subtitle, createdAt: raw.createdAt || "" }], groupingKey: groupingKey, type: raw.type || "", title: title, subtitle: subtitle,
    createdAt: raw.createdAt || "", read: !!raw.readAt, snoozedUntil: raw.snoozedUntilAt || "",
    url: issue && issue.url ? issue.url : (raw.project && raw.project.url ? raw.project.url : (raw.inboxUrl || "")), actor: actor,
    issueId: issue ? issue.id : "", identifier: issue ? issue.identifier || "" : "",
    teamId: issue && issue.team ? issue.team.id : "", teamName: issue && issue.team ? issue.team.name || "" : "",
    projectId: project ? project.id : "", projectName: project ? project.name || "" : "",
    projectColor: project ? project.color || "" : "", category: raw.category || "",
    snippet: body.length > 160 ? body.slice(0, 159) + "…" : body
  }
}

// Notifications grouped like Linear's inbox: one row per groupingKey (an
// issue's assignment and priority change are one row), newest first. A row is
// unread while any of its notifications is, and carries all their ids.
function toInbox(nodes, nowIso) {
  var newestFirst = function(a, b) { return a.createdAt < b.createdAt ? 1 : (a.createdAt > b.createdAt ? -1 : 0) }
  var list = (nodes || []).map(toNotification).filter(function(n) {
    return !n.snoozedUntil || n.snoozedUntil <= nowIso
  }).sort(newestFirst)
  var groups = {}, rows = []
  list.forEach(function(n) {
    var g = groups[n.groupingKey]
    if (!g) { groups[n.groupingKey] = n; rows.push(n); return }
    g.ids.push(n.id)
    g.count++
    g.events.push({ subtitle: n.subtitle, createdAt: n.createdAt })
    if (!n.read) g.read = false
    if (!g.snippet && n.snippet) g.snippet = n.snippet
  })
  return rows
}

// Linear's notification categories, as the inbox filter names them.
var CATEGORY_LABELS = {
  assignments: "Assigned", mentions: "Mentions", commentsAndReplies: "Comments", statusChanges: "Status",
  reactions: "Reactions", subscriptions: "Subscribed", triage: "Triage", reminders: "Reminders", reviews: "Reviews",
  postsAndUpdates: "Updates", documentChanges: "Documents", appsAndIntegrations: "Integrations",
  customers: "Customers", feed: "Feed", loops: "Loops", billing: "Billing", system: "System"
}

function categoryLabel(c) { return CATEGORY_LABELS[c] || c || "Other" }

// ---- relations, attachments, history ---------------------------------------------------

// One list from an issue's relations (it -> other) and inverse relations (other -> it).
function toRelations(issueData) {
  var out = []
  var other = function(i) {
    return { id: i.id, identifier: i.identifier, title: i.title, url: i.url || "",
      stateName: i.state ? i.state.name : "", stateColor: i.state ? i.state.color : "#888888",
      done: !!(i.state && (i.state.type === "completed" || i.state.type === "canceled")) }
  }
  var rel = issueData && issueData.relations ? issueData.relations.nodes : []
  var inv = issueData && issueData.inverseRelations ? issueData.inverseRelations.nodes : []
  rel.forEach(function(r) { if (r.relatedIssue) out.push({ id: r.id, type: r.type, inverse: false, issue: other(r.relatedIssue) }) })
  inv.forEach(function(r) {
    // related/similar are symmetric; showing both directions would list them twice
    if (!r.issue || ((r.type === "related" || r.type === "similar") && out.some(function(o) { return o.issue.id === r.issue.id && o.type === r.type }))) return
    out.push({ id: r.id, type: r.type, inverse: true, issue: other(r.issue) })
  })
  var order = { blocks: 0, duplicate: 1, related: 2, similar: 3 }
  var rank = function(t) { return order.hasOwnProperty(t) ? order[t] : 9 }
  return out.sort(function(a, b) { return rank(a.type) - rank(b.type) || (a.inverse ? 1 : 0) - (b.inverse ? 1 : 0) })
}

function relationLabel(type, inverse) {
  if (type === "blocks") return inverse ? "Blocked by" : "Blocks"
  if (type === "duplicate") return inverse ? "Duplicated by" : "Duplicate of"
  if (type === "similar") return "Similar to"
  return "Related to"
}

// What the editor offers when adding a relation, and how it maps to Linear's
// (issueId, relatedIssueId, type): "Blocked by X" is X blocks this.
var RELATION_KINDS = [
  { id: "blocks", label: "Blocks", type: "blocks", inverse: false },
  { id: "blockedBy", label: "Blocked by", type: "blocks", inverse: true },
  { id: "duplicate", label: "Duplicate of", type: "duplicate", inverse: false },
  { id: "related", label: "Related to", type: "related", inverse: false }
]

function relationInput(kindId, thisId, otherId) {
  for (var i = 0; i < RELATION_KINDS.length; i++) {
    var k = RELATION_KINDS[i]
    if (k.id === kindId) return k.inverse
      ? { issueId: otherId, relatedIssueId: thisId, type: k.type }
      : { issueId: thisId, relatedIssueId: otherId, type: k.type }
  }
  return null
}

// The input that creates a removed relation again (for undo).
function relationRestoreInput(rel, thisId) {
  return rel.inverse ? { issueId: rel.issue.id, relatedIssueId: thisId, type: rel.type }
    : { issueId: thisId, relatedIssueId: rel.issue.id, type: rel.type }
}

function toAttachment(a) {
  return { id: a.id, title: a.title || a.url || "", subtitle: a.subtitle || "", url: a.url || "", source: a.sourceType || "" }
}

// ---- templates ------------------------------------------------------------------------------

// Linear issue templates of a team (or of the whole workspace).
function issueTemplates(templates, teamId) {
  return (templates || []).filter(function(t) {
    return t && t.type === "issue" && (!t.team || t.team.id === teamId)
  }).map(function(t) {
    var d = t.templateData
    if (typeof d === "string") { try { d = JSON.parse(d) } catch (e) { d = {} } }
    return { id: t.id, name: t.name, teamId: t.team ? t.team.id : "", data: d || {} }
  }).sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
}

// templateData for the editor's current values (fields Linear's issue templates use).
function templateDataFrom(v) {
  var d = { title: v.title || "", description: v.description || "", priority: v.priority || 0, labelIds: v.labelIds || [] }
  if (v.stateId) d.stateId = v.stateId
  if (v.projectId) d.projectId = v.projectId
  if (v.assigneeId) d.assigneeId = v.assigneeId
  if (typeof v.estimate === "number") d.estimate = v.estimate
  return d
}

// ---- cycles --------------------------------------------------------------------------

function toCycles(nodes) {
  return (nodes || []).map(function(c) {
    return { id: c.id, number: c.number, name: c.name || "", startsAt: c.startsAt || "", endsAt: c.endsAt || "", isActive: !!c.isActive }
  }).sort(function(a, b) { return a.startsAt < b.startsAt ? -1 : 1 })
}

// Preset colors offered for labels and columns: Linear's own label palette.
var COLORS = ["#95a2b3", "#5e6ad2", "#26b5ce", "#0f783c", "#4cb782", "#f2c94c", "#f2994a", "#eb5757", "#f7c8c1", "#bb87fc", "#a2845e"]

// ---- projects -------------------------------------------------------------------------

var HEALTH = [
  { id: "onTrack", label: "On track", color: "#4cb782" },
  { id: "atRisk", label: "At risk", color: "#f2c94c" },
  { id: "offTrack", label: "Off track", color: "#eb5757" }
]
function healthInfo(id) {
  for (var i = 0; i < HEALTH.length; i++) if (HEALTH[i].id === id) return HEALTH[i]
  return null
}

function toMilestones(raw) {
  var nodes = raw && raw.nodes ? raw.nodes : (Array.isArray(raw) ? raw : [])
  return nodes.map(function(m) { return { id: m.id, name: m.name || "", targetDate: m.targetDate || "", sortOrder: m.sortOrder || 0 } })
    .sort(function(a, b) { return a.sortOrder - b.sortOrder || (a.name < b.name ? -1 : 1) })
}

function toProject(raw) {
  if (!raw) return null
  return { id: raw.id, name: raw.name || "", color: raw.color || "", url: raw.url || "",
    targetDate: raw.targetDate || "", startDate: raw.startDate || "",
    progress: typeof raw.progress === "number" ? raw.progress : 0, health: raw.health || "",
    status: raw.status ? { id: raw.status.id, name: raw.status.name || "", color: raw.status.color || "", type: raw.status.type || "" } : null,
    lead: raw.lead ? (raw.lead.displayName || raw.lead.name || "") : "",
    milestones: toMilestones(raw.projectMilestones) }
}

function toProjectUpdate(raw) {
  return { id: raw.id, body: raw.body || "", health: raw.health || "", createdAt: raw.createdAt || "", url: raw.url || "",
    author: raw.user ? (raw.user.displayName || raw.user.name || "") : "", authorId: raw.user ? raw.user.id : "" }
}

// ---- recurring issues (Recur.js; Linear's API for them is internal) ----

// Has the copy for this day been made already (maybe on another computer)?
function recurExistsFilter(rule, iso) {
  return { team: { id: { eq: rule.teamId } }, title: { eq: rule.title }, createdAt: { gte: iso + "T00:00:00" },
    project: rule.projectId ? { id: { eq: rule.projectId } } : { null: true } }
}

// ---- errors ----

// What to tell the user when a request fails.
function errorMessage(response, status) {
  if (status === 401 || status === 400 && /authentication/i.test(JSON.stringify(response || {})))
    return "Linear rejected the API key. Paste a new one."
  if (response && response.errors && response.errors.length) {
    var e = response.errors[0]
    var user = e.extensions && (e.extensions.userPresentableMessage || e.extensions.userError && e.message)
    return String(user || e.message || "Linear returned an error")
  }
  if (status === 0) return "Cannot reach Linear. Check your connection."
  if (status === 429) return "Linear's rate limit was reached. Trying again in a while."
  return "Linear request failed (HTTP " + status + ")"
}

// Linear answers too many requests with HTTP 429, or 400 and the error code
// RATELIMITED (it did both over time).
function isRateLimited(response, status) {
  if (status === 429) return true
  var errors = response && response.errors
  return !!(errors && errors.some(function(e) { return e && e.extensions && e.extensions.code === "RATELIMITED" }))
}

// When to try again, in ms since epoch: Linear's X-RateLimit-Requests-Reset
// header (ms since epoch), or Retry-After (seconds), else a minute. Never
// longer than an hour, whatever the header says.
function rateLimitUntil(resetHeader, retryAfterHeader, nowMs) {
  var reset = Number(resetHeader)
  var retry = Number(retryAfterHeader)
  var until = reset > nowMs ? reset : (retry > 0 ? nowMs + retry * 1000 : nowMs + 60000)
  return Math.min(until, nowMs + 3600000)
}
