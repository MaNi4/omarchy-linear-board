import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Part of the Linear board (mani4.linear-board): the board's text field, one
// line or (multiline: true) many. Used in place of TextField and TextArea.
//
// It is a TextEdit on purpose: a TextField (TextInput) reads the whole
// clipboard whenever the clipboard changes, to know whether it could paste.
// A TextEdit only looks at the offered types. Pasting never goes through
// Qt: Ctrl+V and Shift+Insert call paste(), which asks logic/Clipboard.qml
// for at most maxPasteBytes of text, and the middle and right buttons are
// swallowed. Fields that take images (multiline ones with imagePaste) let
// logic/Uploads.qml look for an image first.
//
// Callers use it like the shell's TextField: text, placeholderText,
// placeholderTextColor, horizontalPadding / verticalPadding, background,
// hasCursor, and Keys handlers of their own.
TextEdit {
  id: field

  property bool multiline: false
  // Ctrl+V looks for an image in the clipboard first (uploaded to Linear).
  property bool imagePaste: false
  property int maxPasteBytes: multiline ? 200000 : 4096

  property string placeholderText: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color placeholderTextColor: Qt.darker(field.foreground, 1.6)
  property bool hasCursor: false
  readonly property alias hovered: hover.hovered
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  readonly property var borderSpec: Border.controlSpec(field.activeFocus ? "focus" : (hover.hovered || field.hasCursor ? "hover-cursor" : "normal"),
    field.foreground, field.accent)
  // The space left and right of the text; callers with a background of
  // their own set these (0 for the title).
  property real padLeft: field.horizontalPadding + Border.left(field.borderSpec)
  property real padRight: field.horizontalPadding + Border.right(field.borderSpec)

  property Item background: BorderSurface {
    color: Style.controlFill(field.activeFocus, hover.hovered || field.hasCursor, field.foreground, field.accent)
    borderSpec: field.borderSpec
    radius: Style.cornerRadius
  }

  // Enter in a one-line field (when the caller's keys did not take it).
  signal accepted()

  // One line does not wrap; it scrolls sideways so the cursor stays in view.
  property real scrollX: 0

  textFormat: TextEdit.PlainText
  wrapMode: field.multiline ? TextEdit.Wrap : TextEdit.NoWrap
  clip: !field.multiline
  selectByMouse: true
  persistentSelection: false
  activeFocusOnTab: true
  color: field.foreground
  selectionColor: Style.selectionFillFor(field.foreground, field.accent)
  selectedTextColor: field.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  verticalAlignment: field.multiline ? TextEdit.AlignTop : TextEdit.AlignVCenter
  leftPadding: field.padLeft - field.scrollX
  rightPadding: field.padRight
  topPadding: field.verticalPadding + Border.top(field.borderSpec)
  bottomPadding: field.verticalPadding + Border.bottom(field.borderSpec)

  function placeBackground() {
    if (!field.background) return
    field.background.parent = field
    field.background.z = -1
    field.background.anchors.fill = field
  }
  onBackgroundChanged: field.placeBackground()
  Component.onCompleted: field.placeBackground()

  // Qt's own paste is never used, also when something calls field.paste().
  function paste() {
    if (field.readOnly) return
    if (field.imagePaste) uploads.pasteInto(field)
    else clipboard.pasteText(field)
  }

  // A typed Enter or Tab in a one-line field: TextEdit puts it in the text
  // (no Keys handler took it). Take it out again: Enter accepts, Tab moves
  // on. This runs before the callers' onTextChanged, so they never see it.
  property string lastText: ""
  onTextChanged: {
    if (!field.multiline && /[\r\n\t]/.test(field.text)) {
      var at = field.cursorPosition
      var typed = field.text.length === field.lastText.length + 1 ? field.text.charAt(at - 1) : ""
      if (typed === "\n" || typed === "\t") {
        field.text = field.lastText
        field.cursorPosition = Math.max(0, Math.min(at - 1, field.text.length))
        if (typed === "\n") field.accepted()
        else Qt.callLater(function() { field.moveFocus(true) })
      } else {
        field.text = field.text.replace(/\r\n|[\r\n\t]/g, " ")
        field.cursorPosition = Math.min(at, field.text.length)
      }
      return
    }
    field.lastText = field.text
  }

  function moveFocus(forward) {
    var next = field.nextItemInFocusChain(forward)
    if (next && next !== field) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
  }

  onCursorRectangleChanged: field.keepCursorInView()
  onWidthChanged: field.keepCursorInView()
  // A multiline field in a ScrollView: its Flickable (scrollView.contentItem),
  // scrolled along with the cursor.
  property Flickable flickable: null
  function keepCursorInView() {
    if (field.multiline) {
      field.scrollX = 0
      var f = field.flickable
      if (!f || !field.activeFocus) return
      var r = field.cursorRectangle
      if (r.y < f.contentY) f.contentY = Math.max(0, r.y)
      else if (r.y + r.height > f.contentY + f.height) f.contentY = r.y + r.height - f.height
      return
    }
    var x = field.cursorRectangle.x + field.scrollX   // where the cursor is with no scrolling
    var view = Math.max(1, field.width - field.padLeft - field.padRight)
    var s = field.scrollX
    if (x - s > field.padLeft + view - 1) s = x - field.padLeft - view + 1
    if (x - s < field.padLeft) s = x - field.padLeft
    s = Math.max(0, Math.min(s, Math.max(0, field.contentWidth - view + 1)))
    if (s !== field.scrollX) field.scrollX = s
  }

  Keys.onPressed: function(event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
      field.paste()
    } else if (!field.multiline && event.key === Qt.Key_Backtab) {
      event.accepted = true
      field.moveFocus(false)
    }
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.IBeamCursor
  }

  // The middle button would paste the primary selection; the right one has
  // nothing to offer.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onPressed: function(mouse) { mouse.accepted = true }
    onReleased: function(mouse) { mouse.accepted = true }
  }

  Text {
    visible: field.length === 0 && field.preeditText === ""
    x: field.padLeft
    y: field.topPadding
    width: Math.max(0, field.width - field.padLeft - field.padRight)
    height: Math.max(0, field.height - field.topPadding - field.bottomPadding)
    textFormat: Text.PlainText
    text: field.placeholderText
    color: field.placeholderTextColor
    font: field.font
    elide: field.multiline ? Text.ElideNone : Text.ElideRight
    wrapMode: field.multiline ? Text.Wrap : Text.NoWrap
    verticalAlignment: field.verticalAlignment
  }
}
