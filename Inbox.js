.pragma library
.import "Linear.js" as Linear

// The inbox filter (team, project, kind) and what is new since the last check.
// Linear's notifications themselves are read in Linear.js.
// Pure helpers, no QML or network, so tests run them with node.

// filter: { teamId, projectId, category }; "" means any. "none" for project
// means notifications without a project.
function inboxMatches(n, filter) {
  if (!filter) return true
  if (filter.teamId && n.teamId !== filter.teamId) return false
  if (filter.projectId === "none") { if (n.projectId) return false }
  else if (filter.projectId && n.projectId !== filter.projectId) return false
  if (filter.category && n.category !== filter.category) return false
  return true
}

// Choices for the inbox filter rows, with unread counts. Each row counts
// what the other active filters leave (kinds within the chosen project, and
// so on), so the numbers add up to what the inbox shows.
function inboxFacets(inbox, filter) {
  var f = filter || {}
  var without = function(key) {
    var g = { teamId: f.teamId || "", projectId: f.projectId || "", category: f.category || "" }
    g[key] = ""
    return g
  }
  var forTeams = without("teamId"), forProjects = without("projectId"), forCats = without("category")
  var teams = {}, projects = {}, cats = {}
  var add = function(map, id, make, unread) {
    var e = map[id] || (map[id] = make())
    e.total++
    if (unread) e.unread++
  }
  inbox.forEach(function(n) {
    if (n.teamId && inboxMatches(n, forTeams)) add(teams, n.teamId, function() { return { id: n.teamId, label: n.teamName, total: 0, unread: 0 } }, !n.read)
    if (inboxMatches(n, forProjects)) add(projects, n.projectId || "none", function() {
      return { id: n.projectId || "none", label: n.projectId ? n.projectName : "No project", color: n.projectColor, total: 0, unread: 0 }
    }, !n.read)
    if (n.category && inboxMatches(n, forCats)) add(cats, n.category, function() { return { id: n.category, label: Linear.categoryLabel(n.category), total: 0, unread: 0 } }, !n.read)
  })
  var list = function(map) {
    return Object.keys(map).map(function(k) { return map[k] }).sort(function(a, b) {
      if (a.id === "none") return 1
      if (b.id === "none") return -1
      return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1
    })
  }
  return { teams: list(teams), projects: list(projects), categories: list(cats) }
}

// Unread notifications created after `since` (ISO time), oldest first: what
// to announce on the desktop. Nothing on the first check (since empty).
function newUnread(inbox, since) {
  if (!since) return []
  return inbox.filter(function(n) { return !n.read && n.createdAt > since }).reverse()
}

// Paging the inbox can stop once every unread row Linear counts is in.
// Without Linear's count (count < 0, the fallback query) it never stops early.
function enoughUnread(rows, count) {
  if (count < 0) return false
  return rows.filter(function(n) { return !n.read }).length >= count
}

// A check of the inbox that has not come back for this long is given up, so
// one lost answer cannot stop all the later checks (the request watchdog
// gives up after 30 s per page; this covers everything else).
var LOAD_GIVE_UP_MS = 5 * 60000

function loadStuck(loadingSinceMs, nowMs) {
  return loadingSinceMs > 0 && nowMs - loadingSinceMs > LOAD_GIVE_UP_MS
}

// The inbox is checked every minute; after this long without a good check
// the bar says so instead of showing an old count as current.
var STALE_MS = 5 * 60000

// What the bar widget shows for the state the board wrote (inbox.json):
// { stale, note }. note is "" when all is well.
function barHealth(state, nowMs) {
  if (!state || state.connected !== true) return { stale: false, note: "" }
  var checked = state.checkedAt ? Date.parse(state.checkedAt) : NaN
  var error = String(state.error || "")
  if (isNaN(checked)) {
    // Just started: the first check is on its way.
    var started = state.startedAt ? Date.parse(state.startedAt) : NaN
    var fresh = !isNaN(started) && nowMs - started <= STALE_MS
    return { stale: !fresh, note: (fresh ? "Loading the inbox…" : "Inbox not loaded") + (error ? ": " + error : "") }
  }
  if (nowMs - checked <= STALE_MS) return { stale: false, note: error ? "Last check failed: " + error : "" }
  var mins = Math.round((nowMs - checked) / 60000)
  return { stale: true, note: "Not updated for " + (mins < 60 ? mins + " min" : Math.round(mins / 60) + " h") + (error ? ": " + error : "") }
}

// Of two boards writing inbox.json (an old one left over after the plugin
// was reloaded), the bar follows the one that started last.
function newerWriter(state, followedStartedAt) {
  var started = String(state && state.startedAt || "")
  return !followedStartedAt || !started || started >= followedStartedAt
}

function newestTime(inbox) {
  var t = ""
  inbox.forEach(function(n) { if (n.createdAt > t) t = n.createdAt })
  return t
}

// Short text for the other events in an inbox row (Linear shows only the newest).
function inboxEventsText(n) {
  if (!n || !n.events || n.events.length < 2) return ""
  var seen = {}, out = []
  n.events.slice(1).forEach(function(e) {
    var t = String(e.subtitle || "").replace(/ by .*$/, "")
    if (t && !seen[t]) { seen[t] = true; out.push(t) }
  })
  return out.length ? "also: " + out.join(", ") : ""
}
