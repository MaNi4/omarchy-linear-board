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
    if (privateFiles.ready[path] && !privateFiles.queue.length) { view.setText(text); return }
    privateFiles.queue = privateFiles.queue.concat([{ view: view, path: path, text: String(text) }])
    privateFiles.next()
  }

  function next() {
    while (privateFiles.queue.length && !firstWrite.running) {
      var job = privateFiles.queue[0]
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

  readonly property string sharedFiles: timeTracker.timeLocation ? timeTracker.timePath + "\n" + shared.path : ""
  onSharedFilesChanged: if (privateFiles.sharedFiles) privateFiles.tighten(privateFiles.sharedFiles.split("\n"))
}
