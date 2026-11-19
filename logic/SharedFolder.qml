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
  // Read and written through the folder's checked, link-free path.
  readonly property string path: shared.folder ? privateFiles.realPath(Shared.FILE_NAME) : ""
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

  // Read and written without following links (see SharedFile).
  SharedFile {
    id: sharedFile
    // Only after config.json is read, so the local copy never overwrites what came from the folder.
    path: root.configLoaded ? shared.path : ""
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
    onLoadFailed: function(why) {
      if (!shared.path) return
      if (why !== "missing") {
        shared.writable = false
        shared.error = (why === "link"
          ? "The shared settings " + shared.folder.replace(root.home, "~") + "/" + Shared.FILE_NAME + " are a link. The board doesn't follow links in the shared folder (whoever else syncs it could point one at a file of yours), so they are neither read nor written until it is the file itself."
          : "The shared settings in " + shared.folder.replace(root.home, "~") + " cannot be read.") + " Until then, changes stay on this computer."
        return
      }
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
      shared.error = "The shared settings are not at " + shared.path.replace(root.home, "~") + " yet (not synced?). Checking again every few seconds. Until then, changes stay on this computer."
    }
  }

  // Changes from another computer (and a file that appears later) are
  // picked up by reading again now and then.
  Timer {
    interval: shared.error !== "" ? 5000 : 15000
    repeat: true
    running: !!sharedFile.path
    onTriggered: sharedFile.reload()
  }

  // ---- conflict copies ----
  // When two computers changed the time file or linear-board.json before
  // syncing (one was offline), Syncthing keeps one version and puts the
  // other next to it as a .sync-conflict copy. Its time entries, running
  // timer and recurring rules / project codes / hidden statuses are added to
  // the file in use next to it (nothing is removed). Until they are on disk,
  // the copy is the only saved place of them, so it is never cleared away
  // right after a merge: each pass reads the file in use from disk, and only
  // a copy that adds nothing to it goes to the trash. Otherwise what is on
  // disk plus the copy is saved and the copy stays for the next pass (every
  // 30 s), which also retries a failed save; merging twice adds nothing twice.
  // What was read is acted on only while nothing changed since: the same
  // folder (a copy is merged only into the file next to it) and no save of
  // that file in between (it would hold changes the read lacks). Otherwise
  // the copy waits for the next pass. A copy that cannot be read is left
  // alone and reported once.
  property var conflictQueue: []
  property var conflictReported: ({})
  property var conflictNotified: ({})
  property string conflictDir: ""      // the folder the queue was listed in
  property string conflictText: ""
  property int conflictSeq: -1         // the file in use's save count when it was read
  Timer {
    interval: 30000
    repeat: true
    triggeredOnStart: true
    running: !!shared.folder && shared.writable && timeTracker.timeWritable
    onTriggered: shared.findConflicts()
  }
  function findConflicts() {
    if (conflictFind.running || shared.conflictQueue.length || !privateFiles.sharedReal) return
    var timeName = timeTracker.timePath.substring(timeTracker.timePath.lastIndexOf("/") + 1)
    shared.conflictDir = privateFiles.sharedReal
    conflictFind.command = ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in $2 $3; do case "$f" in *"\n"*) continue;; esac; [ -f "$f" ] && [ ! -L "$f" ] && printf "%s\\n" "$PWD/$f"; done; exit 0',
      "sh", privateFiles.sharedReal, Shared.conflictGlob(timeName), Shared.conflictGlob(Shared.FILE_NAME)]
    conflictFind.running = true
  }
  Process {
    id: conflictFind
    stdout: StdioCollector { id: conflictList }
    onExited: {
      if (privateFiles.sharedReal !== shared.conflictDir) return   // another folder by now
      var found = conflictList.text.split("\n").filter(function(f) { return f && !shared.conflictReported[f] })
      if (!found.length) return
      shared.conflictQueue = found
      conflictFile.path = found[0]
    }
  }
  function isSettingsCopy(file) {
    return file.substring(file.lastIndexOf("/") + 1).indexOf(Shared.FILE_NAME.replace(/\.json$/, "") + ".sync-conflict-") === 0
  }
  // The file in use a copy is merged into, { path, view }, or null when it
  // is not next to the copy any more (the folder was changed).
  function conflictTarget(file) {
    var settings = shared.isSettingsCopy(file)
    var p = settings ? shared.path : timeTracker.timeFilePath
    var dir = file.substring(0, file.lastIndexOf("/"))
    if (!p || !shared.conflictDir || dir !== shared.conflictDir || privateFiles.sharedReal !== shared.conflictDir || p.substring(0, p.lastIndexOf("/")) !== dir) return null
    return { path: p, view: settings ? sharedFile : timeTracker.timeFile }
  }
  // Links are not listed above, and not read here either if one appears in between.
  SharedFile {
    id: conflictFile
    onLoaded: {
      // Then the file in use, fresh from disk: what the board holds may not be saved.
      var target = shared.conflictTarget(conflictFile.path)
      if (!target || target.view.writing) { shared.nextConflict("keep"); return }
      shared.conflictText = text()
      shared.conflictSeq = target.view.seq
      conflictDest.path = target.path
    }
    onLoadFailed: function(why) { shared.nextConflict("report", why === "link" ? "it is a link" : "") }
  }
  SharedFile {
    id: conflictDest
    onLoaded: shared.mergeConflict(conflictFile.path, shared.conflictText, text())
    // The file in use cannot be read: its own error is shown, the copy waits.
    onLoadFailed: shared.nextConflict("keep")
  }
  function mergeConflict(file, text, diskText) {
    // Still the same folder, and no save since the read: else the next pass.
    var target = shared.conflictTarget(file)
    if (!target || target.path !== conflictDest.path || target.view.seq !== shared.conflictSeq || target.view.writing) { shared.nextConflict("keep"); return }
    var isSettings = shared.isSettingsCopy(file)
    var copy = isSettings ? Shared.parse(text) : Time.parse(text)
    if (copy.error) { shared.nextConflict("report", copy.error); return }
    var disk = isSettings ? Shared.parse(diskText) : Time.parse(diskText)
    if (disk.error) { shared.nextConflict("keep"); return }
    if (isSettings ? Shared.covers(disk.data, copy.data) : Time.covers(disk.data, copy.data)) {
      console.warn("linear-board: the sync conflict copy " + file + " adds nothing to the file in use; moved to the trash")
      shared.nextConflict("trash")
      return
    }
    // Not all on disk yet: what is on disk (it may hold more than the board
    // read so far) plus the copy is saved.
    var said = ""
    if (isSettings) {
      var base = Shared.apply(root.config, disk.data)
      if (Shared.differs(root.config, base)) root.applySharedConfig(base)
      var s = Shared.mergeSettings(base, copy.data)
      if (Shared.differs(root.config, s.config)) root.setConfig(s.config)
      else shared.save()
      if (s.rules || s.codes) said = [s.rules ? s.rules + " recurring issue" + (s.rules === 1 ? "" : "s") : "", s.codes ? s.codes + " project code" + (s.codes === 1 ? "" : "s") : ""].filter(function(x) { return x }).join(", ")
    } else {
      var m = Time.mergeConflict(disk.data, copy.data)
      if (!timeTracker.saveTime(m.data)) { shared.nextConflict("keep"); return }
      said = [m.added ? m.added + " time " + (m.added === 1 ? "entry" : "entries") : "", m.timer ? "the running timer" : ""].filter(function(x) { return x }).join(", ")
    }
    if (said && !shared.conflictNotified[file]) {
      var n = {}
      for (var k in shared.conflictNotified) n[k] = shared.conflictNotified[k]
      n[file] = true
      shared.conflictNotified = n
      notices.notify("Merged from a sync conflict copy: " + said)
    }
    console.warn("linear-board: merged the sync conflict copy " + file + (said ? " (" + said + ")" : "") + "; it stays until a later read of the file in use has all of it")
    shared.nextConflict("keep")
  }
  // action: "trash" (all of it is on disk), "keep" (look again on the next
  // pass) or "report" (cannot be merged: left alone, said once).
  function nextConflict(action, error) {
    var file = shared.conflictQueue[0]
    if (action === "trash" && file) Quickshell.execDetached(["sh", "-c", 'gio trash -- "$1" 2>/dev/null || rm -f -- "$1"', "sh", file])
    else if (action === "report" && file) {
      var rep = {}
      for (var k in shared.conflictReported) rep[k] = shared.conflictReported[k]
      rep[file] = true
      shared.conflictReported = rep
      notices.notify("A sync conflict copy could not be merged" + (error ? " (" + error + ")" : "") + ": " + file.replace(root.home, "~"), true)
    }
    shared.conflictText = ""
    shared.conflictSeq = -1
    conflictDest.path = ""
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
