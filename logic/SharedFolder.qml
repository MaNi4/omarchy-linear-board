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
    sharedFile.setText(Shared.serialize(root.config))
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
