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
// picker (team / project)
MouseArea {
  id: pickerPopup
  property alias pickerFlick: pickerFlick
  anchors.fill: parent
  z: 61
  visible: root.dialog === "picker"
  onClicked: pickers.closeDialog()

  Rectangle {
    x: Math.min(pickers.popupX, parent.width - width)
    y: pickers.popupBottom >= 0 ? Math.max(Style.spacing.lg, pickers.popupBottom - height) : boardScreen.header.height + Style.spacing.sm
    width: Style.space(300)
    height: Math.min(pickerList.implicitHeight + Style.spacing.md * 2,
      pickers.popupBottom >= 0 ? pickers.popupBottom - Style.spacing.lg : parent.height - boardScreen.header.height - Style.spacing.sm - Style.spacing.lg)
    radius: root.radius
    color: root.bg
    border.width: 1
    border.color: Util.alpha(root.fg, 0.25)
    MouseArea { anchors.fill: parent }

    Flickable {
      id: pickerFlick
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      contentHeight: pickerList.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      clip: true

    Column {
      id: pickerList
      width: pickerFlick.width
      Repeater {
        model: pickers.pickerItems.length
        delegate: Rectangle {
          required property int index
          readonly property var item: pickers.pickerItems[index]
          width: pickerList.width
          height: Style.spacing.popupRowHeight + Style.space(4)
          radius: root.radius
          color: index === pickers.cursor ? Util.alpha(root.fg, 0.1) : "transparent"
          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md
            Label { text: index < 9 ? String(index + 1) : " "; opacity: 0.35; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            Dot { visible: !!(item && item.color); dotColor: item && item.color ? item.color : "transparent"; anchors.verticalCenter: parent.verticalCenter }
            Label {
              text: item ? item.label : ""
              color: item && item.selected ? root.accent : root.fg
              font.italic: !!(item && item.id === "__new")
              anchors.verticalCenter: parent.verticalCenter
            }
            Label { text: item ? item.hint : ""; opacity: 0.45; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          }
          Label {
            visible: !!(item && item.selected)
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon.check
            color: root.accent
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) pickers.cursor = index
            onClicked: pickers.choosePicker(index)
          }
        }
      }
    }
    }
  }
}
