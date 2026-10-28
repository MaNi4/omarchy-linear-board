import Quickshell
import Quickshell.Io
import QtQuick

// Messages to the user: the toast at the bottom of the board (with an
// action such as Undo when it has one) and desktop notifications.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `notices`; ui/Toast.qml shows the toast. Everything else calls
// notices.notify(…) or notices.desktopNote(…).
Item {
  id: notices

  property string toast: ""
  property bool toastError: false
  property string toastIcon: ""
  property var toastAction: null       // clicking the toast runs it (Undo)

  Timer { id: toastTimer; interval: 4500; onTriggered: notices.toast = "" }

  function notify(message, isError, icon) {
    notices.toastAction = null
    notices.toast = message
    notices.toastError = isError === true
    notices.toastIcon = icon || (isError === true ? root.icon.alert : root.icon.info)
    toastTimer.interval = isError === true ? 6000 : 3500
    toastTimer.restart()
  }

  // A toast that runs `action` when clicked, shown a little longer.
  function notifyAction(message, action, icon) {
    notices.notify(message, false, icon)
    notices.toastAction = action
    toastTimer.interval = 6000
    toastTimer.restart()
  }

  // Clicked: hide it and run its action.
  function clickToast() {
    var act = notices.toastAction
    notices.toast = ""
    notices.toastAction = null
    if (act) act()
  }

  // Sent over D-Bus by bin/linear-notify, which reads them on stdin: issue
  // titles and inbox text never show up in process listings. `payload` is
  // what a click summons on the board (Omarchy runs it, also from the
  // notification history), or null for no click action.
  property var noteQueue: []
  function desktopNote(title, body, payload, urgency) {
    var n = { title: String(title || "Linear"), body: String(body || ""), urgency: urgency === undefined ? 1 : urgency }
    if (payload) n.exec = ["omarchy-shell", "shell", "summon", root.pluginId, JSON.stringify(payload)]
    notices.noteQueue = notices.noteQueue.concat([n])
    if (!noteProc.running) notices.nextNote()
  }
  function nextNote() {
    if (!notices.noteQueue.length || noteProc.running) return
    noteProc.note = JSON.stringify(notices.noteQueue[0])
    notices.noteQueue = notices.noteQueue.slice(1)
    noteProc.running = true
  }
  Process {
    id: noteProc
    property string note: ""
    command: ["python3", root.pluginDir + "bin/linear-notify"]
    stdinEnabled: true
    stdout: StdioCollector {}
    onStarted: { write(note + "\n"); stdinEnabled = false }
    onExited: function(code) {
      stdinEnabled = true
      if (code !== 0) console.warn("linear-board: a desktop notification could not be sent (exit " + code + ")")
      Qt.callLater(notices.nextNote)
    }
  }
}
