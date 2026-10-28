// Loads one of the board's `.pragma library` JS files under node, the way
// QML does: top-level names become the library's members, and each
// `.import "X.js" as X` line is loaded the same way and put under X.
const fs = require("fs"), path = require("path"), vm = require("vm")
const root = path.join(__dirname, "..")
const cache = {}

function load(name) {
  if (cache[name]) return cache[name]
  const src = fs.readFileSync(path.join(root, name + ".js"), "utf8")
  const sandbox = { module: { exports: {} } }
  cache[name] = sandbox
  for (const m of src.matchAll(/^\.import "([\w.\/-]+)\.js" as (\w+)\s*$/gm)) sandbox[m[2]] = load(m[1])
  vm.runInNewContext(src.replace(/^\.(pragma|import) .*$/gm, ""), sandbox, { filename: name + ".js" })
  return sandbox
}

// Every JS library at the plugin root, by name.
function libraries() {
  return fs.readdirSync(root).filter(f => /^[A-Z]\w*\.js$/.test(f)).map(f => f.slice(0, -3))
}

module.exports = { load, libraries, root }
