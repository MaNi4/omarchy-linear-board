import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon for the Linear inbox with an unread count. The board overlay checks
// Linear every minute and writes the count to a small runtime file, which this
// widget watches, so the API key and the requests stay in one place.
BarWidget {
  id: root

  moduleName: "mani4.linear-board"

  property bool connected: false
  property int unread: 0
  property var items: []
  property var timer: null             // { identifier, title, startedAt } while a timer runs
  property double nowMs: Date.now()
  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-linear-board/inbox.json"

  implicitWidth: (timerButton.visible ? timerButton.implicitWidth : 0) + button.implicitWidth
  implicitHeight: button.implicitHeight

  function apply(raw) {
    try {
      var s = JSON.parse(raw || "{}")
      root.connected = s.connected === true
      root.unread = Math.max(0, Number(s.unread) || 0)
      root.items = Array.isArray(s.items) ? s.items.slice(0, 5) : []
      root.timer = s.timer && s.timer.startedAt ? s.timer : null
      root.nowMs = Date.now()
    } catch (e) {
      root.connected = false
    }
  }

  function oneLine(text, limit) {
    return String(text || "").replace(/[\r\n\t]+/g, " ").replace(/</g, "‹").replace(/>/g, "›").slice(0, limit)
  }

  // Watching misses the file being created after the widget loads (first
  // start, or the shell restarting before the board writes it), so also
  // re-read it every few seconds.
  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.apply(text())
    onFileChanged: reload()
    onLoadFailed: root.connected = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: !!root.timer
    onTriggered: root.nowMs = Date.now()
  }

  function clock(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
    var p = function(n) { return n < 10 ? "0" + n : String(n) }
    return (h ? h + ":" + p(m) : String(m)) + ":" + p(sec)
  }

  // Running timer: issue and elapsed time; a click stops it and logs the time.
  WidgetButton {
    id: timerButton
    visible: !!root.timer
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    text: root.timer ? String.fromCodePoint(0xF13AB) + " " + (root.timer.projectCode ? root.timer.projectCode + " · " : "") +
      root.timer.identifier + " " + root.clock((root.nowMs - new Date(root.timer.startedAt).getTime()) / 1000) : ""
    active: true
    tooltipText: root.timer ? "Working on " + root.timer.identifier + ": " + root.oneLine(root.timer.title, 70) +
      (root.timer.projectName ? "\nProject: " + root.oneLine(root.timer.projectName, 50) : "") + "\nClick to stop and log the time" : ""
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton)
        root.bar.run("omarchy-shell shell summon mani4.linear-board '{\"toggle\":true}'")
      else
        root.bar.run("omarchy-shell shell summon mani4.linear-board '{\"timer\":\"stop\"}'")
    }
  }

  BarIconButton {
    id: button
    anchors.left: timerButton.visible ? timerButton.right : parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    text: String.fromCodePoint(0xF0687)
    dimmed: !root.connected
    tooltipText: {
      if (!root.connected) return "Linear: open the board to connect"
      if (root.unread === 0) return "Linear inbox: nothing unread"
      var lines = [root.unread + " unread in Linear"]
      root.items.forEach(function(n) {
        lines.push((n.identifier ? n.identifier + "  " : "") + root.oneLine(n.title, 70))
      })
      return lines.join("\n")
    }
    onPressed: function(mouseButton) {
      if (!root.bar) return
      // Left: inbox. Right: the board.
      if (mouseButton === Qt.RightButton)
        root.bar.run("omarchy-shell shell summon mani4.linear-board '{\"toggle\":true}'")
      else
        root.bar.run("omarchy-shell shell summon mani4.linear-board '{\"toggle\":true,\"inbox\":true}'")
    }
  }

  Rectangle {
    visible: root.connected && root.unread > 0
    anchors.right: button.right
    anchors.rightMargin: Style.space(1)
    anchors.top: button.top
    anchors.topMargin: Style.space(3)
    width: Math.max(countText.implicitWidth + Style.space(6), Style.space(12))
    height: Style.space(12)
    radius: height / 2
    color: Color.accent

    Text {
      id: countText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      font.family: Style.font.family
      font.pixelSize: Math.max(8, Style.font.caption - Style.space(3))
      font.bold: true
      color: Color.background
    }
  }
}
