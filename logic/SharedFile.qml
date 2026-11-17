import Quickshell
import Quickshell.Io
import QtQuick

// A file read and written through bin/linear-file instead of a FileView:
// the time file, linear-board.json and sync conflict copies. In the shared
// folder, whoever else syncs it can put a link in place of a file (sync
// tools keep links as links); a FileView would follow it, read your file
// elsewhere into what is synced, or overwrite it. Here a link is never
// read, and a save replaces the link instead of writing through it, even
// one that appeared a moment before. followLinks: true for the board's own
// folders, where a link is yours and stays.
// There is no file watching: the users reload() now and then.
//   loaded()            text() has the content
//   loadFailed(why)     "missing", "link", "other" (not a regular file) or "error"
//   saveFailed(error)
// Part of the Linear board (mani4.linear-board); PrivateFiles.write() calls
// setText() on it directly (every save is a new 0600 file already).
Item {
  id: file
  visible: false

  property string path: ""
  property bool followLinks: false
  readonly property bool safeWrites: true
  property string content: ""
  signal loaded()
  signal loadFailed(string why)
  signal saveFailed(string error)

  readonly property string helper: root.pluginDir + "bin/linear-file"
  function text() { return file.content }

  // Every save bumps seq: a read started before it may hold the old content
  // and is thrown away (it would put back what was just changed).
  property int seq: 0
  property bool readAgain: false
  property var pending: null          // { path, text }: the newest text still to write

  onPathChanged: {
    file.content = ""
    if (file.path) file.reload()
  }

  function args(mode, p) { return ["python3", "-I", file.helper, mode].concat(file.followLinks ? ["--follow"] : []).concat([p]) }

  function reload() {
    if (!file.path) return
    if (reader.running || writer.running || file.pending) { file.readAgain = true; return }
    reader.target = file.path
    reader.startSeq = file.seq
    reader.exited = false
    reader.read = false
    reader.command = file.args("read", file.path)
    reader.running = true
  }

  Process {
    id: reader
    property string target: ""
    property int startSeq: 0
    property bool exited: false
    property bool read: false
    property int code: 0
    stdout: StdioCollector {
      id: readOut
      onStreamFinished: { reader.read = true; reader.finish() }
    }
    onExited: function(code) { reader.code = code; reader.exited = true; reader.finish() }
    function finish() {
      if (!reader.exited || !reader.read) return
      reader.exited = false
      var stale = reader.target !== file.path || reader.startSeq !== file.seq
      if (!stale) {
        if (reader.code === 0) { file.content = readOut.text; file.loaded() }
        else file.loadFailed(reader.code === 2 ? "missing" : reader.code === 3 ? "link" : reader.code === 4 ? "other" : "error")
      }
      if (stale || file.readAgain) { file.readAgain = false; Qt.callLater(file.reload) }
    }
  }

  function setText(text) {
    if (!file.path) return
    file.content = String(text)
    file.seq++
    file.pending = { path: file.path, text: String(text) }
    file.nextWrite()
  }

  function nextWrite() {
    if (writer.running || !file.pending) return
    writer.job = file.pending
    file.pending = null
    writer.command = file.args("write", writer.job.path)
    writer.running = true
  }

  Process {
    id: writer
    property var job: null
    stdinEnabled: true
    stderr: StdioCollector { id: writeErr }
    onStarted: { writer.write(writer.job.text); writer.stdinEnabled = false }
    onExited: function(code) {
      writer.stdinEnabled = true
      if (code !== 0) file.saveFailed(writeErr.text.trim() || "could not write " + writer.job.path)
      writer.job = null
      if (file.pending) Qt.callLater(file.nextWrite)
      else if (file.readAgain) { file.readAgain = false; Qt.callLater(file.reload) }
    }
  }
}
