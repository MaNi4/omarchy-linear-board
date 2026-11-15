.pragma library
.import "Dates.js" as Dates

// Recurring issues. Linear's API has none, so the board keeps the rules
// (Shared.js stores them) and creates each copy itself when it is due.
// Pure helpers, no QML or network, so tests run them with node.

var RECUR_KINDS = [
  { id: "day", label: "Every day" }, { id: "weekday", label: "Every weekday" },
  { id: "week", label: "Every week" }, { id: "month", label: "Every month" }
]

function recurLabel(every) {
  for (var i = 0; i < RECUR_KINDS.length; i++) if (RECUR_KINDS[i].id === every) return RECUR_KINDS[i].label
  return every
}

// Does the date (YYYY-MM-DD) fall on the rule's schedule? `start` is the first
// occurrence; weekly repeats its weekday, monthly its day of the month (the
// last day for short months).
function recursOn(rule, iso) {
  if (iso < rule.start) return false
  var d = Dates.dateOf(iso), s = Dates.dateOf(rule.start)
  if (rule.every === "day") return true
  if (rule.every === "weekday") return d.getDay() >= 1 && d.getDay() <= 5
  if (rule.every === "week") return d.getDay() === s.getDay()
  if (rule.every === "month") {
    var last = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
    return d.getDate() === Math.min(s.getDate(), last)
  }
  return false
}

// The newest occurrence on or before `today` that has not been created yet
// (after rule.last), or "" when nothing is due. Missed days are not caught
// up one by one: only the latest one is created.
function recurDue(rule, today) {
  if (!rule || !rule.start || !rule.every) return ""
  var d = Dates.dateOf(today)
  for (var n = 0; n < 40; n++) {
    var iso = Dates.isoDate(d)
    if (rule.last && iso <= rule.last) return ""
    if (iso < rule.start) return ""
    if (recursOn(rule, iso)) return iso
    d = Dates.addDays(d, -1)
  }
  return ""
}

// The next occurrence strictly after `after` (for the settings list).
function recurNext(rule, after) {
  var d = Dates.addDays(Dates.dateOf(after < rule.start ? Dates.isoDate(Dates.addDays(Dates.dateOf(rule.start), -1)) : after), 1)
  for (var n = 0; n < 400; n++) {
    var iso = Dates.isoDate(d)
    if (recursOn(rule, iso)) return iso
    d = Dates.addDays(d, 1)
  }
  return ""
}

// First occurrence for a new rule made today: the next matching day after today.
function recurStart(every, today) {
  var t = Dates.dateOf(today)
  if (every === "day") return Dates.isoDate(Dates.addDays(t, 1))
  if (every === "weekday") { var d = Dates.addDays(t, 1); while (d.getDay() === 0 || d.getDay() === 6) d = Dates.addDays(d, 1); return Dates.isoDate(d) }
  if (every === "week") return Dates.isoDate(Dates.addDays(t, 7))
  if (every === "month") return Dates.isoDate(new Date(t.getFullYear(), t.getMonth() + 1, Math.min(t.getDate(), new Date(t.getFullYear(), t.getMonth() + 2, 0).getDate())))
  return Dates.isoDate(Dates.addDays(t, 1))
}

// The repeat rule an issue belongs to: the one made from it (issueId), else
// one with its team, project and title (the copies it made, and rules made
// before issueId was kept). An issue duplicated into another project is
// not part of the series. null when it does not repeat.
function recurRuleFor(rules, issue) {
  if (!issue || !rules || !rules.length) return null
  for (var i = 0; i < rules.length; i++) if (rules[i].issueId && rules[i].issueId === issue.id) return rules[i]
  for (var j = 0; j < rules.length; j++) if (inRecurSeries(rules[j], issue)) return rules[j]
  return null
}

// Rules updated from their issues ({ id, title, projectId, milestoneId } by
// issue id): a rule takes the current title and project of the issue it
// is tied to (issueId), e.g. after a rename in Linear. null when nothing changed.
function recurFollow(rules, sources) {
  var changed = false
  var out = (rules || []).map(function(r) {
    var s = r.issueId ? sources[r.issueId] : null
    if (!s) return r
    if (s.title === r.title && (s.projectId || "") === (r.projectId || "") && (s.milestoneId || "") === (r.milestoneId || "")) return r
    var n = {}
    for (var k in r) n[k] = r[k]
    n.title = s.title
    n.projectId = s.projectId || ""
    n.milestoneId = s.milestoneId || ""
    changed = true
    return n
  })
  return changed ? out : null
}

function inRecurSeries(rule, issue) {
  return rule.teamId === issue.teamId && rule.title === issue.title && (rule.projectId || "") === (issue.projectId || "")
}

// The day the rule makes its next copy, seen from today.
function recurUpcoming(rule, today) {
  return recurNext(rule, rule.last && rule.last >= today ? rule.last : Dates.isoDate(Dates.addDays(Dates.dateOf(today), -1)))
}

// The id (a UUID) of the copy of `ruleId` for the day `iso`: the same on
// every computer, so when two of them create the copy at the same moment
// Linear refuses the second ("conflict on insert") instead of making two.
function recurIssueId(ruleId, iso) {
  var text = String(ruleId) + "|" + String(iso)
  var hex = ""
  for (var seed = 0; seed < 4; seed++) {
    var h = (0x811c9dc5 ^ (seed * 0x9e3779b1)) >>> 0
    for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0 }
    hex += ("00000000" + h.toString(16)).slice(-8)
  }
  return hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-4" + hex.slice(13, 16) + "-" +
    "89ab".charAt(parseInt(hex.charAt(16), 16) & 3) + hex.slice(17, 20) + "-" + hex.slice(20, 32)
}
