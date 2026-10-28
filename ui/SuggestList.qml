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
// Suggestions under the relation / parent field.
Column {
  id: suggestList
  property string kind: ""
  visible: ed.suggestFor === kind && ed.suggestItems.length > 0
  spacing: Style.spacing.xs
  Repeater {
    model: suggestList.visible ? ed.suggestItems : []
    delegate: Rectangle {
      id: sugRow
      required property var modelData
      required property int index
      readonly property bool otherTeam: !!(root.team && modelData.teamId && modelData.teamId !== root.team.id)
      width: suggestList.width
      height: sugContent.implicitHeight + Style.spacing.sm * 2
      radius: root.radius
      color: index === ed.suggestCursor ? Util.alpha(root.accent, 0.16) : (sugMouse.containsMouse ? Util.alpha(root.fg, 0.08) : Util.alpha(root.fg, 0.04))
      MouseArea {
        id: sugMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) ed.suggestCursor = sugRow.index
        onClicked: editorOps.pickSuggestion(sugRow.modelData)
      }
      Row {
        id: sugContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.md
        Dot { dotColor: sugRow.modelData.stateColor || (root.stateById(sugRow.modelData.stateId) || {}).color || "#888888"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: sugRow.modelData.identifier; opacity: 0.55; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        Label {
          text: sugRow.modelData.title
          width: Math.max(0, sugContent.width - x - sugProject.width - sugState.implicitWidth - Style.spacing.md * 2)
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
        Row {
          id: sugProject
          readonly property var proj: sugRow.modelData.projectName ? { name: sugRow.modelData.projectName, color: sugRow.modelData.projectColor }
            : root.projectById(sugRow.modelData.projectId)
          visible: !!proj
          width: visible ? implicitWidth : 0
          spacing: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          Dot { dotColor: sugProject.proj && sugProject.proj.color ? sugProject.proj.color : root.accent; width: Style.space(8); anchors.verticalCenter: parent.verticalCenter }
          Label { text: sugProject.proj ? sugProject.proj.name : ""; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        }
        Label {
          id: sugState
          text: [sugRow.modelData.teamName, sugRow.modelData.stateName || (root.stateById(sugRow.modelData.stateId) || {}).name || ""]
            .filter(function(x) { return x }).join("  ·  ")
          opacity: 0.5
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
  Label { text: "↑↓ choose  ·  Enter or Tab pick  ·  Esc clear"; opacity: 0.4; font.pixelSize: Style.font.caption }
}
