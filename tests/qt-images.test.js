// Run: node tests/qt-images.test.js   (needs Qt 6's `qml`; QML_BIN overrides it)
// Issue text is drawn with Qt's Markdown (Text.MarkdownText), and Qt loads
// an image in it from any server: whoever wrote the issue would see who
// opened it and when, or make this computer request a local address. So
// Markdown.displayMarkdown must never hand Qt an image, whatever shape the
// Markdown takes. This draws its output in real Qt against a local server
// and fails on any request. The control (Markdown not passed through
// displayMarkdown) proves the server would see one.
const http = require("http"), fs = require("fs"), os = require("os"), path = require("path")
const { spawn } = require("child_process")
const { load } = require("./load")
const M = load("Markdown")

const QML = process.env.QML_BIN || "/usr/lib/qt6/bin/qml"
if (!fs.existsSync(QML)) { console.log("qt-images: skipped (no " + QML + ")"); process.exit(0) }

const shapes = port => {
  const u = name => "HTTP://127.0.0.1:" + port + "/" + name + ".png"
  const l = name => "http://127.0.0.1:" + port + "/" + name + ".png"
  return {
    plain: "![x](" + l("plain") + ")",
    nested: "![a [b]](" + u("nested") + ")",
    nestedLower: "![a [b]](" + l("nestedLower") + ")",
    reference: "![x][r]\n\n[r]: " + u("reference"),
    referenceLower: "![x][r]\n\n[r]: " + l("referenceLower"),
    angle: "![x](<" + l("angle") + ">)",
    ticks: "`` ![a [b]](" + u("ticks") + ") `",
    fence: "```a`b\n![a [b]](" + u("fence") + ")\n```",
    backslash: "\\\\![a [b]](" + u("backslash") + ")",
    inLink: "[![a [b]](" + u("inLink") + ")](https://x.io)",
    title: '![a [b]](' + u("title") + ' "t")',
    collapsed: "![r][]\n\n[r]: " + u("collapsed"),
    shortcut: "![r]\n\n[r]: " + u("shortcut"),
    rawHtml: '<img src="' + l("rawHtml") + '">'
  }
}

function run(qmlText) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-qt-images-"))
  const file = path.join(dir, "t.qml")
  fs.writeFileSync(file, qmlText)
  return new Promise(resolve => {
    const p = spawn(QML, [file], { env: Object.assign({}, process.env, { QT_QPA_PLATFORM: "offscreen" }), stdio: "ignore" })
    const kill = setTimeout(() => p.kill("SIGKILL"), 15000)
    p.on("exit", () => { clearTimeout(kill); fs.rmSync(dir, { recursive: true, force: true }); resolve() })
  })
}

function page(texts) {
  return "import QtQuick\nWindow { width: 600; height: " + (texts.length * 80 + 40) + "; visible: true\n" +
    texts.map((t, i) => "  Text { y: " + i * 80 + "; width: 580; wrapMode: Text.Wrap; textFormat: Text.MarkdownText; text: " + JSON.stringify(t) + " }\n").join("") +
    "  Timer { interval: 2500; running: true; onTriggered: Qt.quit() }\n}\n"
}

async function main() {
  const seen = []
  const server = http.createServer((req, res) => { seen.push(req.url); res.writeHead(404); res.end() })
  await new Promise(r => server.listen(0, "127.0.0.1", r))
  const port = server.address().port
  const cases = shapes(port)
  let failed = false
  try {
    // Control: Qt does load these when they reach it as they are.
    await run(page([cases.nested, cases.reference]))
    for (const name of ["nested", "reference"]) {
      if (!seen.includes("/" + name + ".png")) { console.error("qt-images: the control /" + name + ".png was not requested; the test cannot see requests"); failed = true }
    }
    seen.length = 0
    // Through displayMarkdown, with and without a link color: nothing.
    const texts = []
    for (const name in cases) for (const color of ["", "#ffcc00"]) texts.push(M.displayMarkdown(cases[name], color))
    await run(page(texts))
    if (seen.length) { console.error("qt-images: Qt loaded images from issue text: " + seen.join(", ")); failed = true }
  } finally { server.close() }
  if (failed) process.exit(1)
  console.log("qt-images: ok (" + Object.keys(cases).length + " shapes, none loaded)")
}
main().catch(e => { console.error(e); process.exit(1) })
