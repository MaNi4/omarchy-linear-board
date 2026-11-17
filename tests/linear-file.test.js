// Run: node tests/linear-file.test.js
// bin/linear-file reads and writes the files in the shared folder (the time
// file, linear-board.json, sync conflict copies). Whoever else syncs that
// folder can put a link in place of any of them, and Syncthing keeps links
// as links: a read never follows one (nothing of yours elsewhere is read
// and synced back), and a write replaces the link itself (nothing of yours
// elsewhere is overwritten), whenever the link appeared.
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path")
const { spawnSync } = require("child_process")
const BIN = path.join(__dirname, "..", "bin", "linear-file")

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-linear-file-"))
const run = (args, input) => spawnSync("python3", ["-I", BIN, ...args], { input: input || "", encoding: "utf8" })
try {
  const file = path.join(dir, "linear-time.json"), victim = path.join(dir, "victim.txt"), link = path.join(dir, "link.json")
  fs.writeFileSync(victim, "your own file\n")
  fs.symlinkSync(victim, link)

  // write: a fresh 0600 file, made whole or not at all
  let r = run(["write", file], '{"a":1}\n')
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(fs.readFileSync(file, "utf8"), '{"a":1}\n')
  assert.strictEqual(fs.statSync(file).mode & 0o777, 0o600)
  fs.chmodSync(file, 0o644)
  run(["write", file], '{"a":2}\n')
  assert.strictEqual(fs.statSync(file).mode & 0o777, 0o600, "a file readable by others is replaced by a private one")

  // read
  r = run(["read", file])
  assert.strictEqual(r.status, 0)
  assert.strictEqual(r.stdout, '{"a":2}\n')
  assert.strictEqual(run(["read", path.join(dir, "missing.json")]).status, 2, "missing: 2")
  r = run(["read", link])
  assert.strictEqual(r.status, 3, "a link: 3")
  assert.strictEqual(r.stdout, "", "nothing of the linked file is read")
  const fifo = path.join(dir, "fifo.json")
  if (spawnSync("mkfifo", [fifo]).status === 0) assert.strictEqual(run(["read", fifo]).status, 4, "not a regular file: 4, without blocking")
  assert.strictEqual(run(["read", dir]).status, 4, "a folder: 4")

  // write over a link: the link is replaced, its target untouched
  r = run(["write", link], '{"b":1}\n')
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(fs.readFileSync(victim, "utf8"), "your own file\n", "the link's target is untouched")
  assert.ok(!fs.lstatSync(link).isSymbolicLink(), "the link is replaced by the file")
  assert.strictEqual(fs.readFileSync(link, "utf8"), '{"b":1}\n')

  // a link to a folder is not written into
  const sub = path.join(dir, "sub"); fs.mkdirSync(sub)
  const dirLink = path.join(dir, "dirlink.json"); fs.symlinkSync(sub, dirLink)
  r = run(["write", dirLink], "x")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.deepStrictEqual(fs.readdirSync(sub), [], "nothing lands in the linked folder")
  assert.ok(!fs.lstatSync(dirLink).isSymbolicLink())

  // tighten: a file others can read becomes 0600 with the same content; a link is left alone
  fs.writeFileSync(file, "keep\n"); fs.chmodSync(file, 0o644)
  const inode = fs.statSync(file).ino
  assert.strictEqual(run(["tighten", file]).status, 0)
  assert.strictEqual(fs.statSync(file).mode & 0o777, 0o600)
  assert.strictEqual(fs.readFileSync(file, "utf8"), "keep\n")
  assert.notStrictEqual(fs.statSync(file).ino, inode, "a new file, not chmod (an open copy could still be read)")
  fs.chmodSync(victim, 0o644)
  const link2 = path.join(dir, "link2.json"); fs.symlinkSync(victim, link2)
  assert.strictEqual(run(["tighten", link2]).status, 3)
  assert.strictEqual(fs.statSync(victim).mode & 0o777, 0o644, "the link's target is untouched")

  // --follow (the board's own folders, where a link is yours): followed
  const own = path.join(dir, "own.json"), ownLink = path.join(dir, "own-link.json")
  fs.writeFileSync(own, "mine\n"); fs.symlinkSync(own, ownLink)
  r = run(["read", "--follow", ownLink])
  assert.strictEqual(r.status, 0); assert.strictEqual(r.stdout, "mine\n")
  assert.strictEqual(run(["write", "--follow", ownLink], "new\n").status, 0)
  assert.ok(fs.lstatSync(ownLink).isSymbolicLink(), "the link stays")
  assert.strictEqual(fs.readFileSync(own, "utf8"), "new\n")

  // nothing is left behind next to the file
  assert.deepStrictEqual(fs.readdirSync(dir).filter(n => /tmp|\.part/.test(n)), [])
  assert.strictEqual(run(["bogus", file]).status, 64)
  console.log("linear-file: ok")
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
