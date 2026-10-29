import Quickshell
import Quickshell.Io
import QtQuick

// The only place the board reads text from the clipboard: when a field is
// pasted into (ui/TextBox.qml, ui/SecretField.qml), and never more than the
// field can use. Images are read by logic/Uploads.qml.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `clipboard`.
Item {
  id: clipboard
  visible: false

  property var target: null

  // field: has text, cursorPosition, selectionStart/End, insert, remove,
  // maxPasteBytes and multiline.
  function pasteText(field) {
    if (!field || reader.running) return
    clipboard.target = field
    reader.command = ["sh", "-c", 'timeout 2 wl-paste --no-newline --type text 2>/dev/null | head -c "$1"', "sh", String(field.maxPasteBytes || 4096)]
    reader.running = true
  }

  function finish(raw) {
    var field = clipboard.target
    clipboard.target = null
    if (!field || !field.activeFocus) return
    // A character cut in half at the byte limit is dropped.
    var text = String(raw || "").replace(/�+$/, "")
    if (!field.multiline) text = text.replace(/\r\n|[\r\n\t]/g, " ")
    if (!text) return
    if (field.selectionEnd > field.selectionStart) field.remove(field.selectionStart, field.selectionEnd)
    field.insert(field.cursorPosition, text)
  }

  Process {
    id: reader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: clipboard.finish(text)
    }
  }
}
