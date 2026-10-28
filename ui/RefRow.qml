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
// A row in the editor's relation / link lists.
Rectangle {
  id: refRow
  property string lead: ""
  property string ident: ""
  property string title: ""
  property string trail: ""
  property color dotColor: "transparent"
  property bool dim: false
  signal opened()
  signal removed()
  width: parent ? parent.width : 0
  height: refContent.implicitHeight + Style.spacing.md * 2
  radius: root.radius
  color: refMouse.containsMouse ? Util.alpha(root.fg, 0.08) : Util.alpha(root.fg, 0.04)
  MouseArea {
    id: refMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: refRow.opened()
  }
  Row {
    id: refContent
    anchors.left: parent.left
    anchors.right: refRemove.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.lg
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.md
    Label { visible: refRow.lead !== ""; text: refRow.lead; opacity: 0.6; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Dot { visible: refRow.dotColor.a > 0; dotColor: refRow.dotColor; anchors.verticalCenter: parent.verticalCenter }
    Label { visible: refRow.ident !== ""; text: refRow.ident; opacity: 0.55; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Label {
      id: refTitle
      text: refRow.title
      width: Math.max(0, refContent.width - x - refTrail.implicitWidth - Style.spacing.md)
      opacity: refRow.dim ? 0.6 : 1
      anchors.verticalCenter: parent.verticalCenter
    }
    Label { id: refTrail; text: refRow.trail; opacity: 0.5; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
  }
  Button {
    id: refRemove
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.xs
    anchors.verticalCenter: parent.verticalCenter
    iconText: root.icon.close
    tooltipText: "Remove"
    onClicked: refRow.removed()
  }
}
