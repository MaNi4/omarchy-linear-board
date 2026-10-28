import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Linear.js" as Linear
import "../Dates.js" as Dates
import "../Time.js" as Time

// Part of the Linear board (mani4.linear-board): in the list layout
// (Ctrl+B), one workflow state's heading and a row per issue, with drag
// and drop between groups. Created by ui/BoardView.qml for each shown column.
Column {
  id: groupItem
  required property int index
  readonly property var ws: root.columns[index] || ({ id: "", name: "", color: "#888888", type: "" })
  readonly property var cards: root.visibleByColumn[index] || []
  spacing: Style.spacing.xs
  function rowY(i) { var it = rowRepeater.itemAt(i); return it ? it.mapToItem(groupItem.parent, 0, 0).y : groupItem.y }
  // Drop position for y (group coordinates): before the first row whose middle is below it.
  function dropIndexAt(y) {
    for (var i = 0; i < rowRepeater.count; i++) {
      var it = rowRepeater.itemAt(i)
      if (it && y < it.y + it.height / 2) return i
    }
    return rowRepeater.count
  }
  readonly property bool dropHere: bulk.dragging && bulk.dropCol === index
  function rowH(i) { var it = rowRepeater.itemAt(i); return it ? it.height : 0 }

  Rectangle {
    readonly property bool cursorHere: root.cursorShown && root.selCol === groupItem.index && groupItem.cards.length === 0
    width: parent.width
    height: Style.spacing.controlHeight
    radius: root.radius
    color: cursorHere || groupItem.dropHere ? Util.alpha(root.accent, 0.12) : Util.alpha(root.fg, 0.04)
    border.width: cursorHere || groupItem.dropHere ? Math.max(1, Style.space(2)) : 0
    border.color: root.accent
    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md
      Dot { dotColor: groupItem.ws.color; anchors.verticalCenter: parent.verticalCenter }
      Label { text: groupItem.ws.name; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Label { text: String(groupItem.cards.length); opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
    }
    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.icon.plus
      tooltipText: "New issue in " + groupItem.ws.name
      onClicked: issueOps.newIssue(groupItem.index)
    }
  }

  Repeater {
    id: rowRepeater
    model: groupItem.cards.length
    delegate: Rectangle {
      id: rowItem
      required property int index
      readonly property var issue: groupItem.cards[index] || null
      readonly property bool selected: root.cursorShown && root.selCol === groupItem.index && root.selIdx === index
      readonly property bool picked: !!issue && root.multi.indexOf(issue.id) >= 0
      readonly property bool done: groupItem.ws.type === "completed" || groupItem.ws.type === "canceled"
      readonly property var prio: Linear.priority(issue ? issue.priority : 0)
      readonly property string code: issue && issue.projectId && issue.projectId !== root.config.projectId ? root.codeFor(issue.projectId) : ""
      readonly property var due: issue ? Dates.dueInfo(issue.dueDate, root.today) : null
      width: groupItem.width
      height: Style.spacing.popupRowHeight + Style.space(8)
      radius: root.radius
      color: picked ? Util.alpha(root.accent, 0.14) : (rowMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent")
      opacity: bulk.dragging && issue && bulk.dragId === issue.id ? 0.35 : 1
      border.width: selected ? Math.max(1, Style.space(2)) : 0
      border.color: root.accent

      // Drop marker above this row while dragging.
      Rectangle {
        visible: bulk.dragging && bulk.dropCol === groupItem.index && bulk.dropIdx === rowItem.index
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        y: -Style.spacing.xs / 2 - height / 2
        color: root.accent
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: bulk.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        property point pressAt: Qt.point(0, 0)
        onPressed: function(mouse) { pressAt = Qt.point(mouse.x, mouse.y) }
        onPositionChanged: function(mouse) {
          if (!pressed && root.pointerMoved(rowMouse, mouse.x, mouse.y)) root.cursorShown = false
          if (!pressed || !rowItem.issue || mouse.buttons !== Qt.LeftButton) return
          var p = rowMouse.mapToItem(dragLayer, mouse.x, mouse.y)
          if (!bulk.dragging) {
            if (Math.abs(mouse.x - pressAt.x) + Math.abs(mouse.y - pressAt.y) < Style.space(6)) return
            bulk.startDrag(rowItem.issue, p, Qt.point(Math.min(pressAt.x, Style.space(40)), pressAt.y))
          } else bulk.updateDrag(p)
        }
        onReleased: function(mouse) {
          if (bulk.dragging) { bulk.endDrag(true); return }
          if (!rowItem.issue) return
          if (mouse.button === Qt.MiddleButton) editorOps.openInLinear(rowItem.issue.url)
          else if (mouse.modifiers & Qt.ControlModifier) bulk.toggleMulti(rowItem.issue.id)
          else issueOps.editIssue(rowItem.issue.id)
        }
        onCanceled: bulk.endDrag(false)
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.md
        Label { visible: rowItem.picked; text: root.icon.check; color: root.accent; font.pixelSize: Style.font.caption + 1 }
        Label {
          Layout.preferredWidth: Style.space(16)
          text: rowItem.prio.value !== 0 ? rowItem.prio.short : ""
          color: rowItem.prio.value === 1 ? root.urgent : root.tint(rowItem.prio.color)
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Rectangle {
          visible: rowItem.code !== ""
          Layout.preferredWidth: rowCode.implicitWidth + Style.spacing.md * 2
          Layout.preferredHeight: rowCode.implicitHeight + Style.space(2)
          radius: root.radius
          color: Util.alpha(rowItem.issue ? root.colorFor(rowItem.issue.projectId) : root.accent, 0.22)
          Label { id: rowCode; anchors.centerIn: parent; text: rowItem.code; font.pixelSize: Style.font.caption; font.bold: true; color: rowItem.issue ? root.colorFor(rowItem.issue.projectId) : root.accent }
        }
        Label { text: rowItem.issue ? rowItem.issue.identifier : ""; opacity: 0.55; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(64) }
        Label {
          Layout.fillWidth: true
          text: rowItem.issue ? rowItem.issue.title : ""
          opacity: rowItem.done ? 0.6 : 1
          font.strikeout: groupItem.ws.type === "canceled"
        }
        Repeater {
          model: rowItem.issue ? rowItem.issue.labelIds.slice(0, 3) : []
          delegate: Row {
            required property var modelData
            readonly property var label: root.labelById(modelData)
            visible: !!label
            spacing: Style.spacing.xs
            Dot { dotColor: parent.label ? parent.label.color : "transparent"; width: Style.space(7); anchors.verticalCenter: parent.verticalCenter }
            Label { text: parent.label ? parent.label.name : ""; font.pixelSize: Style.font.caption; opacity: 0.75; anchors.verticalCenter: parent.verticalCenter }
          }
        }
        Label {
          visible: !!(rowItem.issue && rowItem.issue.milestoneName)
          text: rowItem.issue ? root.icon.flag + " " + rowItem.issue.milestoneName : ""
          opacity: 0.6
          font.pixelSize: Style.font.caption
        }
        Label {
          visible: !!rowItem.due
          text: rowItem.due ? root.icon.calendar + " " + rowItem.due.text : ""
          color: !rowItem.done && rowItem.due && rowItem.due.level === "overdue" ? root.urgent : root.fg
          opacity: 0.75
          font.pixelSize: Style.font.caption
        }
        Label {
          visible: !!(rowItem.issue && rowItem.issue.estimate !== null)
          text: rowItem.issue && rowItem.issue.estimate !== null ? root.icon.estimate + " " + Linear.estimateLabel(root.team, rowItem.issue.estimate) : ""
          opacity: 0.6
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          readonly property bool runningHere: !!rowItem.issue && timeTracker.isRunningOn(rowItem.issue.id)
          visible: runningHere || rowMouse.containsMouse || rowTimerMouse.containsMouse
          Layout.preferredWidth: rowTimerText.implicitWidth + Style.spacing.md * 2
          Layout.preferredHeight: Style.space(20)
          radius: height / 2
          color: runningHere ? Util.alpha(root.accent, 0.22) : (rowTimerMouse.containsMouse ? Util.alpha(root.fg, 0.15) : Util.alpha(root.fg, 0.07))
          Label {
            id: rowTimerText
            anchors.centerIn: parent
            text: parent.runningHere ? root.icon.stop + " " + Time.formatClock(timeTracker.runningSeconds) : root.icon.play
            color: parent.runningHere ? root.accent : root.fg
            font.pixelSize: Style.font.caption
          }
          MouseArea { id: rowTimerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: timeTracker.toggleTimer(rowItem.issue) }
          PanelToolTip { visible: rowTimerMouse.containsMouse; text: parent.runningHere ? "Stop the timer and log the time (Shift+T)" : "Start a timer on this issue (Shift+T)" }
        }
        Rectangle {
          Layout.preferredWidth: Style.space(20)
          Layout.preferredHeight: Style.space(20)
          radius: width / 2
          color: rowItem.issue && rowItem.issue.assignee ? Util.alpha(root.accent, 0.25) : "transparent"
          Label {
            anchors.centerIn: parent
            text: rowItem.issue && rowItem.issue.assignee ? rowItem.issue.assignee.initials : ""
            font.pixelSize: Style.font.caption - 1
            color: root.accent
          }
        }
      }
    }
  }
  Rectangle {
    visible: groupItem.dropHere && bulk.dropIdx >= groupItem.cards.length
    width: parent.width
    height: Style.space(3)
    radius: height / 2
    color: root.accent
  }
}
