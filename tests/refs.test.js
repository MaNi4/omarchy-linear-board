// Run: node tests/refs.test.js
// Every Linear.X, Issues.X, Time.X… that a QML or JS file uses must exist in
// that JS file, and the file must import it under that name. So a typo, a
// helper moved to another file or a missing import fails here and not when
// someone clicks the button that needs it.
const fs = require("fs"), path = require("path")
const { load, libraries, root } = require("./load")
const libs = {}
for (const name of libraries()) libs[name] = load(name)
const problems = []
const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).forEach(e => {
  const p = path.join(dir, e.name)
  if (e.isDirectory() && !/^(node_modules|tests|\.git)$/.test(e.name)) return walk(p)
  if (!/\.(qml|js)$/.test(e.name)) return
  const text = fs.readFileSync(p, "utf8")
  const code = text.replace(/^\.?import .*$/gm, "").replace(/(^|\s)\/\/.*$/gm, "").replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
  for (const lib in libs) {
    const uses = [...code.matchAll(new RegExp("(^|[^.\\w])" + lib + "\\.([a-zA-Z_]\\w*)", "g"))].map(m => m[2])
    const self = path.relative(root, p) === lib + ".js"
    const imported = new RegExp('^\\.?import "[^"]*\\b' + lib + '\\.js" as ' + lib + "\\b", "m").test(text)
    if (imported && !uses.length) problems.push(path.relative(root, p) + ": imports " + lib + ".js but does not use it")
    if (!uses.length) continue
    if (!imported && !self) problems.push(path.relative(root, p) + ": uses " + lib + ". without importing " + lib + ".js")
    for (const u of uses) if (!(u in libs[lib])) problems.push(path.relative(root, p) + ": " + lib + "." + u + " is not defined")
  }
})
walk(root)
if (problems.length) { console.error("refs:\n  " + [...new Set(problems)].join("\n  ")); process.exit(1) }
console.log("refs: ok (" + Object.keys(libs).join(", ") + ")")
