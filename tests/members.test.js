// Run: node tests/members.test.js
// The board's parts reach each other by id: root (Board.qml), ed, pickers,
// notices… Every `part.name` a QML file uses must be a property, function
// or signal of that part, so a typo or something moved to another part
// fails here and not when someone clicks the button that needs it.
const fs = require("fs"), path = require("path")
const root = path.join(__dirname, "..")
const read = p => fs.readFileSync(path.join(root, p), "utf8")

// What QML itself gives every Item / QtObject / window (only what the board uses).
const BUILTIN = new Set(("objectName parent children data visible enabled opacity x y z width height implicitWidth implicitHeight " +
  "anchors focus activeFocus forceActiveFocus contains mapToItem mapFromItem childAt state states clip scale rotation " +
  "Keys text cursorPosition selectedText selectionStart selectionEnd length insert remove select selectAll deselect " +
  "positionToRectangle positionAt contentX contentY contentHeight contentWidth running restart start stop interval " +
  "toString destroy left right top bottom horizontalCenter verticalCenter baseline color radius border font").split(" "))

// The members a QML file's top object declares.
function members(file) {
  const out = new Set()
  const text = read(file)
  for (const m of text.matchAll(/^  (?:(?:readonly|required|default) )*property\s+[\w<>.]+\s+(\w+)/gm)) out.add(m[1])
  for (const m of text.matchAll(/^  (?:function|signal)\s+(\w+)/gm)) out.add(m[1])
  for (const m of text.matchAll(/^  property alias (\w+)/gm)) out.add(m[1])
  return out
}

// Parts: `root` is Board.qml; each `Type { id: name` in Board.qml whose
// Type is a file in logic/ or ui/ is that file.
const parts = { root: "Board.qml" }
const board = read("Board.qml")
for (const m of board.matchAll(/^\s*(\w+)\s*\{\s*(?:\n\s*)?id:\s*(\w+)/gm)) {
  for (const dir of ["logic", "ui"]) if (fs.existsSync(path.join(root, dir, m[1] + ".qml"))) parts[m[2]] = dir + "/" + m[1] + ".qml"
}
const known = {}
for (const [id, file] of Object.entries(parts)) known[id] = members(file)

const problems = []
const files = ["Board.qml"].concat(...["logic", "ui"].map(d => fs.readdirSync(path.join(root, d)).filter(f => /\.qml$/.test(f)).map(f => d + "/" + f)))
// Parts a file makes itself (the issue editor's EditorSidebar { id: sidebar }…).
function localParts(text) {
  const out = {}
  for (const m of text.matchAll(/^\s*(\w+)\s*\{\s*(?:\n\s*)?id:\s*(\w+)/gm)) {
    for (const dir of ["logic", "ui"]) {
      const f = dir + "/" + m[1] + ".qml"
      // Wrappers of Qt's Text and TextEdit (Label, TextBox) have all of their members; skip them.
      if (fs.existsSync(path.join(root, f)) && !/^(Text|TextEdit)\s*\{/m.test(read(f))) out[m[2]] = f
    }
  }
  return out
}

for (const file of files) {
  const text = read(file)
  // A file's own top id may shadow a part's name (Board's root); skip that part there.
  const self = (text.match(/^  id:\s*(\w+)/m) || [])[1]
  const local = file === "Board.qml" ? {} : localParts(text)
  const here = Object.assign({}, known)
  for (const [id, f] of Object.entries(local)) { here[id] = members(f); parts[id] = parts[id] || f }
  const code = text.replace(/^import .*$/gm, "").replace(/(^|\s)\/\/.*$/gm, "").replace(/"(?:[^"\\\n]|\\.)*"/g, '""').replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
  for (const [id, names] of Object.entries(here)) {
    if (id === self && parts[id] !== file) continue
    for (const m of code.matchAll(new RegExp("(^|[^.\\w])" + id + "\\.([a-zA-Z_]\\w*)", "g"))) {
      if (!names.has(m[2]) && !BUILTIN.has(m[2])) problems.push(file + ": " + id + "." + m[2] + " is not in " + (local[id] || parts[id]))
    }
  }
}
if (problems.length) { console.error("members:\n  " + [...new Set(problems)].join("\n  ")); process.exit(1) }
console.log("members: ok (" + Object.keys(parts).length + " parts)")
