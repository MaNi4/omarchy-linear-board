// Run: npm run test:qml (needs Qt 6: qmltestrunner). The text fields of
// ui/ with stand-ins for the shell's qs.Commons and qs.Ui (imports/):
// Enter, Tab, paste never through Qt, sideways scrolling, the key field.
import QtQuick
import QtTest
import "../../ui"
Item {
  id: top
  width: 600; height: 400
  property var log: []
  Item { id: clipboard; function pasteText(f) { top.log.push("clip:" + f.objectName) } }
  Item { id: uploads; function pasteInto(f) { top.log.push("img:" + f.objectName) } }
  Column {
    TextBox { id: a; objectName: "a"; width: 100; placeholderText: "Find"; onAccepted: top.log.push("acceptedA") }
    TextBox { id: b; objectName: "b"; width: 100; Keys.onReturnPressed: function(e) { top.log.push("returnB:" + text); e.accepted = true } }
    TextBox { id: m; objectName: "m"; width: 200; height: 80; multiline: true; imagePaste: true; background: Rectangle { id: bg; color: "gray" } }
    SecretField { id: s; width: 200; Keys.onReturnPressed: function(e) { top.log.push("secret:" + s.text); e.accepted = true } }
  }
  TestCase {
    name: "textbox"; when: windowShown
    function test_line() {
      verify(a.children.some(function(c) { return c.visible && c.text === "Find" }), "placeholder shown")
      a.forceActiveFocus()
      keyClick(Qt.Key_H); keyClick(Qt.Key_I); keyClick(Qt.Key_Return)
      compare(a.text, "hi"); verify(top.log.indexOf("acceptedA") >= 0)
      verify(!a.children.some(function(c) { return c.visible && c.text === "Find" }), "placeholder hidden")
      keyClick(Qt.Key_V, Qt.ControlModifier); keyClick(Qt.Key_Insert, Qt.ShiftModifier)
      compare(a.text, "hi")
      keyClick(Qt.Key_Tab); wait(10)
      verify(b.activeFocus, "tab moved on"); compare(a.text, "hi")
      keyClick(Qt.Key_Backtab); wait(10); verify(a.activeFocus, "backtab back")
      keyClick(Qt.Key_Tab); wait(10)
      keyClick(Qt.Key_X); keyClick(Qt.Key_Return); compare(b.text, "x")
      a.forceActiveFocus(); a.cursorPosition = a.text.length
      for (var i = 0; i < 40; i++) keyClick(Qt.Key_W)
      var cx = a.cursorRectangle.x
      verify(cx >= 0 && cx <= a.width, "cursor in view: " + cx + " scroll " + a.scrollX)
      verify(a.scrollX > 0)
      keyClick(Qt.Key_Home); verify(a.scrollX === 0, "home scrolls back " + a.scrollX)
      a.text = "one\ntwo"; compare(a.text, "one two")
    }
    function test_multi() {
      m.forceActiveFocus()
      keyClick(Qt.Key_A); keyClick(Qt.Key_Return); keyClick(Qt.Key_B)
      compare(m.text, "a\nb")
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(bg.parent, m)
    }
    function test_secret() {
      s.forceActiveFocus()
      keyClick(Qt.Key_L); keyClick(Qt.Key_I); keyClick(Qt.Key_N); keyClick(Qt.Key_Backspace); keyClick(Qt.Key_V, Qt.ControlModifier); keyClick(Qt.Key_Return)
      s.insert(0, " zz \n")
    }
    function cleanupTestCase() { console.log(JSON.stringify(top.log), JSON.stringify(s.text)) }
  }
}
