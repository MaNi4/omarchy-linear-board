import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Hotkey.js" as Hotkey

// The board's global keys in the running Hyprland session, like the mani4
// plugins do it: a service is mounted with the shell, so the keys work as
// soon as the plugin is installed, without anything in ~/.config/hypr.
// Keys somebody else holds are never taken over: one notification names
// them and opens the board's key settings. The keys are kept in
// ~/.config/omarchy/extensions/linear-board.json.
Item {
  id: service
  visible: false

  readonly property string pluginId: "mani4.linear-board"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/linear-board.json"

  property var config: Hotkey.parseConfig("").config
  property bool firstRun: false       // there was no config file: say which keys, once
  property var boundHotkeys: []       // what we bound, so unloading can unbind it
  property var warned: ({})           // notify once per taken key, not on every reload
  property bool queued: false

  function summonAction(payload) {
    return "hl.dsp.exec_cmd(" + Hotkey.quote("omarchy-shell shell summon " + service.pluginId + " '" + payload + "'") + ")"
  }

  function applyConfig(text, missing) {
    var parsed = Hotkey.parseConfig(text)
    if (parsed.error) console.warn("linear-board: " + service.configPath + " is not a JSON object, the default keys are used")
    service.config = parsed.config
    service.firstRun = missing
    startTimer.restart()
  }

  FileView {
    path: service.configPath
    watchChanges: true
    printErrors: false
    onLoaded: service.applyConfig(text(), false)
    onLoadFailed: service.applyConfig("", true)
    onFileChanged: reload()
  }

  // The short delay lets a previous instance's unbind land first when the
  // plugin is reloaded.
  Timer {
    id: startTimer
    interval: 600
    onTriggered: service.ensure()
  }

  function ensure() {
    if (bindsProc.running) { service.queued = true; return }
    bindsProc.running = true
  }

  function reconcile(bindsJson) {
    var plan = Hotkey.plan(bindsJson, [
      { setting: "hotkey", hotkey: service.config.hotkey, description: Hotkey.TOGGLE, action: service.summonAction('{"toggle":true}') },
      { setting: "newIssueHotkey", hotkey: service.config.newIssueHotkey, description: Hotkey.NEW_ISSUE, action: service.summonAction('{"new":true}') }
    ])
    if (plan.lua.length > 0) Quickshell.execDetached(["hyprctl", "eval", plan.lua.join("\n")])
    service.boundHotkeys = plan.bound

    var conflict = Hotkey.notice(plan.conflicts, service.warned)
    if (conflict && !note.running) {
      for (var i = 0; i < conflict.hotkeys.length; i++) service.warned[conflict.hotkeys[i]] = true
      note.show(conflict.title, conflict.body, conflict.action, conflict.payload)
    } else if (service.firstRun && plan.conflicts.length === 0 && !note.running) {
      var key = Hotkey.tidy(service.config.hotkey)
      var newKey = Hotkey.tidy(service.config.newIssueHotkey)
      note.show("Linear board",
        (key ? key + " opens your Linear board" : "No key opens the Linear board yet")
        + (newKey ? ", " + newKey + " a new issue. " : ". ") + "Click to change the keys.", "Keys", '{"setup":"keys"}')
    }
    // Hello is said once: from now on there is a config file, ready to edit.
    if (service.firstRun && !conflict) {
      service.firstRun = false
      creator.running = true
    }
    if (service.queued) { service.queued = false; service.ensure() }
  }

  // The first config file, with the default keys; never written over.
  Process {
    id: creator
    command: ["sh", "-c", 'set -C; mkdir -p "$(dirname "$1")" && cat > "$1" 2>/dev/null || cat > /dev/null', "sh", service.configPath]
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(service.config, null, 2) + "\n")
      stdinEnabled = false
    }
    onExited: stdinEnabled = true
  }

  // Clicking the notification opens the board's key settings. Sent over
  // D-Bus by bin/linear-notify (read on stdin), like the board's own.
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^[a-z]+:\/\//, "").replace(/\/?$/, "/")
  Process {
    id: note
    property string message: ""
    function show(title, body, action, payloadJson) {
      note.message = JSON.stringify({ title: title, body: body, urgency: 1,
        exec: ["omarchy-shell", "shell", "summon", service.pluginId, payloadJson] })
      note.running = true
    }
    command: ["python3", service.pluginDir + "bin/linear-notify"]
    stdinEnabled: true
    stdout: StdioCollector {}
    onStarted: { write(note.message + "\n"); stdinEnabled = false }
    onExited: stdinEnabled = true
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.reconcile(String(text || ""))
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Hyprland drops runtime binds when its config reloads.
      if (event && String(event.name) === "configreloaded") service.ensure()
    }
  }

  // Disabling, removing or reloading the plugin takes the keys with it.
  Component.onDestruction: {
    var lua = []
    for (var i = 0; i < service.boundHotkeys.length; i++) {
      var combo = Hotkey.parse(service.boundHotkeys[i])
      if (combo) lua.push(Hotkey.unbind(combo.mask, combo.key))
    }
    if (lua.length > 0) Quickshell.execDetached(["hyprctl", "eval", lua.join("\n")])
  }
}
