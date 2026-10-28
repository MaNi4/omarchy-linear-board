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
Rectangle {
  id: chip
  property string text: ""
  property string glyph: ""
  property color tint: root.fg
  property color dotColor: "transparent"
  property bool selected: false
  property bool showDot: false
  property bool strong: false
  property real fontSize: Style.font.bodySmall
  property string tip: ""
  signal clicked()
  implicitWidth: chipRow.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Math.max(root.inlineHeight, chipRow.implicitHeight + Style.spacing.xs * 2)
  radius: root.radius
  color: selected ? Util.alpha(tint, 0.22) : (chipMouse.containsMouse ? Util.alpha(tint, 0.12) : Util.alpha(tint, strong ? 0.12 : 0.05))
  border.width: selected ? 1 : 0
  border.color: Util.alpha(tint, 0.85)

  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.spacing.sm
    Dot { visible: chip.showDot; dotColor: chip.dotColor; anchors.verticalCenter: parent.verticalCenter; width: Style.space(8) }
    Label {
      visible: chip.glyph !== ""
      text: chip.glyph
      color: chip.selected || chip.strong ? chip.tint : root.fg
      font.pixelSize: chip.fontSize + 1
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      visible: chip.text !== ""
      text: chip.text
      color: chip.selected || chip.strong ? chip.tint : root.fg
      font.pixelSize: chip.fontSize
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
  PanelToolTip {
    visible: chip.tip !== "" && chipMouse.containsMouse
    text: chip.tip
  }
}
