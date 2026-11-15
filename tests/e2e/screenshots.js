// Run: node tests/e2e/screenshots.js
// The README's pictures and preview.png, from made-up data (the fake
// server's demo set: a product team mid-cycle), never from a real Linear
// account. Same isolated offscreen board as the end-to-end tests, in the
// current Omarchy theme. Needs ImageMagick (magick) for preview.png.
const fs = require("fs"), path = require("path"), { execFileSync } = require("child_process")
const H = require("./run.js")
const { ev, waitFor, sleep } = H

const OUT = path.join(H.ROOT, "screenshots")

// The theme's colors (the board's window is partly see-through: the
// picture goes on the background a desktop would show through it).
const THEME = fs.readFileSync(path.join(process.env.HOME, ".local/state/omarchy/current/theme/colors.toml"), "utf8")
const color = (name, fallback) => (THEME.match(new RegExp("^" + name + "\\s*=\\s*\"(#[0-9a-fA-F]{6})\"", "m")) || [])[1] || fallback

async function shot(name) {
  const file = await H.shot(name)
  // Qt writes the file in the background: wait until it stops growing.
  let size = -1
  await waitFor(() => { const now = fs.existsSync(file) ? fs.statSync(file).size : 0; const done = now > 0 && now === size; size = now; return done }, 10000, name + ".png to be written")
  await sleep(500)
  execFileSync("magick", [file, "-background", color("background", "#282828"), "-flatten", "-alpha", "off", "-strip", "PNG24:" + path.join(OUT, name + ".png")])
  console.log("screenshots/" + name + ".png")
}

async function main() {
  H.setup()
  await H.startServer()
  await H.ctl("demo")
  fs.mkdirSync(OUT, { recursive: true })
  // A timer running on WEB-140 for 47 minutes.
  const started = new Date(Date.now() - 47 * 60000).toISOString()
  const time = { version: 1, running: { issueId: "issue-140", identifier: "WEB-140", title: "Apple Pay on the payment step", url: "", projectId: "project-checkout",
    projectName: "Checkout v2", teamName: "Web App", startedAt: started }, entries: [] }
  await H.startBoard({ config: JSON.stringify({ teamId: "team-web", desktopNotify: false, group: "none", projectCodes: { "project-checkout": "CHK", "project-onboarding": "ONB", "project-perf": "SPD" } }),
    time: JSON.stringify(time) })
  await waitFor(() => ev("board.issues.length > 10 && board.pending === 0"), 15000, "the demo issues")
  await waitFor(() => { const s = H.inboxState(); return s && s.checkedAt }, 15000, "the inbox")
  ev("board.open('{}')")
  ev("board.selCol = 2; board.selIdx = 0")
  await sleep(1500)
  await shot("board")

  ev("m('editIssue').editIssue('issue-140')")
  await waitFor(() => ev("board.dialog") === "issue" && !ev("p('milestoneValid').detailLoading") && ev("p('milestoneValid').comments.length") === 2, 10000, "the editor")
  await sleep(1200)
  await shot("editor")
  ev("m('closeDialog').closeDialog()")

  ev("m('openInbox').openInbox()")
  await waitFor(() => ev("board.dialog") === "inbox", 5000, "the inbox")
  await sleep(1000)
  await shot("inbox")
  ev("m('closeDialog').closeDialog()")

  ev("m('openProject').openProject('project-checkout')")
  await waitFor(() => ev("m('openProject').projectViewId") === "project-checkout" && !ev("m('openProject').projectLoading"), 8000, "the project")
  await sleep(1200)
  await shot("project")
  ev("m('closeDialog').closeDialog()")

  await H.stopBoard()
  H.stopServer()

  // preview.png: the board on the theme's darkest background, 1600 × 900,
  // like the other mani4 plugins.
  const bg = color("darker_background", "#1e2122")
  execFileSync("magick", [path.join(OUT, "board.png"), "-resize", "1480x820", "-background", bg, "-gravity", "center", "-extent", "1600x900",
    "-strip", "PNG24:" + path.join(H.ROOT, "preview.png")])
  console.log("preview.png")
  fs.rmSync(H.TMP, { recursive: true, force: true })
}

main().catch(async e => { console.error(e); try { await H.stopBoard(); H.stopServer() } catch (x) {} process.exit(1) })
