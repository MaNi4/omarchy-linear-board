import Quickshell
import Quickshell.Io
import QtQuick

// Files with private data (the API key, issues, inbox, time entries) are
// readable only by the user (0600). The first write of a file in a session
// goes through sh with umask 077 to a fresh inode, so a file an older
// version left readable is replaced, not just chmod-ed. After that the
// FileView's own atomic saves keep 0600: Qt gives the new file the mode of
// the one it replaces.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `privateFiles`. Everything that writes private data calls
// privateFiles.write(fileView, text) instead of fileView.setText(text).
Item {
  id: privateFiles
  visible: false

  property var ready: ({})   // path → true once this session wrote it 0600
  property var queue: []     // [{ view, path, text }]

  // view: a FileView with atomicWrites; text: its whole new content.
  function write(view, text) {
    var path = String(view.path || "")
    if (!path) return
    if (privateFiles.ready[path] && !privateFiles.queue.length && !privateFiles.inShared(path)) { view.setText(text); return }
    if (privateFiles.ready[path] && !privateFiles.queue.length && privateFiles.sharedState === "ok") { view.setText(text); return }
    privateFiles.queue = privateFiles.queue.concat([{ view: view, path: path, text: String(text) }])
    privateFiles.next()
  }

  function next() {
    while (privateFiles.queue.length && !firstWrite.running) {
      var job = privateFiles.queue[0]
      if (privateFiles.inShared(job.path) && privateFiles.sharedState !== "ok") {
        if (privateFiles.sharedState === "checking") return   // folderCheck calls next() when done
        privateFiles.queue = privateFiles.queue.slice(1)       // missing or unsafe: not written
        continue
      }
      if (!privateFiles.ready[job.path]) {
        firstWrite.job = job
        firstWrite.command = ["sh", "-c", firstWrite.script, "sh", job.path]
        firstWrite.running = true
        return
      }
      privateFiles.queue = privateFiles.queue.slice(1)
      if (String(job.view.path) === job.path) job.view.setText(job.text)
    }
  }

  // The text comes on stdin, never in the arguments. A symlink is followed,
  // as Qt's own saves do, so a linked file stays linked.
  Process {
    id: firstWrite
    property var job: null
    readonly property string script: 'umask 077; f=$(readlink -f -- "$1") || f=$1; t="$f.tmp-$$"; rm -f -- "$t"; ' +
      '(set -C; cat > "$t") && mv -f -- "$t" "$f" || { rm -f -- "$t"; exit 1; }'
    stdinEnabled: true
    onStarted: { firstWrite.write(firstWrite.job.text); stdinEnabled = false }
    onExited: function(code) {
      stdinEnabled = true
      var job = firstWrite.job
      firstWrite.job = null
      privateFiles.queue = privateFiles.queue.slice(1)
      if (code === 0) {
        var r = {}
        for (var k in privateFiles.ready) r[k] = true
        r[job.path] = true
        privateFiles.ready = r
      } else notices.notify("Could not save " + job.path.replace(root.home, "~"), true)
      Qt.callLater(privateFiles.next)
    }
  }

  // Existing files that are readable by others are copied to a fresh 0600
  // inode. The board's own folders are done at start (Board.qml); the files
  // in a shared folder when it is known.
  function tighten(paths) {
    var list = (paths || []).filter(function(p) { return !!p })
    if (!list.length) return
    Quickshell.execDetached(["sh", "-c", privateFiles.tightenScript, "sh"].concat(list))
  }
  readonly property string tightenScript: 'umask 077; for f; do f=$(readlink -f -- "$f") || continue; [ -f "$f" ] || continue; ' +
    '[ "$(stat -c %a -- "$f")" = 600 ] && continue; t="$f.tmp-$$"; rm -f -- "$t"; ' +
    '(set -C; cat -- "$f" > "$t") && mv -f -- "$t" "$f" || rm -f -- "$t"; done'

  readonly property string sharedFiles: timeTracker.timeLocation && privateFiles.sharedState === "ok" ? timeTracker.timePath + "\n" + shared.path : ""
  onSharedFilesChanged: if (privateFiles.sharedFiles) privateFiles.tighten(privateFiles.sharedFiles.split("\n"))

  // ---- the shared folder ----
  // Its files are read and written only when no other user can change the
  // folder: otherwise another account on this computer could swap a file
  // for a link to one of yours (the board would overwrite that file) or
  // plant settings such as recurring issues. The folder must belong to you
  // (or root) and not be writable by others; every folder above it too,
  // except shared ones with the sticky bit such as /tmp.
  // sharedState: "" (no shared folder), checking, ok, missing, unsafe.
  readonly property string sharedDir: timeTracker.timeLocation ? timeTracker.timePath.substring(0, timeTracker.timePath.lastIndexOf("/")) : ""
  property string sharedState: ""
  property string sharedProblem: ""     // the folder others can change
  readonly property bool sharedUsable: !privateFiles.sharedDir || privateFiles.sharedState === "ok"
  function inShared(path) { return !!privateFiles.sharedDir && String(path).indexOf(privateFiles.sharedDir + "/") === 0 }

  onSharedDirChanged: privateFiles.checkShared()
  function checkShared() {
    if (!privateFiles.sharedDir) { privateFiles.sharedState = ""; return }
    if (folderCheck.running) return
    if (privateFiles.sharedState !== "ok") privateFiles.sharedState = "checking"
    folderCheck.command = ["sh", "-c", folderCheck.script, "sh", privateFiles.sharedDir]
    folderCheck.running = true
  }
  Process {
    id: folderCheck
    readonly property string script: 'd=$(readlink -f -- "$1") && [ -d "$d" ] || { echo missing; exit 0; }; u=$(id -u); p=$d; leaf=1; ' +
      'while :; do s=$(stat -c "%u %a" -- "$p") || { echo "unsafe $p"; exit 0; }; o=${s% *}; m=$((0${s#* })); ' +
      'if [ "$o" != "$u" ] && [ "$o" != 0 ]; then echo "unsafe $p"; exit 0; fi; ' +
      'if [ $((m & 18)) -ne 0 ] && { [ $leaf = 1 ] || [ $((m & 512)) -eq 0 ]; }; then echo "unsafe $p"; exit 0; fi; ' +
      '[ "$p" = / ] && break; p=$(dirname -- "$p"); leaf=0; done; echo ok'
    stdout: StdioCollector { id: folderOut }
    onExited: {
      var out = folderOut.text.trim()
      var was = privateFiles.sharedState
      if (out === "ok") privateFiles.sharedState = "ok"
      else if (out.indexOf("unsafe ") === 0) {
        privateFiles.sharedState = "unsafe"
        privateFiles.sharedProblem = out.slice(7)
        timeTracker.timeWritable = false
        timeTracker.timeError = "Other users on this computer can change " + privateFiles.sharedProblem.replace(root.home, "~") +
          ", so the board doesn't read or write its files there. Make it yours only, for example: chmod go-w " + privateFiles.sharedProblem.replace(root.home, "~")
        if (was !== "unsafe") notices.notify(timeTracker.timeError, true)
      } else {
        privateFiles.sharedState = "missing"
        timeTracker.timeWritable = false
        timeTracker.timeError = "The shared folder " + privateFiles.sharedDir.replace(root.home, "~") + " isn't there yet (not synced or not mounted?). Looking again every few seconds; until then nothing is written."
      }
      Qt.callLater(privateFiles.next)
    }
  }
  // Checked again now and then: a folder that shows up later, or whose
  // permissions changed.
  Timer {
    interval: privateFiles.sharedState === "ok" ? 60000 : 5000
    repeat: true
    running: !!privateFiles.sharedDir
    onTriggered: privateFiles.checkShared()
  }
}
