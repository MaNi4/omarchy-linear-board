import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Part of the Linear board (mani4.linear-board): the field for the API key.
// The keys are collected one by one into `text` and only dots are drawn: no
// text item holds the key, and the clipboard is read only on paste
// (logic/Clipboard.qml), like ui/TextBox.qml.
BorderSurface {
  id: secret

  property string text: ""
  property string placeholderText: ""
  property int maximumLength: 256
  readonly property int maxPasteBytes: secret.maximumLength
  readonly property bool multiline: false
  // What logic/Clipboard.qml needs of a field: the cursor is always at the end.
  readonly property int cursorPosition: secret.text.length
  readonly property int selectionStart: secret.text.length
  readonly property int selectionEnd: secret.text.length
  function remove(from, to) { }
  function insert(at, t) { secret.text = (secret.text + String(t).trim()).substring(0, secret.maximumLength) }

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  readonly property var spec: Border.controlSpec(secret.activeFocus ? "focus" : (hover.hovered ? "hover-cursor" : "normal"), secret.foreground, secret.accent)

  activeFocusOnTab: true
  implicitWidth: Style.space(240)
  implicitHeight: dots.implicitHeight + (Style.spacing.inputPaddingY + Border.top(secret.spec)) * 2
  color: Style.controlFill(secret.activeFocus, hover.hovered, secret.foreground, secret.accent)
  borderSpec: secret.spec
  radius: Style.cornerRadius

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    if (event.matches(StandardKey.Paste)) { event.accepted = true; clipboard.pasteText(secret) }
    else if (event.key === Qt.Key_Backspace) { event.accepted = true; secret.text = ctrl ? "" : secret.text.slice(0, -1) }
    else if (!ctrl && !alt && event.text.length > 0 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127) {
      event.accepted = true
      secret.text = (secret.text + event.text).substring(0, secret.maximumLength)
    }
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.IBeamCursor
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onPressed: function(mouse) { mouse.accepted = true; secret.forceActiveFocus() }
  }

  Text {
    id: dots
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(secret.spec)
    anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(secret.spec)
    textFormat: Text.PlainText
    elide: Text.ElideLeft
    text: secret.text.length ? "•".repeat(Math.min(64, secret.text.length)) + (secret.activeFocus ? "▏" : "")
      : (secret.activeFocus ? "▏" : secret.placeholderText)
    color: secret.text.length || secret.activeFocus ? secret.foreground : Qt.darker(secret.foreground, 1.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
