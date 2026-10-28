.pragma library

// Time tracking for the Linear board. Linear has no time tracking of its own,
// so entries live in a JSON file (time.json) that can sit in a synced folder;
// optionally each entry is also posted to the issue as a comment. Pure
// helpers only, so tests/time.test.js can run them with node.

var VERSION = 1
// Shorter stretches are dropped when a timer stops (a start by mistake).
// Shorter runs are treated as a mis-click and dropped (with a notice).
var MIN_SECONDS = 10

function emptyData() {
  return { version: VERSION, running: null, entries: [] }
}

// Read a time file. Returns { data } or { error } when the file cannot be
// used as is (then nothing should be written over it).
function parse(text) {
  var t = String(text || "").trim()
  if (!t) return { data: emptyData() }
  var d
  try { d = JSON.parse(t) } catch (e) { return { error: "The time file is not valid JSON." } }
  if (!d || typeof d !== "object" || !Array.isArray(d.entries)) return { error: "The time file has no entries list." }
  var entries = []
  for (var i = 0; i < d.entries.length; i++) {
    var e = toEntry(d.entries[i])
    if (!e) return { error: "Entry " + (i + 1) + " in the time file is not readable." }
    entries.push(e)
  }
  var r = d.running
  var running = r && r.issueId && r.startedAt && !isNaN(new Date(r.startedAt).getTime()) ? {
    issueId: String(r.issueId), identifier: String(r.identifier || ""), title: String(r.title || ""),
    url: String(r.url || ""), projectId: String(r.projectId || ""), projectName: String(r.projectName || ""), teamName: String(r.teamName || ""),
    startedAt: String(r.startedAt), device: String(r.device || "")
  } : null
  return { data: { version: VERSION, running: running, entries: entries } }
}

function toEntry(e) {
  if (!e || typeof e !== "object") return null
  var start = new Date(e.start)
  var seconds = Math.round(Number(e.seconds))
  if (!e.id || !e.issueId || isNaN(start.getTime()) || !(seconds > 0)) return null
  return {
    id: String(e.id), issueId: String(e.issueId), identifier: String(e.identifier || ""), title: String(e.title || ""),
    url: String(e.url || ""), projectName: String(e.projectName || ""), teamName: String(e.teamName || ""),
    start: start.toISOString(), seconds: seconds, note: String(e.note || ""),
    commentId: String(e.commentId || ""), device: String(e.device || ""), manual: e.manual === true
  }
}

function serialize(data) {
  return JSON.stringify({ version: VERSION, running: data.running || null, entries: data.entries || [] }, null, 1) + "\n"
}

function newId(now) {
  return now.getTime().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
}

// Issue facts kept with an entry, so reports read well without Linear.
function issueInfo(issue, projectName, teamName) {
  return { issueId: issue.id, identifier: issue.identifier || "", title: issue.title || "", url: issue.url || "",
    projectId: issue.projectId || "", projectName: projectName || issue.projectName || "", teamName: teamName || issue.teamName || "" }
}

function entryFromRunning(running, end, id, device) {
  var start = new Date(running.startedAt)
  var seconds = Math.round((end.getTime() - start.getTime()) / 1000)
  return {
    id: id, issueId: running.issueId, identifier: running.identifier, title: running.title, url: running.url || "",
    projectName: running.projectName, teamName: running.teamName, start: start.toISOString(), seconds: seconds,
    note: "", commentId: "", device: device || running.device || "", manual: false
  }
}

// ---- durations ------------------------------------------------------------------

