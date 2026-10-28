import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Linear.js" as Linear
import "../Dates.js" as Dates
import "../Time.js" as Time
import "../Shared.js" as Shared

// Time tracking: the time file, the timer, away detection, manual entries and CSV export.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `timeTracker`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: timeTracker

  // The time report (ui/TimeReport.qml): which period, grouped how.
  property string reportKind: "week"     // day | week | month
  property int reportOffset: 0
  property string reportBy: "issue"      // issue | project
  property var reportIssue: null         // issue picked for a manual entry in the report
  property string reportEditId: ""       // entry being edited in the report
  readonly property var reportPeriod: Time.period(timeTracker.reportKind, timeTracker.reportOffset, new Date(timeTracker.nowMs))
  readonly property var reportEntries: Time.entriesIn(timeTracker.timeData.entries, timeTracker.reportPeriod)
  readonly property var reportGroups: Time.summarize(timeTracker.reportEntries, timeTracker.reportBy)
  visible: false
  property alias timeLocationFile: timeLocationFile

  // ---- time tracking -------------------------------------------------------------------
  // Entries are kept in a JSON file: by default in the data folder, or in a
  // folder of your choice (e.g. a synced one, to share it between computers).
  // The chosen location is a single line in ~/.config/omarchy-linear-board/time-location;
  // the shared settings (SharedFolder.qml) use the same folder.
  property string timeLocation: ""
  property bool timeLocationLoaded: false
  property var timeData: Time.emptyData()
  property bool timeWritable: false
  property string timeError: ""
  property string device: ""
  property double nowMs: Date.now()
  readonly property string timePath: {
    var loc = timeTracker.timeLocation.replace(/^~(?=\/|$)/, root.home)
    if (!loc) return root.dataDir + "/time.json"
    return /\.json$/i.test(loc) ? loc : loc.replace(/\/+$/, "") + "/linear-time.json"
  }
  readonly property var running: timeTracker.timeData.running
  readonly property int runningSeconds: timeTracker.running ? Math.max(0, Math.floor((timeTracker.nowMs - new Date(timeTracker.running.startedAt).getTime()) / 1000)) : 0
  readonly property var timeTotals: Time.totalsByIssue(timeTracker.timeData.entries)

  Timer {
    interval: 1000
    repeat: true
    running: !!timeTracker.running && panel.visible
    onTriggered: timeTracker.nowMs = Date.now()
  }

  FileView {
    path: "/etc/hostname"
    printErrors: false
    onLoaded: timeTracker.device = text().trim()
  }

  FileView {
    id: timeLocationFile
    printErrors: false
    atomicWrites: true
    onLoaded: { timeTracker.timeLocation = text().trim(); timeTracker.timeLocationLoaded = true }
    onLoadFailed: timeTracker.timeLocationLoaded = true
  }

  FileView {
    id: timeFile
    path: timeTracker.timeLocationLoaded ? timeTracker.timePath : ""
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: reload()
    onSaveFailed: function(error) {
      console.warn("linear-board: time file save failed: " + error)
      notices.notify("Could not save the time file: " + error, true)
    }
    onLoaded: {
      var r = Time.parse(text())
      if (r.error) {
        timeTracker.timeWritable = false
        timeTracker.timeError = r.error + " Nothing is written until it is fixed: " + timeTracker.timePath.replace(root.home, "~")
        return
      }
      timeTracker.timeData = r.data
      timeTracker.timeWritable = true
      timeTracker.timeError = ""
      timeTracker.nowMs = Date.now()
      inboxCtl.writeInboxState()
    }
    onLoadFailed: {
      if (!timeTracker.timeLocation) {
        // First use: the default file is made on the first write.
        timeTracker.timeData = Time.emptyData()
        timeTracker.timeWritable = true
        timeTracker.timeError = ""
      } else {
        // A chosen location that is not there (disk not mounted, sync not
        // finished): never start an empty file in its place.
        timeTracker.timeWritable = false
        timeTracker.timeError = "The time file is not at " + timeTracker.timePath.replace(root.home, "~") + " (not synced yet?). Looking again every few seconds."
      }
    }
  }

  // Watching misses a file that appears later (first sync from another
  // computer, a disk mounted after start), so read it again every few seconds.
  Timer {
    interval: timeTracker.timeError !== "" ? 5000 : 10000
    repeat: true
    running: timeTracker.timeLocationLoaded
    onTriggered: timeFile.reload()
  }

  function saveTime(data) {
    if (!timeTracker.timeWritable) { notices.notify(timeTracker.timeError || "The time file cannot be written right now.", true); return false }
    timeTracker.timeData = data
    timeFile.setText(Time.serialize(data))
    inboxCtl.writeInboxState()
    return true
  }

  function copyData() {
    return { version: 1, running: timeTracker.timeData.running, entries: timeTracker.timeData.entries.slice() }
  }

  function issueTimeInfo(issue) {
    var p = root.projectById(issue.projectId)
    var sameTeam = root.team && (!issue.teamId || issue.teamId === root.team.id)
    return Time.issueInfo(issue, p ? p.name : (issue.projectName || ""), sameTeam && root.team ? root.team.name : (issue.teamName || ""))
  }

  function isRunningOn(issueId) { return !!(timeTracker.running && timeTracker.running.issueId === issueId) }

  function startTimer(issue) {
    if (!issue) return
    if (timeTracker.isRunningOn(issue.id)) return
    if (timeTracker.running) timeTracker.stopTimer()
    var d = timeTracker.copyData()
    var info = timeTracker.issueTimeInfo(issue)
    info.startedAt = new Date().toISOString()
    info.device = timeTracker.device
    d.running = info
    timeTracker.nowMs = Date.now()
    if (timeTracker.saveTime(d)) notices.notify("Timer started on " + issue.identifier)
  }

  function stopTimer() {
    var r = timeTracker.running
    if (!r) return
    var d = timeTracker.copyData()
    d.running = null
    var e = Time.entryFromRunning(r, new Date(), Time.newId(new Date()), timeTracker.device)
    if (e.seconds < Time.MIN_SECONDS) {
      if (!timeTracker.saveTime(d)) return
      var msg = "Timer on " + r.identifier + " ran only " + e.seconds + " s, nothing logged (minimum " + Time.MIN_SECONDS + " s)"
      notices.notify(msg, true)
      timeTracker.timerDesktopNotice("Nothing logged", msg)
      return
    }
    d.entries.push(e)
    if (!timeTracker.saveTime(d)) return
    var logged = "Logged " + Time.formatDuration(e.seconds) + " on " + r.identifier
    notices.notify(logged)
    timeTracker.timerDesktopNotice(logged, r.title + (root.config.timeComments ? "\nAlso posted to the issue as a comment." : ""))
    timeTracker.postTimeComment(e)
  }

  // Stopped from the bar with the board closed: the toast would go unseen,
  // so say it with a desktop notification.
  function timerDesktopNotice(title, body) {
    if (root.opened && panel.visible) return
    notices.desktopNote(title, body, null, 1)
  }

  // ---- away detection: idle for a while, or the computer slept ----
  readonly property int awayMinutes: 5
  property double idleSince: 0
  property double lastTick: 0

  IdleMonitor {
    id: idleWatch
    enabled: !!timeTracker.running
    timeout: timeTracker.awayMinutes * 60
    respectInhibitors: true   // a playing video is not "away"
    onIsIdleChanged: {
      if (!timeTracker.running) { timeTracker.idleSince = 0; return }
      if (isIdle) timeTracker.idleSince = Date.now() - timeout * 1000
      else if (timeTracker.idleSince) {
        var from = timeTracker.idleSince
        timeTracker.idleSince = 0
        timeTracker.askAboutAway(from, Date.now())
      }
    }
  }

  // A gap between ticks means the computer was suspended.
  Timer {
    interval: 10000
    repeat: true
    running: !!timeTracker.running
    onRunningChanged: timeTracker.lastTick = running ? Date.now() : 0
    onTriggered: {
      var now = Date.now()
      if (timeTracker.lastTick && now - timeTracker.lastTick > 120000 && !timeTracker.idleSince) timeTracker.askAboutAway(timeTracker.lastTick, now)
      timeTracker.lastTick = now
    }
  }

  // Ask (desktop notification) whether to drop the time away from the timer.
  property double lastAwayAsked: 0
  function askAboutAway(from, to) {
    var r = timeTracker.running
    if (!r) return
    from = Math.max(from, new Date(r.startedAt).getTime())
    var mins = Math.round((to - from) / 60000)
    if (mins < timeTracker.awayMinutes || to - timeTracker.lastAwayAsked < 60000) return
    timeTracker.lastAwayAsked = to
    // A click removes the time; closing the notification keeps it.
    notices.desktopNote("Timer on " + r.identifier + " kept running",
      "You were away for " + mins + " min. Click to remove that time from the timer; close this to keep it.",
      { timer: "away", from: new Date(from).toISOString(), to: new Date(to).toISOString() }, 2)
    notices.notify("Away " + mins + " min while the timer ran: click the notification to remove it")
  }

  // Take [from, to] out of the running timer: log the part before, go on from `to`.
  function removeAway(fromIso, toIso) {
    var r = timeTracker.running
    if (!r) return
    var from = new Date(fromIso), to = new Date(toIso)
    if (isNaN(from.getTime()) || isNaN(to.getTime())) return
    var d = timeTracker.copyData()
    var logged = null
    if (new Date(r.startedAt).getTime() < from.getTime()) {
      var e = Time.entryFromRunning(r, from, Time.newId(new Date()), timeTracker.device)
      if (e.seconds >= Time.MIN_SECONDS) { d.entries.push(e); logged = e }
    }
    var next = {}
    for (var k in r) next[k] = r[k]
    next.startedAt = to.toISOString()
    d.running = next
    if (!timeTracker.saveTime(d)) return
    timeTracker.nowMs = Date.now()
    notices.notify("Removed " + Math.round((to - from) / 60000) + " min away" + (logged ? "; logged " + Time.formatDuration(logged.seconds) + " before it" : ""))
    if (logged) timeTracker.postTimeComment(logged)
  }

  function toggleTimer(issue) {
    if (!issue) return
    if (timeTracker.isRunningOn(issue.id)) timeTracker.stopTimer()
    else timeTracker.startTimer(issue)
  }

  // Logged time also goes to the issue as a comment (Linear has no time
  // tracking); the comment id is kept so editing or deleting follows it.
  function postTimeComment(entry) {
    if (!root.config.timeComments) return
    sync.send("Time comment", Linear.M_COMMENT_CREATE, { input: { issueId: entry.issueId, body: Time.commentBody(entry) } }, function(d) {
      var cid = d.commentCreate.comment.id
      var data = timeTracker.copyData()
      data.entries = data.entries.map(function(x) {
        if (x.id !== entry.id) return x
        var y = {}
        for (var k in x) y[k] = x[k]
        y.commentId = cid
        return y
      })
      timeTracker.saveTime(data)
      if (ed.issueId === entry.issueId) ed.comments = ed.comments.concat([Linear.toComment(d.commentCreate.comment)])
    }, function(msg) { notices.notify("Time saved, but the Linear comment failed: " + msg, true) })
  }

  function addManualTime(issue, durationText, dateText, note) {
    if (!issue) { notices.notify("Pick an issue first.", true); return false }
    var seconds = Time.parseDuration(durationText)
    if (!seconds) { notices.notify("Duration should look like 45m, 1h 30m, 1.5h or 1:30", true); return false }
    var start = Time.manualStart(Dates.parseDate(dateText) || "")
    if (!start) { notices.notify("Date should look like 2026-10-31 or 31.10.2026", true); return false }
    var e = timeTracker.issueTimeInfo(issue)
    e.id = Time.newId(new Date())
    e.start = start.toISOString()
    e.seconds = seconds
    e.note = String(note || "").trim()
    e.commentId = ""
    e.device = timeTracker.device
    e.manual = true
    var d = timeTracker.copyData()
    d.entries.push(e)
    if (!timeTracker.saveTime(d)) return false
    notices.notify("Logged " + Time.formatDuration(seconds) + " on " + e.identifier)
    timeTracker.postTimeComment(e)
    return true
  }

  function updateTimeEntry(entry, durationText, note) {
    var seconds = Time.parseDuration(durationText)
    if (!seconds) { notices.notify("Duration should look like 45m, 1h 30m, 1.5h or 1:30", true); return false }
    var updated = null
    var d = timeTracker.copyData()
    d.entries = d.entries.map(function(x) {
      if (x.id !== entry.id) return x
      var y = {}
      for (var k in x) y[k] = x[k]
      y.seconds = seconds
      y.note = String(note || "").trim()
      updated = y
      return y
    })
    if (!updated || !timeTracker.saveTime(d)) return false
    if (updated.commentId)
      root.gql(Linear.M_COMMENT_UPDATE, { id: updated.commentId, input: { body: Time.commentBody(updated) } }, null,
        function(msg) { notices.notify("Time saved, but the Linear comment was not updated: " + msg, true) })
    return true
  }

  function deleteTimeEntry(entry) {
    pickers.ask("Delete " + Time.formatDuration(entry.seconds) + " on " + entry.identifier + (entry.commentId ? " (and its Linear comment)" : "") + "?", "Delete", function() {
      var d = timeTracker.copyData()
      d.entries = d.entries.filter(function(x) { return x.id !== entry.id })
      if (!timeTracker.saveTime(d)) return
      if (entry.commentId) {
        root.gql(Linear.M_COMMENT_DELETE, { id: entry.commentId }, null, function() {})
        ed.comments = ed.comments.filter(function(c) { return c.id !== entry.commentId })
      }
    })
  }

  // ---- time file location, export, import ----
  function setTimeLocation(text) {
    var loc = String(text || "").trim()
    if (loc === timeTracker.timeLocation) return
    var target = !loc ? root.dataDir + "/time.json"
      : (/\.json$/i.test(loc) ? loc.replace(/^~(?=\/|$)/, root.home) : loc.replace(/^~(?=\/|$)/, root.home).replace(/\/+$/, "") + "/linear-time.json")
    locationProc.location = loc
    locationProc.target = target
    locationProc.command = ["sh", "-c", 'umask 077; d="$(dirname "$1")"; mkdir -p "$d" || exit 1; if [ -e "$1" ]; then echo exists; else echo new; fi; if [ -e "$d/$2" ]; then echo exists; else echo new; fi', "sh", target, Shared.FILE_NAME]
    locationProc.running = true
  }

  Process {
    id: locationProc
    property string location: ""
    property string target: ""
    stdout: StdioCollector { id: locationOut }
    onExited: function(code) {
      if (code !== 0) { notices.notify("Cannot use " + target.replace(root.home, "~"), true); return }
      var found = locationOut.text.trim().split(/\s+/)
      var timeExists = found[0] === "exists", settingsExist = found[1] === "exists"
      var keep = timeTracker.timeData
      // With no settings file in the folder yet, this computer's go there.
      shared.createIfMissing = !!location && !settingsExist
      timeLocationFile.setText(location ? location + "\n" : "")
      timeTracker.timeLocation = location
      if (!timeExists) {
        // Nothing there yet: the current entries move along.
        timeTracker.timeWritable = true
        timeTracker.timeError = ""
        timeTracker.saveTime(keep)
      }
      var where = target.replace(root.home, "~").replace(/\/[^\/]*$/, "")
      if (!location) notices.notify("Shared folder off: everything is kept on this computer (" + where + ")")
      else if (timeExists || settingsExist) notices.notify("Using what is already in " + where + " (time" + (timeExists ? "" : ": moved from here") + ", recurring issues and settings" + (settingsExist ? "" : ": copied from here") + ")")
      else notices.notify("Time, recurring issues and settings now kept in " + where)
    }
  }

  FileView {
    id: exportFile
    printErrors: false
    atomicWrites: true
  }

  function exportTo(path, text, what) {
    exportFile.path = path
    exportFile.setText(text)
    notices.notify(what + " saved to " + path.replace(root.home, "~"))
  }

  function downloadsDir() {
    return (Quickshell.env("XDG_DOWNLOAD_DIR") || (root.home + "/Downloads"))
  }

  function exportCsv(period, entries) {
    var name = "linear-time-" + Time.isoDate(period.from) + "_" + Time.isoDate(new Date(period.to.getTime() - 86400000)) + ".csv"
    timeTracker.exportTo(timeTracker.downloadsDir() + "/" + name, Time.toCsv(entries), "CSV")
  }

  // Adds entries of an imported time file that are not here yet. Returns
  // how many, or -1 when it could not be imported.
  function importData(raw) {
    var r = Time.parse(JSON.stringify(raw))
    if (r.error) { notices.notify("Import: " + r.error, true); return -1 }
    var m = Time.merge(timeTracker.copyData(), r.data)
    if (!m.added) return 0
    return timeTracker.saveTime(m.data) ? m.added : -1
  }
}
