import Quickshell
import Quickshell.Io
import QtQuick
import "../Hotkey.js" as Hotkey

// The global keys as Settings → Keys shows them: the config file the service
// (Service.qml) binds from, and which keys are free in Hyprland right now.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `hotkeys`.
Item {
  id: hotkeys
  visible: false

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/linear-board.json"
  property var config: Hotkey.parseConfig("").config
  property string bindsJson: "[]"
  readonly property var settings: [
    { id: "hotkey", label: "Open the board", description: Hotkey.TOGGLE },
    { id: "newIssueHotkey", label: "New issue", description: Hotkey.NEW_ISSUE }
  ]

  FileView {
    id: configFile
    path: hotkeys.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: hotkeys.config = Hotkey.parseConfig(text()).config
    onLoadFailed: hotkeys.config = Hotkey.parseConfig("").config
    onFileChanged: reload()
  }

  function refreshBinds() { if (!bindsProc.running) bindsProc.running = true }
  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: hotkeys.bindsJson = String(text || "[]") }
  }
  // The service rebinds a moment after the file changes; then look again.
  Timer { id: rebindCheck; interval: 1500; onTriggered: hotkeys.refreshBinds() }

  // The keys to offer for a setting and what is typed: free ones first, a
  // taken one says what holds it (Hotkey.choices).
  function choices(setting, typed) {
    var s = hotkeys.settings.filter(function(x) { return x.id === setting })[0]
    return s ? Hotkey.choices(hotkeys.bindsJson, typed, Hotkey.IDEAS[setting], s.description) : []
  }

  // "" binds nothing. The service picks the file up and rebinds.
  function setHotkey(setting, value) {
    var key = value === "" ? "" : Hotkey.tidy(value)
    if (value !== "" && !key) { notices.notify("That is not a key combination, e.g. SUPER + SHIFT + K", true); return }
    var s = hotkeys.settings.filter(function(x) { return x.id === setting })[0]
    var held = key ? Hotkey.holder(hotkeys.bindsJson, key, s ? s.description : "") : ""
    if (held) { notices.notify(key + " is already used by “" + held + "”", true); return }
    var next = {}
    for (var k in hotkeys.config) next[k] = hotkeys.config[k]
    next[setting] = key
    hotkeys.config = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
    notices.notify(key ? (s ? s.label : setting) + ": " + key : (s ? s.label : setting) + ": no key", false, root.icon.check)
    rebindCheck.restart()
  }
}
