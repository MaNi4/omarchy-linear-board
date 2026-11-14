import Quickshell
import Quickshell.Io
import QtQuick
import "lb" as LB
import "lb/Linear.js" as Linear

// The board alone in its own Quickshell, for tests/e2e/run.js: offscreen,
// against tests/fake-linear.js, with its files in a temporary directory.
// The runner drives it over IPC (`t.ev` evaluates JavaScript here).
ShellRoot {
  id: top

  LB.Board { id: board; manifest: ({ id: "mani4.linear-board" }) }

  // The bar widget, fed by the board's inbox.json like in the real bar.
  Item {
    width: 200; height: 30
    LB.BarWidget { id: bar; bar: top.fakeBar }
  }
  property var ran: []
  property var fakeBar: ({ run: function(cmd) { top.ran = top.ran.concat([cmd]) } })

  // The board's window and its parts (logic/*.qml), found among its children.
  function win() {
    for (var i = 0; i < board.data.length; i++) { var o = board.data[i]; if (o && o.title === "Linear Board") return o }
    return null
  }
  function m(fn) {
    for (var i = 0; i < board.data.length; i++) { var o = board.data[i]; if (o && typeof o[fn] === "function") return o }
    return null
  }
  // The board's part that has property `prop` (the editor state: "milestoneValid").
  function p(prop) {
    for (var i = 0; i < board.data.length; i++) { var o = board.data[i]; if (o && o[prop] !== undefined && typeof o[prop] !== "function") return o }
    return null
  }
  // The first item in the window that has property `prop` (the editor: "titleField").
  function find(prop) {
    var w = win()
    var walk = function(o) {
      if (!o) return null
      if (o[prop] !== undefined) return o
      for (var i = 0; i < (o.children || []).length; i++) { var r = walk(o.children[i]); if (r) return r }
      return null
    }
    return w ? walk(w.contentItem) : null
  }
  function key(k, mods, text) {
    var e = { key: k, modifiers: mods || 0, text: text || "", accepted: false, isAutoRepeat: false }
    m("handleKey").handleKey(e)
    return e.accepted
  }

  IpcHandler {
    target: "t"
    function ev(js: string): string {
      try { var v = eval(js); return JSON.stringify(v === undefined ? null : v) } catch (e) { return JSON.stringify({ __error: String(e) }) }
    }
    function shot(path: string): string {
      var w = top.win()
      if (!w || !w.visible) return "no window"
      w.contentItem.children[0].grabToImage(function(r) { r.saveToFile(path) })
      return "ok"
    }
  }
}
