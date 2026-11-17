.pragma library

// Markdown as the board draws and edits it: links, images, checklists,
// typing help and @mentions. Qt's own Markdown cannot do these.
// Pure helpers, no QML or network, so tests run them with node.

// Entities already in the text (&lt; from escapeRawHtml) are kept.
function escapeHtml(t) {
  return String(t).replace(/&(?![A-Za-z]+;|#\d+;)/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// Raw HTML in issue text (anyone in the team can write it) is shown as
// text: Qt would draw it, and load an <img> from any server. Code spans and
// fenced blocks are left as they are, Markdown shows them literally anyway.
// <https://…> autolinks become plain links.
function escapeRawHtml(md) {
  var fence = null
  return String(md || "").split("\n").map(function(line) {
    var f = line.match(/^\s{0,3}(```|~~~)/)
    if (fence) { if (f && f[1] === fence) fence = null; return line }
    if (f) { fence = f[1]; return line }
    return line.split(/(`+[^`]*`+)/).map(function(part, i) {
      return i % 2 ? part : part.replace(/<((?:https?:\/\/|mailto:)[^\s<>]+)>/gi, "$1").replace(/<(?=[A-Za-z\/!?])/g, "&lt;")
    }).join("")
  }).join("\n")
}

// A link as inline HTML with its own color: Qt draws Markdown links in the
// default dark blue whatever linkColor says, which is unreadable on dark themes.
function htmlLink(text, url, color) {
  var mention = /^https:\/\/linear\.app\/[^\/\s]+\/profiles\//.test(url)
  var body = escapeHtml(text)
  if (mention) body = "<b>" + body + "</b>"
  return '<a href="' + String(url).replace(/"/g, "%22") + '"' + (mention ? ' style="text-decoration:none"' : "") + '>' +
    '<span style="color:' + color + '">' + body + "</span></a>"
}

// Images fetched without asking, to show inline: only Linear's own uploads.
// Any other image in issue text (anyone in the workspace writes it) would
// tell its server who opened the issue and when, or make this computer
// request a local address; those stay links, opened in the browser.
function autoImage(url) {
  return /^https:\/\/uploads\.linear\.app\//.test(String(url || ""))
}

// Image URLs in Markdown (![alt](url)), for downloading them to show inline.
function markdownImages(md) {
  var out = [], re = /!\[[^\]]*\]\((https?:\/\/[^)\s]+)[^)]*\)/g, m
  while ((m = re.exec(String(md || ""))) !== null) if (out.indexOf(m[1]) < 0) out.push(m[1])
  return out
}

// Markdown without the image(s) pointing at url, and without the empty
// lines they leave behind.
function removeImage(md, url) {
  var esc = String(url).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  return String(md || "")
    .replace(new RegExp("[ \\t]*!\\[[^\\]]*\\]\\(" + esc + "(?:\\s+\"[^\"]*\")?\\)(\\n)?", "g"), "")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/^\s+|\s+$/g, "")
}

// Markdown split around images, so the board can draw each image itself
// (Qt's Markdown text cannot show them): [{ text } | { image: true, url, alt }].
function splitImages(md) {
  var src = String(md || ""), out = [], re = /!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/g, m, last = 0
  while ((m = re.exec(src)) !== null) {
    var before = src.slice(last, m.index)
    if (before.trim()) out.push({ text: before.replace(/^\s*\n/, "").replace(/\n\s*$/, "") })
    out.push({ image: true, url: m[2], alt: m[1] || "image" })
    last = re.lastIndex
  }
  var rest = src.slice(last)
  if (rest.trim() || !out.length) out.push({ text: rest.replace(/^\s*\n/, "") })
  return out
}

// A task list line: indent, bullet ("-", "*", "+" or "1."), box, text.
var TASK_RE = /^(\s*)([-*+]|\d+[.)])[ \t]+\[([ xX])\](?:[ \t]+(.*))?$/

var FENCE_RE = /^\s*(```|~~~)/

// Markdown split for drawing: text, images and checklist items, so each
// checklist item gets a real checkbox that can be clicked. Task items
// carry the line they come from in md (for toggleTask). Lines inside
// ``` code blocks stay text.
// [{ text } | { image: true, url, alt } | { task: true, checked, text, line, level }]
function splitParts(md) {
  var lines = String(md || "").split("\n"), out = [], buf = [], fence = false
  var flush = function() {
    if (!buf.length) return
    var text = buf.join("\n")
    buf = []
    if (!text.trim()) return
    splitImages(text).forEach(function(p) { if (p.image || p.text.trim()) out.push(p) })
  }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (FENCE_RE.test(line)) fence = !fence
    var m = fence ? null : line.match(TASK_RE)
    if (!m) { buf.push(lines[i]); continue }
    flush()
    var indent = m[1].replace(/\t/g, "    ").length
    out.push({ task: true, checked: m[3] !== " ", text: (m[4] || "").replace(/\s+$/, ""), line: i, level: Math.min(6, Math.floor(indent / 2)) })
  }
  flush()
  if (!out.length) out.push({ text: "" })
  return out
}

