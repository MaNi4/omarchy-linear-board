.pragma library

// Dates as the board shows and reads them, and when a snooze or reminder
// choice ends. Local time.
// Pure helpers, no QML or network, so tests run them with node.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function pad2(n) { return n < 10 ? "0" + n : String(n) }

// Local calendar date of a Date as YYYY-MM-DD.
function isoDate(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function addDays(d, n) {
  var x = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  x.setDate(x.getDate() + n)
  return x
}

function dateOf(iso) { var p = String(iso).split("-"); return new Date(+p[0], +p[1] - 1, +p[2]) }

// Accepts YYYY-MM-DD (also D.M.YYYY); returns YYYY-MM-DD, "" for empty, or null when invalid.
function parseDate(text) {
  var t = String(text || "").trim()
  if (!t) return ""
  var m = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)
  var y, mo, d
  if (m) { y = +m[1]; mo = +m[2]; d = +m[3] }
  else {
    m = t.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/)
    if (!m) return null
    y = +m[3]; mo = +m[2]; d = +m[1]
  }
  var x = new Date(y, mo - 1, d)
  if (x.getFullYear() !== y || x.getMonth() !== mo - 1 || x.getDate() !== d) return null
  return isoDate(x)
}

// Short label for a due date and how urgent it is, relative to `today` (YYYY-MM-DD).
function dueInfo(due, today) {
  if (!due) return null
  var p = due.split("-")
  var text = MONTHS[+p[1] - 1] + " " + (+p[2])
  if (p[0] !== today.slice(0, 4)) text += " " + p[0]
  var level = due < today ? "overdue" : (due === today ? "today" : "later")
  if (due === today) text = "Today"
  return { text: text, level: level }
}

// "Oct 26, 14:05" for a timestamp, in local time.
function shortDateTime(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// "5m", "3h", "2d" or a date, for inbox rows.
function ago(iso, now) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var s = Math.max(0, (now.getTime() - d.getTime()) / 1000)
  if (s < 60) return "now"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  if (s < 7 * 86400) return Math.floor(s / 86400) + "d"
  return MONTHS[d.getMonth()] + " " + d.getDate()
}

var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var SNOOZE_OPTIONS = [
  { id: "hour", label: "1 hour" },
  { id: "tomorrow", label: "Tomorrow 9:00" },
  { id: "week", label: "Next Monday" }
]

// When a snooze option ends: "hour", "tomorrow" (9:00), "week" (next Monday 9:00).
function snoozeUntil(option, now) {
  var d = new Date(now.getTime())
  if (option === "hour") return new Date(d.getTime() + 3600 * 1000)
  if (option === "tomorrow") return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 9, 0, 0)
  var days = (8 - d.getDay()) % 7 || 7
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, 9, 0, 0)
}

var REMINDER_OPTIONS = [
  { id: "1h", label: "In 1 hour" }, { id: "3h", label: "In 3 hours" },
  { id: "tomorrow", label: "Tomorrow at 9:00" }, { id: "monday", label: "Next Monday at 9:00" },
  { id: "week", label: "In a week at 9:00" }
]

function reminderAt(option, now) {
  var d = new Date(now.getTime())
  if (option === "1h") return new Date(d.getTime() + 3600000)
  if (option === "3h") return new Date(d.getTime() + 3 * 3600000)
  var days = option === "tomorrow" ? 1 : (option === "week" ? 7 : (option === "monday" ? ((8 - d.getDay()) % 7 || 7) : 1))
  var r = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, 9, 0, 0, 0)
  return r
}
