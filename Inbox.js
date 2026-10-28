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