// "1h 30m", "90m", "1.5h", "1:30", "45" (minutes), "2h" -> seconds; null when unreadable.
function parseDuration(text) {
  var t = String(text || "").trim().toLowerCase().replace(",", ".")
  if (!t) return null
  var m = t.match(/^(\d+):(\d{1,2})$/)
  if (m) return (+m[1] * 60 + +m[2]) * 60 || null
  if (/^\d+(\.\d+)?$/.test(t)) return Math.round(parseFloat(t) * 60) || null
  var re = /(\d+(?:\.\d+)?)\s*(hours?|hod|h|minutes?|min|m)/g, total = 0, used = "", x
  while ((x = re.exec(t)) !== null) {
    total += parseFloat(x[1]) * (x[2][0] === "h" ? 3600 : 60)
    used += x[0]
  }
  if (!total || used.replace(/\s/g, "").length !== t.replace(/\s/g, "").length) return null
  return Math.round(total)
}

// 5400 -> "1h 30m"; under a minute -> "0m".
function formatDuration(seconds) {
  seconds = Math.max(0, Math.floor(seconds || 0))
  if (seconds > 0 && seconds < 60) return seconds + "s"
  var mins = Math.floor(seconds / 60)
  var h = Math.floor(mins / 60), m = mins % 60
  if (!h) return m + "m"
  return h + "h" + (m ? " " + m + "m" : "")
}

// Running clock: 754 -> "12:34", 3754 -> "1:02:34".
function formatClock(seconds) {
  var s = Math.max(0, Math.floor(seconds))
  var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
  var p = function(n) { return n < 10 ? "0" + n : String(n) }
  return (h ? h + ":" + p(m) : String(m)) + ":" + p(sec)
}

// Decimal hours for spreadsheets: 5400 -> "1.50".
function hours(seconds) { return (seconds / 3600).toFixed(2) }

// ---- periods ----------------------------------------------------------------------

function pad2(n) { return n < 10 ? "0" + n : String(n) }
function isoDate(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// kind: day | week (Monday first) | month; offset: 0 now, -1 the one before…
// Returns { from, to (exclusive), label }.
function period(kind, offset, now) {
  var d = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var from, to, label
  if (kind === "month") {
    from = new Date(d.getFullYear(), d.getMonth() + offset, 1)
    to = new Date(from.getFullYear(), from.getMonth() + 1, 1)
    label = MONTHS[from.getMonth()] + " " + from.getFullYear()
  } else if (kind === "week") {
    var back = (d.getDay() + 6) % 7
    from = new Date(d.getFullYear(), d.getMonth(), d.getDate() - back + 7 * offset)
    to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 7)
    var last = new Date(to.getFullYear(), to.getMonth(), to.getDate() - 1)
    label = from.getDate() + " " + MONTHS[from.getMonth()] + " – " + last.getDate() + " " + MONTHS[last.getMonth()] + " " + last.getFullYear()
  } else {
    from = new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset)
    to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 1)
    label = offset === 0 ? "Today" : (offset === -1 ? "Yesterday" : from.getDate() + " " + MONTHS[from.getMonth()] + " " + from.getFullYear())
  }
  return { from: from, to: to, label: label }
}

function inPeriod(entry, p) {
  var t = new Date(entry.start).getTime()
  return t >= p.from.getTime() && t < p.to.getTime()
}

// Entries of a period, newest first.
function entriesIn(entries, p) {
  return (entries || []).filter(function(e) { return inPeriod(e, p) })
    .sort(function(a, b) { return a.start < b.start ? 1 : (a.start > b.start ? -1 : 0) })
}

// Totals by "issue" or "project", biggest first: [{ key, label, sub, seconds, count }].
function summarize(entries, by) {
  var map = {}, out = []
  ;(entries || []).forEach(function(e) {
    var key = by === "project" ? (e.projectName || "") : e.issueId
    var g = map[key]
    if (!g) {
      g = map[key] = by === "project"
        ? { key: key, label: e.projectName || "No project", sub: e.teamName, seconds: 0, count: 0 }
        : { key: key, label: (e.identifier ? e.identifier + "  " : "") + e.title, sub: e.projectName, seconds: 0, count: 0, url: e.url, issueId: e.issueId }
      out.push(g)
    }
    g.seconds += e.seconds
    g.count++
  })
  return out.sort(function(a, b) { return b.seconds - a.seconds })
}

