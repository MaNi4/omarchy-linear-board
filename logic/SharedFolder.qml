import Quickshell
import Quickshell.Io
import QtQuick
import "../Shared.js" as Shared
import "../Time.js" as Time

// The shared folder for everything the board keeps outside Linear. The time
// file (TimeTracker) and linear-board.json (recurring issues, project codes,
// board layout; see Shared.js) sit side by side in the folder chosen in
// Settings → Data, e.g. a Syncthing folder. config.json keeps a copy, so the
// board works the same when the folder is gone.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `shared`; it uses the board's state through the id `root`.
Item {
  id: shared
  visible: false

  readonly property string folder: {
    if (!timeTracker.timeLocation) return ""
    var p = timeTracker.timePath
    return p.substring(0, p.lastIndexOf("/"))
  }
  readonly property string path: shared.folder ? shared.folder + "/" + Shared.FILE_NAME : ""
  property bool writable: false
  property string error: ""
  // Set while a new folder is being taken into use: when linear-board.json
  // is not there yet, it is made from this computer's settings.
  property bool createIfMissing: false

  // Another folder (or none): nothing is written until its file is read,
  // or this computer's settings could land on top of what is there.
  onPathChanged: { shared.writable = false; shared.error = "" }

  function save() {
    if (!shared.path || !shared.writable) return
    privateFiles.write(sharedFile, Shared.serialize(root.config))
  }

  FileView {
    id: sharedFile
    // Only after config.json is read, so the local copy never overwrites what came from the folder.
    path: root.configLoaded ? shared.path : ""
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: reload()
    onSaveFailed: function(error) { notices.notify("Could not save " + shared.path.replace(root.home, "~") + ": " + error, true) }
    onLoaded: {
      shared.createIfMissing = false
      var r = Shared.parse(text())
      if (r.error) {
        shared.writable = false
        shared.error = r.error + " Nothing is written to it until it is fixed: " + shared.path.replace(root.home, "~")
        return
      }
      shared.writable = true
      shared.error = ""
      var next = Shared.apply(root.config, r.data)
      if (Shared.differs(root.config, next)) root.applySharedConfig(next)
    }
    onLoadFailed: {
      if (!shared.path) return
      // A new folder with no settings yet, or one this computer already
      // keeps its time in (set before the settings were shared): make it.
      if (shared.createIfMissing || (timeTracker.timeWritable && timeTracker.timeError === "")) {
        shared.createIfMissing = false
        shared.writable = true
        shared.error = ""
        shared.save()
        return
      }
      // Not there (sync not finished, disk not mounted): wait, never start
      // an empty file in its place.
      shared.writable = false
      shared.error = "The shared settings are not at " + shared.path.replace(root.home, "~") + " yet (not synced?). Looking again every few seconds; until then changes stay on this computer."
    }
  }

  // Watching misses a file that appears later, so read it again now and then.
  Timer {
    interval: shared.error !== "" ? 5000 : 15000
    repeat: true
    running: !!sharedFile.path
    onTriggered: sharedFile.reload()
  }

  // ---- conflict copies ----
  // When two computers changed the time file or linear-board.json before
  // syncing (one was offline), Syncthing keeps one version and puts the
  // other next to it as a .sync-conflict copy. Their time entries and
  // recurring rules / project codes are added to the file in use (nothing
  // is removed), then the copy is deleted. A copy that cannot be read is
  // left alone and reported once.
  property var conflictQueue: []
  property var conflictReported: ({})
  Timer {
    interval: 30000
    repeat: true
    triggeredOnStart: true
    running: !!shared.folder && shared.writable && timeTracker.timeWritable
    onTriggered: shared.findConflicts()
  }
  function findConflicts() {
    if (conflictFind.running || shared.conflictQueue.length) return
    var timeName = timeTracker.timePath.substring(timeTracker.timePath.lastIndexOf("/") + 1)
    conflictFind.command = ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in $2 $3; do [ -f "$f" ] && printf "%s\\n" "$PWD/$f"; done; exit 0',
      "sh", shared.folder, Shared.conflictGlob(timeName), Shared.conflictGlob(Shared.FILE_NAME)]
    conflictFind.running = true
  }
  Process {
    id: conflictFind
    stdout: StdioCollector { id: conflictList }
    onExited: {
      var found = conflictList.text.split("\n").filter(function(f) { return f && !shared.conflictReported[f] })
      if (!found.length) return
      shared.conflictQueue = found
      conflictFile.path = found[0]
    }
  }
  FileView {
    id: conflictFile
    printErrors: false
    onLoaded: shared.mergeConflict(conflictFile.path, text())
    onLoadFailed: shared.nextConflict(false)
  }
  function mergeConflict(file, text) {
    var isSettings = file.substring(file.lastIndexOf("/") + 1).indexOf(Shared.FILE_NAME.replace(/\.json$/, "") + ".sync-conflict-") === 0
    var said = ""
    if (isSettings) {
      var r = Shared.parse(text)
      if (r.error) { shared.nextConflict(false, r.error); return }
      var s = Shared.mergeSettings(root.config, r.data)
      if (Shared.differs(root.config, s.config)) root.setConfig(s.config)
      if (s.rules || s.codes) said = [s.rules ? s.rules + " recurring issue" + (s.rules === 1 ? "" : "s") : "", s.codes ? s.codes + " project code" + (s.codes === 1 ? "" : "s") : ""].filter(function(x) { return x }).join(", ")
    } else {
      var t = Time.parse(text)
      if (t.error) { shared.nextConflict(false, t.error); return }
      var m = Time.merge(timeTracker.copyData(), t.data)
      if (m.added) {
        if (!timeTracker.saveTime(m.data)) { shared.nextConflict(false, "the time file cannot be written"); return }
        said = m.added + " time " + (m.added === 1 ? "entry" : "entries")
      }
    }
    if (said) notices.notify("Merged from a sync conflict copy: " + said)
    console.warn("linear-board: merged and removed the sync conflict copy " + file + (said ? " (" + said + ")" : " (nothing new)"))
    shared.nextConflict(true)
  }
  function nextConflict(merged, error) {
    var file = shared.conflictQueue[0]
    if (merged) Quickshell.execDetached(["rm", "-f", "--", file])
    else if (file) {
      var rep = {}
      for (var k in shared.conflictReported) rep[k] = shared.conflictReported[k]
      rep[file] = true
      shared.conflictReported = rep
      notices.notify("A sync conflict copy could not be merged" + (error ? " (" + error + ")" : "") + ": " + file.replace(root.home, "~"), true)
    }
    shared.conflictQueue = shared.conflictQueue.slice(1)
    if (shared.conflictQueue.length) conflictFile.path = shared.conflictQueue[0]
    else conflictFile.path = ""
  }

  // ---- export and import of everything kept outside Linear ----
  function exportAll() {
    var name = "linear-board-export-" + Time.isoDate(new Date()) + ".json"
    timeTracker.exportTo(timeTracker.downloadsDir() + "/" + name, Shared.exportText(root.config, timeTracker.timeData, new Date()), "Export")
  }

  FileView {
    id: importFile
    printErrors: false
    onLoaded: shared.importText(text())
    onLoadFailed: notices.notify("Import: cannot read " + path.replace(root.home, "~"), true)
  }

  function importFrom(path) {
    var p = String(path || "").trim().replace(/^~(?=\/|$)/, root.home)
    if (!p) return
    if (importFile.path === p) importFile.reload()
    else importFile.path = p
  }

  function importText(text) {
    var r = Shared.parseExport(text)
    if (r.error) { notices.notify("Import: " + r.error, true); return }
    var said = []
    var s = Shared.mergeSettings(root.config, r.settings)
    if (Shared.differs(root.config, s.config)) root.setConfig(s.config)
    if (s.rules) said.push(s.rules + (s.rules === 1 ? " recurring issue" : " recurring issues"))
    if (s.codes) said.push(s.codes + (s.codes === 1 ? " project code" : " project codes"))
    if (r.time) {
      var t = timeTracker.importData(r.time)
      if (t < 0) return
      if (t) said.push(t + (t === 1 ? " time entry" : " time entries"))
    }
    notices.notify(said.length ? "Imported " + said.join(", ") : "Nothing new to import: all of it is already here")
  }
}