// md with the checkbox on line `line` ticked or unticked; md unchanged when
// that line is not a checklist item.
function toggleTask(md, line) {
  var lines = String(md || "").split("\n")
  if (line < 0 || line >= lines.length) return String(md || "")
  var m = lines[line].replace(/\r$/, "").match(TASK_RE)
  var isTask = splitParts(md).some(function(p) { return p.task && p.line === line })
  if (!m || !isTask) return String(md || "")
  lines[line] = lines[line].replace(/\[([ xX])\]/, m[3] === " " ? "[x]" : "[ ]")
  return lines.join("\n")
}

// md with every checklist item unticked (a recurring issue's new copy starts fresh).
function untickTasks(md) {
  var lines = String(md || "").split("\n")
  splitParts(md).forEach(function(p) { if (p.task && p.checked) lines[p.line] = lines[p.line].replace(/\[[xX]\]/, "[ ]") })
  return lines.join("\n")
}

function countTasks(md) {
  var n = 0, done = 0
  splitParts(md).forEach(function(p) { if (p.task) { n++; if (p.checked) done++ } })
  return { total: n, done: done }
}

// Typing help in a Markdown field, like Linear's editor. Each returns the
// change to make, { start, end, text } (replace start..end with text, the
// cursor goes after it), or null to let the key do its usual thing.
// Space after "[]" or "[ ]" at the start of a line: a checklist item.
function taskShortcut(text, cursor) {
  var s = String(text || ""), start = s.lastIndexOf("\n", cursor - 1) + 1
  var m = s.slice(start, cursor).match(/^(\s*)(?:[-*+][ \t]+)?\[ ?\]$/)
  return m ? { start: start, end: cursor, text: m[1] + "- [ ] " } : null
}

// Enter in a list item: the next item (a checklist item starts unticked);
// Enter in an empty item ends the list.
function listEnter(text, cursor) {
  var s = String(text || ""), start = s.lastIndexOf("\n", cursor - 1) + 1
  var before = s.slice(start, cursor)
  var fences = (s.slice(0, start).match(/^\s*(```|~~~)/gm) || []).length
  if (fences % 2) return null
  var m = before.match(/^(\s*)([-*+]|\d+[.)])([ \t]+)(\[[ xX]\][ \t]+)?(.*)$/)
  if (!m) return null
  if (!m[5].trim() && !/\S/.test(s.slice(cursor, (s.indexOf("\n", cursor) + 1 || s.length + 1) - 1)))
    return { start: start, end: cursor, text: "" }
  var bullet = /^\d/.test(m[2]) ? (parseInt(m[2], 10) + 1) + m[2].slice(-1) : m[2]
  return { start: cursor, end: cursor, text: "\n" + m[1] + bullet + m[3] + (m[4] ? "[ ] " : "") }
}

// Markdown as the editor shows it: images become links (splitImages takes
// them out first where the board can draw them), profile links read as
// @mentions, and with linkColor every link is drawn in that color.
// Qt's Markdown loads an image from any server, so no image syntax reaches
// it: an image this does not turn into a link (nested brackets, reference
// style, `` and ``` tricks…) gets an invisible word joiner between ! and [,
// which leaves a plain link. Everywhere, code included: what counts as code
// is Qt's call, and a guess here would be a way around this.
var NO_IMAGE = "!\u2060["
function displayMarkdown(md, linkColor) {
  var out = escapeRawHtml(md)
    .replace(/!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/g, function(m, alt, url) { return "[🖼 " + (alt || "image") + "](" + url + ")" })
    .replace(/!\[/g, NO_IMAGE)
    .replace(/(^|[^(\[])(https:\/\/linear\.app\/[^\/\s]+\/profiles\/([A-Za-z0-9._-]+))/g, function(m, pre, url, user) {
      return pre + "[@" + user + "](" + url + ")"
    })
  if (!linkColor) return out
  return out
    .replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function(m, text, url) { return htmlLink(text, url, linkColor) })
    .replace(/(^|[\s(])(https?:\/\/(?:(?!&lt;)[^\s<>)])+)/g, function(m, pre, url) { return pre + htmlLink(url, url, linkColor) })
}

// Links the board opens with xdg-open: web and mail only.
function openable(url) {
  return /^(https?:\/\/[^\s]+|mailto:[^\s]+)$/i.test(String(url || ""))
}

// "@que" right before the cursor: what to complete, or null.
function mentionQuery(text, cursor) {
  var before = String(text || "").slice(0, cursor)
  var m = before.match(/(^|\s)@([\w.-]*)$/)
  return m ? { query: m[2], start: cursor - m[2].length - 1 } : null
}

function mentionMatches(members, query) {
  var q = String(query || "").toLowerCase()
  return (members || []).filter(function(m) {
    return m.url && (!q || m.name.toLowerCase().indexOf(q) >= 0 || m.fullName.toLowerCase().indexOf(q) >= 0)
  }).slice(0, 6)
}
