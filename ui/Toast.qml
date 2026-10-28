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
// toast: short messages (copied, saved, errors), above everything
Rectangle {
  id: toastBox
  z: 90
  readonly property bool shown: notices.toast !== ""
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.bottom: parent.bottom
  anchors.bottomMargin: (bulkBar.visible ? bulkBar.height + Style.space(36) : Style.space(36)) + (shown ? 0 : -Style.space(12))
  width: Math.min(parent.width - Style.space(40), toastMetrics.advanceWidth + toastGlyph.implicitWidth + Style.spacing.md + Style.spacing.xl * 2 + 2)
  height: toastText.implicitHeight + Style.spacing.lg * 2
  TextMetrics { id: toastMetrics; font: toastText.font; text: notices.toast }
  radius: root.radius
  color: Qt.lighter(root.bg, 1.2)
  border.width: Math.max(1, Style.space(2))
  border.color: notices.toastError ? root.urgent : root.accent
  opacity: shown ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: 160 } }
  Behavior on anchors.bottomMargin { NumberAnimation { duration: 160 } }
  MouseArea {
    anchors.fill: parent
    cursorShape: notices.toastAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: notices.clickToast()
  }
  Row {
    id: toastRow
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    spacing: Style.spacing.md
    Label {
      id: toastGlyph
      text: notices.toastIcon
      color: notices.toastError ? root.urgent : root.accent
      font.pixelSize: Style.font.body + 2
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      id: toastText
      text: notices.toast
      width: toastRow.width - toastGlyph.implicitWidth - Style.spacing.md
      color: root.fg
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
