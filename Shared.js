.pragma library

// What the board keeps outside Linear, besides time entries (Time.js):
// recurring issue rules, project codes and how the board is laid out. In a
// shared folder these settings sit in linear-board.json next to the time
// file, so every computer pointed at the folder uses the same ones. Pure
// helpers only, so tests/shared.test.js can run them with node.

var VERSION = 1
var FILE_NAME = "linear-board.json"
var EXPORT_KIND = "linear-board-export"

// config.json keys that are shared. The rest stays per computer: the team,
// project and assignee filter the board is on right now.
var KEYS = ["recurring", "projectCodes", "hidden", "sort", "group", "layout", "doneWindow", "timeComments", "desktopNotify"]

function isObject(v) { return !!v && typeof v === "object" && !Array.isArray(v) }

// Only the shared keys, checked; missing or broken ones are left out.
function clean(c) {
  var out = {}
  if (!isObject(c)) return out
  if (Array.isArray(c.recurring)) out.recurring = c.recurring.filter(function(r) { return isObject(r) && r.id && r.title && r.teamId })
  if (isObject(c.projectCodes)) out.projectCodes = c.projectCodes
  if (isObject(c.hidden)) out.hidden = c.hidden
  if (typeof c.sort === "string" && c.sort) out.sort = c.sort
  if (typeof c.group === "string" && c.group) out.group = c.group
  if (c.layout === "list" || c.layout === "board") out.layout = c.layout
  if (["none", "week", "2weeks", "month", "quarter", "all"].indexOf(c.doneWindow) >= 0) out.doneWindow = c.doneWindow
  if (typeof c.timeComments === "boolean") out.timeComments = c.timeComments
  if (typeof c.desktopNotify === "boolean") out.desktopNotify = c.desktopNotify
  return out
}

function pick(config) {
  var out = {}
  KEYS.forEach(function(k) { if (config && config[k] !== undefined) out[k] = config[k] })
  return out
}

function serialize(config) {
  var out = { version: VERSION }
  var p = pick(config)
  for (var k in p) out[k] = p[k]
  return JSON.stringify(out, null, 2) + "\n"
}

// Read linear-board.json. Returns { data } (the shared keys) or { error }
// when the file cannot be used as is (then nothing is written over it).
function parse(text) {
  var t = String(text || "").trim()
  if (!t) return { data: {} }
  var d
  try { d = JSON.parse(t) } catch (e) { return { error: "The shared settings file is not valid JSON." } }
  if (!isObject(d)) return { error: "The shared settings file is not an object." }
  return { data: clean(d) }
}

// config with the shared keys taken from `shared`.
function apply(config, shared) {
  var next = {}
  for (var k in config) next[k] = config[k]
  for (var s in shared) next[s] = shared[s]
  return next
}

// True when the shared keys differ between two configs.
function differs(a, b) {
  return KEYS.some(function(k) { return JSON.stringify(a ? a[k] : undefined) !== JSON.stringify(b ? b[k] : undefined) })
}

// ---- export / import of everything kept outside Linear ----------------------------

function exportText(config, timeData, now) {
  return JSON.stringify({ kind: EXPORT_KIND, version: VERSION, exportedAt: (now || new Date()).toISOString(),
    settings: pick(config), time: { version: 1, running: timeData.running || null, entries: timeData.entries || [] } }, null, 1) + "\n"
}

// An export file: this board's own, or an older time-only export.
// Returns { settings, time (raw, for Time.parse) } or { error }.
function parseExport(text) {
  var d
  try { d = JSON.parse(String(text || "")) } catch (e) { return { error: "The file is not valid JSON." } }
  if (!isObject(d)) return { error: "The file is not an export of this board." }
  if (d.kind === EXPORT_KIND) return { settings: clean(d.settings), time: isObject(d.time) ? d.time : null }
  if (Array.isArray(d.entries)) return { settings: {}, time: d }
  return { error: "The file is not an export of this board." }
}

// Adds what the import has and this computer lacks; nothing here is
// replaced. Recurring rules by id, project codes and hidden columns by
// key. Returns { config, rules, codes } (counts of what was added).
function mergeSettings(config, incoming) {
  var next = {}
  for (var k in config) next[k] = config[k]
  var rules = 0, codes = 0
  if (incoming.recurring) {
    var have = {}
    ;(config.recurring || []).forEach(function(r) { have[r.id] = true })
    var add = incoming.recurring.filter(function(r) { return !have[r.id] })
    rules = add.length
    if (rules) next.recurring = (config.recurring || []).concat(add)
  }
  if (incoming.projectCodes) {
    var pc = {}
    for (var a in (config.projectCodes || {})) pc[a] = config.projectCodes[a]
    for (var b in incoming.projectCodes) if (pc[b] === undefined) { pc[b] = incoming.projectCodes[b]; codes++ }
    if (codes) next.projectCodes = pc
  }
  if (incoming.hidden) {
    var hd = {}, more = false
    for (var c in (config.hidden || {})) hd[c] = config.hidden[c]
    for (var t in incoming.hidden) if (hd[t] === undefined) { hd[t] = incoming.hidden[t]; more = true }
    if (more) next.hidden = hd
  }
  return { config: next, rules: rules, codes: codes }
}

// ---- copies Syncthing keeps when two computers changed a file at once ----
// "linear-time.json" → its conflict copies are named
// "linear-time.sync-conflict-20261114-221500-ABCDEFG.json". Returns the
// glob for them, or "" for a name without an extension.
function conflictGlob(fileName) {
  var m = /^(.+)(\.[^.\/]+)$/.exec(String(fileName || ""))
  return m ? m[1] + ".sync-conflict-*" + m[2] : ""
}

if (typeof module !== "undefined") {
  module.exports = { VERSION: VERSION, FILE_NAME: FILE_NAME, KEYS: KEYS, clean: clean, pick: pick, serialize: serialize,
    parse: parse, apply: apply, differs: differs, exportText: exportText, parseExport: parseExport, mergeSettings: mergeSettings,
    conflictGlob: conflictGlob }
}
