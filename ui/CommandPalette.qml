import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// command palette (Ctrl+K)
Rectangle {
  id: paletteDialog
  property alias paletteField: paletteField
  z: 63
  visible: root.dialog === "palette"
  anchors.horizontalCenter: parent.horizontalCenter
  y: Style.space(60)
  width: Math.min(parent.width - Style.space(40), Style.space(640))
  height: Math.min(parent.height - y - Style.space(40), paletteField.height + paletteList.contentHeight + Style.spacing.panelPadding * 2 + Style.spacing.lg)
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.accent, 0.6)
  MouseArea { anchors.fill: parent }
  TextBox {
    id: paletteField
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
    placeholderText: root.icon.console + "  Type a command, an issue ID or title, or a Linear link"
    onTextChanged: { commands.paletteQuery = text; commands.paletteCursor = 0; paletteList.positionViewAtBeginning() }
    Keys.onDownPressed: function(event) { commands.paletteCursor = Math.min(commands.paletteItems.length - 1, commands.paletteCursor + 1); paletteList.positionViewAtIndex(commands.paletteCursor, ListView.Contain); event.accepted = true }
    Keys.onUpPressed: function(event) { commands.paletteCursor = Math.max(0, commands.paletteCursor - 1); paletteList.positionViewAtIndex(commands.paletteCursor, ListView.Contain); event.accepted = true }
    Keys.onTabPressed: function(event) { commands.paletteCursor = (commands.paletteCursor + 1) % Math.max(1, commands.paletteItems.length); paletteList.positionViewAtIndex(commands.paletteCursor, ListView.Contain); event.accepted = true }
    Keys.onReturnPressed: function(event) { commands.runPalette(commands.paletteCursor); event.accepted = true }
    Keys.onEnterPressed: function(event) { commands.runPalette(commands.paletteCursor); event.accepted = true }
    Keys.onEscapePressed: function(event) { pickers.closeDialog(); event.accepted = true }
  }
  ListView {
    id: paletteList
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: paletteField.bottom
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: commands.paletteItems
    delegate: Rectangle {
      required property var modelData
      required property int index
      width: paletteList.width
      height: Style.spacing.popupRowHeight + Style.space(4)
      radius: root.radius
      color: index === commands.paletteCursor ? Util.alpha(root.accent, 0.18) : (palMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")
      Label {
        anchors.left: parent.left
        anchors.right: palHint.left
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: index === commands.paletteCursor ? root.accent : root.fg
      }
      Label {
        id: palHint
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.hint
        opacity: 0.45
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: palMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) commands.paletteCursor = index
        onClicked: commands.runPalette(index)
      }
    }
  }
}
