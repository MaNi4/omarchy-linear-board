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
import "../Issues.js" as Issues
import "../Markdown.js" as Markdown
import "../Recur.js" as Recur
import "../Time.js" as Time

// Part of the Linear board (mani4.linear-board): one issue card in a board
// column: project code, ID, priority, timer, assignee, title, due date and
// other facts, labels, checklist progress. Click opens it, Ctrl+click picks
// it, drag moves it. Created by ui/BoardColumn.qml for each card.
Item {
  id: cardItem
  // The column it is in (ui/BoardColumn.qml).
  property var column: null
  required property int index
  readonly property var issue: cardItem.column.cards[index] || null
  readonly property bool selected: root.cursorShown && root.selCol === cardItem.column.index && root.selIdx === index
  readonly property bool isDragged: bulk.dragging && issue && bulk.dragId === issue.id
  readonly property bool done: cardItem.column.ws.type === "completed" || cardItem.column.ws.type === "canceled"
  readonly property var prio: Linear.priority(issue ? issue.priority : 0)
  readonly property bool picked: !!issue && root.multi.indexOf(issue.id) >= 0
  // Group heading above the first card of each group.
  readonly property var grp: issue && (root.config.group || "none") !== "none"
    ? Issues.groupOf(issue, root.config.group, { labels: root.labels, projects: root.projects }) : null
  readonly property bool groupStart: {
    if (!grp) return false
    if (index === 0) return true
    var prev = cardItem.column.cards[index - 1]
    return !prev || Issues.groupOf(prev, root.config.group, { labels: root.labels, projects: root.projects }).key !== grp.key
  }
  // Small facts under the title: due date, estimate, cycle, parent, sub-issues.
  readonly property var meta: {
    var i = cardItem.issue, out = []
    if (!i) return out
    var due = Dates.dueInfo(i.dueDate, root.today)
    if (due) out.push({ glyph: root.icon.calendar, text: due.text,
      color: cardItem.done ? "" : (due.level === "overdue" ? root.urgent : (due.level === "today" ? root.tint("orange") : "")) })
    if (i.estimate !== null) out.push({ glyph: root.icon.estimate, text: Linear.estimateLabel(root.team, i.estimate), color: "" })
    var cy = root.cycleById(i.cycleId)
    if (cy) out.push({ glyph: root.icon.cycle, text: cy.name || ("Cycle " + cy.number), color: cy.isActive ? root.accent : "" })
    if (i.milestoneName) out.push({ glyph: root.icon.flag, text: i.milestoneName, color: "" })
    if (i.parent) out.push({ glyph: root.icon.parent, text: i.parent.identifier, color: "" })
    var kids = root.childStats[i.id]
    if (kids) out.push({ glyph: root.icon.tree, text: kids.done + "/" + kids.total, color: "" })
    if (timeTracker.timeTotals[i.id]) out.push({ glyph: root.icon.timer, text: Time.formatDuration(timeTracker.timeTotals[i.id]), color: "" })
    return out
  }

  height: cardBody.y + cardBody.height

  Label {
    id: groupHead
    visible: cardItem.groupStart
    width: parent.width
    height: visible ? implicitHeight + Style.spacing.md : 0
    text: cardItem.grp ? cardItem.grp.label : ""
    font.pixelSize: Style.font.caption
    font.bold: true
    opacity: 0.6
    verticalAlignment: Text.AlignBottom
  }

  Rectangle {
    visible: bulk.dragging && bulk.dropCol === cardItem.column.index && bulk.dropIdx === cardItem.index
    width: parent.width
    height: Style.space(3)
    radius: height / 2
    y: -Style.spacing.md / 2 - height / 2
    color: root.accent
  }

  Rectangle {
    id: cardBody
    y: groupHead.height
    width: parent.width
    height: cardContent.implicitHeight + Style.spacing.xl * 2
    radius: root.radius
    opacity: cardItem.isDragged ? 0.35 : 1
    color: cardItem.picked ? Util.alpha(root.accent, 0.14) : (cardMouse.containsMouse ? Util.alpha(root.fg, 0.09) : Util.alpha(root.fg, 0.05))
    border.width: cardItem.selected || cardItem.picked ? Math.max(1, Style.space(2)) : 1
    border.color: cardItem.selected ? root.accent : (cardItem.picked ? Util.alpha(root.accent, 0.6) : Util.alpha(root.fg, 0.08))

    Column {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.xl
      spacing: Style.spacing.md

      Item {
        width: parent.width
        height: Math.max(idText.implicitHeight, avatar.height)
        Label {
          id: pickMark
          visible: cardItem.picked
          width: visible ? implicitWidth + Style.spacing.sm : 0
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.icon.check
          color: root.accent
          font.pixelSize: Style.font.caption + 1
        }
        // The web (project) the issue belongs to, unless the board shows only that project.
        Rectangle {
          id: codePill
          readonly property string code: cardItem.issue && cardItem.issue.projectId && cardItem.issue.projectId !== root.config.projectId
            ? root.codeFor(cardItem.issue.projectId) : ""
          visible: code !== ""
          width: visible ? codeText.implicitWidth + Style.spacing.md * 2 : 0
          height: codeText.implicitHeight + Style.space(2)
          anchors.left: pickMark.right
          anchors.verticalCenter: parent.verticalCenter
          radius: root.radius
          color: Util.alpha(cardItem.issue ? root.colorFor(cardItem.issue.projectId) : root.accent, 0.22)
          Label {
            id: codeText
            anchors.centerIn: parent
            text: codePill.code
            font.pixelSize: Style.font.caption
            font.bold: true
            color: cardItem.issue ? root.colorFor(cardItem.issue.projectId) : root.accent
          }
        }
        Label {
          id: idText
          anchors.left: codePill.right
          anchors.leftMargin: codePill.visible ? Style.spacing.sm : 0
          anchors.verticalCenter: parent.verticalCenter
          text: cardItem.issue ? cardItem.issue.identifier : ""
          opacity: 0.55
          font.pixelSize: Style.font.caption
        }
        Label {
          anchors.left: idText.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          visible: cardItem.prio.value !== 0
          text: cardItem.prio.short
          color: cardItem.prio.value === 1 ? root.urgent : root.tint(cardItem.prio.color)
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        // Start/stop the timer: shown on hover, and while it runs on this card.
        Rectangle {
          id: cardTimer
          readonly property bool runningHere: !!cardItem.issue && timeTracker.isRunningOn(cardItem.issue.id)
          visible: runningHere || cardMouse.containsMouse || timerMouse.containsMouse
          anchors.right: avatar.visible ? avatar.left : parent.right
          anchors.rightMargin: avatar.visible ? Style.spacing.sm : 0
          anchors.verticalCenter: parent.verticalCenter
          width: timerText.implicitWidth + Style.spacing.md * 2
          height: Style.space(20)
          radius: height / 2
          color: runningHere ? Util.alpha(root.accent, 0.22) : (timerMouse.containsMouse ? Util.alpha(root.fg, 0.15) : Util.alpha(root.fg, 0.07))
          Label {
            id: timerText
            anchors.centerIn: parent
            text: cardTimer.runningHere ? root.icon.stop + " " + Time.formatClock(timeTracker.runningSeconds) : root.icon.play
            color: cardTimer.runningHere ? root.accent : root.fg
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: timerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: timeTracker.toggleTimer(cardItem.issue)
          }
          PanelToolTip {
            visible: timerMouse.containsMouse
            text: cardTimer.runningHere ? "Stop the timer and log the time (Shift+T)" : "Start a timer on this issue (Shift+T)"
          }
        }
        Rectangle {
          id: avatar
          visible: !!(cardItem.issue && cardItem.issue.assignee)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          height: width
          radius: width / 2
          color: Util.alpha(root.accent, 0.25)
          Label {
            anchors.centerIn: parent
            text: cardItem.issue && cardItem.issue.assignee ? cardItem.issue.assignee.initials : ""
            font.pixelSize: Style.font.caption - 1
            color: root.accent
          }
        }
      }

      Label {
        width: parent.width
        text: cardItem.issue ? cardItem.issue.title : ""
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        opacity: cardItem.done ? 0.6 : 1
        font.strikeout: cardItem.column.ws.type === "canceled"
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.lg
        visible: cardItem.meta.length > 0
        Repeater {
          model: cardItem.meta
          delegate: Row {
            required property var modelData
            spacing: Style.spacing.xs
            Label {
              text: modelData.glyph
              color: modelData.color || root.fg
              opacity: modelData.color ? 1 : 0.55
              font.pixelSize: Style.font.caption + 1
              anchors.verticalCenter: parent.verticalCenter
            }
            Label {
              text: modelData.text
              color: modelData.color || root.fg
              opacity: modelData.color ? 1 : 0.7
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: !!(cardItem.issue && (cardItem.issue.labelIds.length || cardItem.issue.description))

        Repeater {
          model: cardItem.issue ? cardItem.issue.labelIds : []
          delegate: Rectangle {
            required property var modelData
            readonly property var label: root.labelById(modelData)
            visible: !!label
            width: visible ? lRow.implicitWidth + Style.spacing.lg * 2 : 0
            height: lRow.implicitHeight + Style.spacing.xs * 2
            radius: root.radius
            color: "transparent"
            border.width: 1
            border.color: Util.alpha(root.fg, 0.15)
            Row {
              id: lRow
              anchors.centerIn: parent
              spacing: Style.spacing.sm
              Dot { dotColor: parent.parent.label ? parent.parent.label.color : "transparent"; width: Style.space(7); anchors.verticalCenter: parent.verticalCenter }
              Label { text: parent.parent.label ? parent.parent.label.name : ""; font.pixelSize: Style.font.caption; opacity: 0.85 }
            }
          }
        }
        Label {
          visible: !!(cardItem.issue && cardItem.issue.description)
          text: root.icon.text
          opacity: 0.4
          font.pixelSize: Style.font.caption + 1
        }
        // Repeats (Repeat… in the editor).
        Label {
          readonly property var rule: cardItem.issue ? Recur.recurRuleFor(root.config.recurring, cardItem.issue) : null
          visible: !!rule
          text: root.icon.repeat
          color: root.accent
          opacity: 0.8
          font.pixelSize: Style.font.caption + 1
        }
        // Checklist progress in the description: "☑ 2/5".
        Label {
          readonly property var tasks: cardItem.issue && cardItem.issue.description.indexOf("[") >= 0
            ? Markdown.countTasks(cardItem.issue.description) : { total: 0, done: 0 }
          visible: tasks.total > 0
          text: "☑ " + tasks.done + "/" + tasks.total
          color: tasks.total > 0 && tasks.done === tasks.total ? root.accent : root.fg
          opacity: tasks.done === tasks.total ? 0.9 : 0.55
          font.pixelSize: Style.font.caption
        }
      }
    }

    MouseArea {
      id: cardMouse
      // Under the card's content, so the timer button on it gets its clicks.
      z: -1
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: bulk.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      property point pressAt: Qt.point(0, 0)

      onPressed: function(mouse) { pressAt = Qt.point(mouse.x, mouse.y) }
      onPositionChanged: function(mouse) {
        if (!pressed && root.pointerMoved(cardMouse, mouse.x, mouse.y)) root.cursorShown = false
        if (!pressed || !cardItem.issue || mouse.buttons !== Qt.LeftButton) return
        var p = cardMouse.mapToItem(dragLayer, mouse.x, mouse.y)
        if (!bulk.dragging) {
          if (Math.abs(mouse.x - pressAt.x) + Math.abs(mouse.y - pressAt.y) < Style.space(6)) return
          bulk.startDrag(cardItem.issue, p, Qt.point(pressAt.x, pressAt.y))
        } else bulk.updateDrag(p)
      }
      onReleased: function(mouse) {
        if (bulk.dragging) bulk.endDrag(true)
        else if (mouse.button === Qt.MiddleButton) editorOps.openInLinear(cardItem.issue.url)
        else if ((mouse.modifiers & Qt.ControlModifier) && cardItem.issue) bulk.toggleMulti(cardItem.issue.id)
        else if (cardItem.issue) issueOps.editIssue(cardItem.issue.id)
      }
      onCanceled: bulk.endDrag(false)
    }
  }
}
