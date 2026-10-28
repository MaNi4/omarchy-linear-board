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
// confirm
Rectangle {
  id: confirmBox
  anchors.fill: parent
  z: 70
  visible: pickers.confirmText !== ""
  color: Util.alpha(root.bg, 0.6)
  MouseArea { anchors.fill: parent; onClicked: { pickers.confirmText = ""; pickers.refocus() } }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), Style.space(440))
    height: confirmColumn.implicitHeight + Style.spacing.panelPadding * 2
    radius: root.radius
    color: root.bg
    border.width: 1
    border.color: Util.alpha(root.urgent, 0.6)
    MouseArea { anchors.fill: parent }

    Column {
      id: confirmColumn
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.xl
      Label { width: parent.width; text: pickers.confirmText; wrapMode: Text.WordWrap; elide: Text.ElideNone }
      Row {
        anchors.right: parent.right
        spacing: Style.spacing.lg
        Button { tooltipText: "Cancel (Esc)"; text: "Cancel"; onClicked: { pickers.confirmText = ""; pickers.refocus() } }
        Button { tooltipText: "Confirm (Enter or Y)"; text: pickers.confirmLabel; foreground: root.urgent; bordered: true; onClicked: pickers.runConfirm() }
      }
    }
  }
}