function total(entries) {
  return (entries || []).reduce(function(s, e) { return s + e.seconds }, 0)
}

function totalFor(entries, issueId) {
  return total((entries || []).filter(function(e) { return e.issueId === issueId }))
}

// Seconds per issue, for card badges: { issueId: seconds }.
function totalsByIssue(entries) {
  var out = {}
  ;(entries || []).forEach(function(e) { out[e.issueId] = (out[e.issueId] || 0) + e.seconds })
  return out
}

// ---- CSV ----------------------------------------------------------------------------

function csvCell(v) {
  var s = String(v === undefined || v === null ? "" : v)
  return /[",\n;]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
}

// One row per entry, oldest first, in local time.
function toCsv(entries) {
  var rows = [["Date", "Start", "End", "Hours", "Duration", "Issue", "Title", "Project", "Team", "Note", "Manual"]]
  ;(entries || []).slice().sort(function(a, b) { return a.start < b.start ? -1 : 1 }).forEach(function(e) {
    var s = new Date(e.start), end = new Date(s.getTime() + e.seconds * 1000)
    var hm = function(d) { return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) }
    rows.push([isoDate(s), e.manual ? "" : hm(s), e.manual ? "" : hm(end), hours(e.seconds), formatDuration(e.seconds),
      e.identifier, e.title, e.projectName, e.teamName, e.note, e.manual ? "yes" : ""])
  })
  return rows.map(function(r) { return r.map(csvCell).join(",") }).join("\n") + "\n"
}

// ---- import / merge ----------------------------------------------------------------

// Entries of `incoming` that `base` lacks are added (same id = same entry,
// the base copy wins). Returns { data, added }.
function merge(base, incoming) {
  var have = {}
  base.entries.forEach(function(e) { have[e.id] = true })
  var added = incoming.entries.filter(function(e) { return !have[e.id] })
  return {
    data: { version: VERSION, running: base.running || incoming.running || null, entries: base.entries.concat(added) },
    added: added.length
  }
}

// Text for the Linear comment about an entry.
function commentBody(entry) {
  var s = new Date(entry.start), end = new Date(s.getTime() + entry.seconds * 1000)
  var hm = function(d) { return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) }
  var when = entry.manual ? isoDate(s) : isoDate(s) + " " + hm(s) + "–" + hm(end)
  return "⏱ **" + formatDuration(entry.seconds) + "** logged (" + when + ")" + (entry.note ? ": " + entry.note : "")
}

// "Oct 26, 09:15" / "Oct 26" for manual entries.
function entryWhen(entry) {
  var s = new Date(entry.start)
  var day = MONTHS[s.getMonth()] + " " + s.getDate()
  if (entry.manual) return day
  var end = new Date(s.getTime() + entry.seconds * 1000)
  return day + ", " + pad2(s.getHours()) + ":" + pad2(s.getMinutes()) + "–" + pad2(end.getHours()) + ":" + pad2(end.getMinutes())
}

// Start time for a manual entry on a date (YYYY-MM-DD): noon local, so time
// zones never move it to another day.
function manualStart(dateText) {
  var m = String(dateText || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return null
  var d = new Date(+m[1], +m[2] - 1, +m[3], 12, 0, 0)
  return isNaN(d.getTime()) ? null : d
}

if (typeof module !== "undefined") {
  module.exports = {
    MIN_SECONDS: MIN_SECONDS, emptyData: emptyData, parse: parse, serialize: serialize, newId: newId, issueInfo: issueInfo,
    entryFromRunning: entryFromRunning, parseDuration: parseDuration, formatDuration: formatDuration, formatClock: formatClock,
    hours: hours, period: period, entriesIn: entriesIn, summarize: summarize, total: total, totalFor: totalFor,
    totalsByIssue: totalsByIssue, toCsv: toCsv, merge: merge, commentBody: commentBody, entryWhen: entryWhen,
    manualStart: manualStart, isoDate: isoDate
  }
}
