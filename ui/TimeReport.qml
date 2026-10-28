import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Time.js" as Time

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// time report
Rectangle {
  id: timeDialog
  property alias timeIssueField: timeIssueField
  z: 62
  visible: root.dialog === "time"
  anchors.centerIn: parent
  width: Math.min(parent.width - Style.space(40), Style.space(900))
  height: Math.min(parent.height - Style.space(40), Style.space(760))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  MouseArea { anchors.fill: parent }

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    contentHeight: timeCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: timeCol
      width: parent.width
      spacing: Style.spacing.lg

      RowLayout {
        width: parent.width
        Label { text: "Time"; font.pixelSize: Style.font.title; font.bold: true }
        Label {
          Layout.fillWidth: true
          text: timeTracker.running ? "  ● " + timeTracker.running.identifier + "  " + Time.formatClock(timeTracker.runningSeconds) : ""
          color: root.accent
        }
        Button {
          tooltipText: "Stop the timer and log the time (Shift+T)"
          visible: !!timeTracker.running
          iconText: root.icon.stop
          text: "Stop"
          bordered: true
          onClicked: timeTracker.stopTimer()
        }
        Button { iconText: root.icon.help; tooltipText: "Shortcuts here (?)"; onClicked: keyboard.openHelp("time") }
        Button { tooltipText: "Close (Esc)"; iconText: root.icon.close; onClicked: pickers.closeDialog() }
      }

      Label {
        visible: timeTracker.timeError !== ""
        width: parent.width
        text: timeTracker.timeError
        color: root.urgent
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
      }

      // period
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: [{ id: "day", label: "Day" }, { id: "week", label: "Week" }, { id: "month", label: "Month" }]
          delegate: Chip {
            required property var modelData
            text: modelData.label
            tint: root.accent
            selected: timeTracker.reportKind === modelData.id
            onClicked: { timeTracker.reportKind = modelData.id; timeTracker.reportOffset = 0 }
          }
        }
        Button { iconText: root.icon.left; tooltipText: "Earlier (←)"; onClicked: timeTracker.reportOffset-- }
        Label { text: timeTracker.reportPeriod.label; font.bold: true; height: Style.spacing.controlHeight; verticalAlignment: Text.AlignVCenter }
        Button { iconText: root.icon.right; tooltipText: "Later (→)"; enabled: timeTracker.reportOffset < 0; onClicked: timeTracker.reportOffset = Math.min(0, timeTracker.reportOffset + 1) }
        Item { width: Style.spacing.xl; height: 1 }
        Chip { tip: "Totals by issue"; text: "By issue"; tint: root.accent; selected: timeTracker.reportBy === "issue"; onClicked: timeTracker.reportBy = "issue" }
        Chip { tip: "Totals by project"; text: "By project"; tint: root.accent; selected: timeTracker.reportBy === "project"; onClicked: timeTracker.reportBy = "project" }
      }

      Label {
        text: "Total " + Time.formatDuration(Time.total(timeTracker.reportEntries)) + "  (" + Time.hours(Time.total(timeTracker.reportEntries)) + " h)  ·  " +
          timeTracker.reportEntries.length + (timeTracker.reportEntries.length === 1 ? " entry" : " entries")
        font.bold: true
      }

      // totals
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        Repeater {
          model: timeTracker.reportGroups
          delegate: Rectangle {
            id: grpRow
            required property var modelData
            width: timeCol.width
            height: grpContent.implicitHeight + Style.spacing.md * 2
            radius: root.radius
            color: Util.alpha(root.fg, 0.04)
            Rectangle {
              // share of the period, as a bar under the row
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              height: Style.space(2)
              width: parent.width * grpRow.modelData.seconds / Math.max(1, Time.total(timeTracker.reportEntries))
              color: Util.alpha(root.accent, 0.6)
            }
            Row {
              id: grpContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.lg
              anchors.rightMargin: Style.spacing.lg
              spacing: Style.spacing.md
              Label {
                text: grpRow.modelData.label
                width: Math.max(0, grpContent.width - grpSub.implicitWidth - grpTime.implicitWidth - Style.spacing.md * 2)
              }
              Label { id: grpSub; text: grpRow.modelData.sub; opacity: 0.5; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Label { id: grpTime; text: Time.formatDuration(grpRow.modelData.seconds); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            }
          }
        }
      }

      // manual entry
      SectionTitle { text: "Add time" }
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        TextField {
          id: timeIssueField
          width: Style.space(300)
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          placeholderText: "Issue: ID or title"
          onTextChanged: if (activeFocus) { timeTracker.reportIssue = null; editorOps.updateSuggest("time", text) }
          Keys.onPressed: function(event) { if (editorOps.suggestKey(event, "time", timeIssueField)) event.accepted = true }
        }
        TextField {
          id: timeDurField
          width: Style.space(120)
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          placeholderText: "45m, 1h 30m"
          Keys.onReturnPressed: function(event) { timeAddBtn.clicked(); event.accepted = true }
        }
        TextField {
          id: timeDateField
          width: Style.space(120)
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          text: root.today
          Keys.onReturnPressed: function(event) { timeAddBtn.clicked(); event.accepted = true }
        }
        TextField {
          id: timeNoteField
          width: Style.space(200)
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          placeholderText: "Note (optional)"
          Keys.onReturnPressed: function(event) { timeAddBtn.clicked(); event.accepted = true }
        }
        Button {
          tooltipText: "Add the time (Enter in the fields)"
          id: timeAddBtn
          text: "Add"
          iconText: root.icon.plus
          bordered: true
          onClicked: if (timeTracker.addManualTime(timeTracker.reportIssue, timeDurField.text, timeDateField.text, timeNoteField.text)) {
            timeDurField.text = ""; timeNoteField.text = ""
          }
        }
      }
      SuggestList { kind: "time"; width: parent.width }

      // entries
      SectionTitle { text: "Entries" }
      Label { visible: timeTracker.reportEntries.length === 0; text: "Nothing logged in this period"; opacity: 0.5 }
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        Repeater {
          model: timeTracker.reportEntries
          delegate: Rectangle {
            id: entRow
            required property var modelData
            readonly property bool editing: timeTracker.reportEditId === modelData.id
            width: timeCol.width
            height: entContent.implicitHeight + Style.spacing.md * 2
            radius: root.radius
            color: entMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent"
            MouseArea { id: entMouse; anchors.fill: parent; hoverEnabled: true }
            Row {
              id: entContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.lg
              anchors.rightMargin: Style.spacing.sm
              spacing: Style.spacing.md
              Label {
                id: entWhen
                text: Time.entryWhen(entRow.modelData)
                opacity: 0.55
                font.pixelSize: Style.font.caption
                width: Style.space(130)
                anchors.verticalCenter: parent.verticalCenter
              }
              Label {
                visible: !entRow.editing
                text: entRow.modelData.identifier + "  " + entRow.modelData.title + (entRow.modelData.note ? "  ·  " + entRow.modelData.note : "")
                width: Math.max(0, entContent.width - entWhen.width - Style.space(70) - Style.space(150) - Style.spacing.md * 3)
                anchors.verticalCenter: parent.verticalCenter
              }
              TextField {
                id: entDurEdit
                visible: entRow.editing
                width: Style.space(100)
                verticalPadding: 0
                implicitHeight: root.inlineHeight
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.bodySmall
                text: Time.formatDuration(entRow.modelData.seconds)
                Keys.onReturnPressed: function(event) { entSave.clicked(); event.accepted = true }
              }
              TextField {
                id: entNoteEdit
                visible: entRow.editing
                width: Math.max(Style.space(120), entContent.width - entWhen.width - entDurEdit.width - Style.space(150) - Style.spacing.md * 4)
                verticalPadding: 0
                implicitHeight: root.inlineHeight
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.bodySmall
                placeholderText: "Note"
                text: entRow.modelData.note
                Keys.onReturnPressed: function(event) { entSave.clicked(); event.accepted = true }
              }
              Label {
                id: entDur
                visible: !entRow.editing
                width: Style.space(70)
                horizontalAlignment: Text.AlignRight
                text: Time.formatDuration(entRow.modelData.seconds)
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Row {
                id: entActions
                width: Style.space(150)
                layoutDirection: Qt.RightToLeft
                spacing: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                Button {
                  tooltipText: "Save (Enter)"
                  id: entSave
                  visible: entRow.editing
                  text: "Save"
                  onClicked: if (timeTracker.updateTimeEntry(entRow.modelData, entDurEdit.text, entNoteEdit.text)) timeTracker.reportEditId = ""
                }
                Button {
                  tooltipText: "Change the duration or note"
                  text: entRow.editing ? "Cancel" : "Edit"
                  onClicked: timeTracker.reportEditId = entRow.editing ? "" : entRow.modelData.id
                }
                Button {
                  visible: !entRow.editing
                  iconText: root.icon.trash
                  tooltipText: "Delete"
                  foreground: root.urgent
                  onClicked: timeTracker.deleteTimeEntry(entRow.modelData)
                }
              }
            }
          }
        }
      }

      // export; sharing and backup live in Settings → Data
      SectionTitle { text: "Export and sharing" }
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Button { tooltipText: "Save this period as CSV to Downloads"; text: "Export this period (CSV)"; iconText: root.icon.download; bordered: true; onClicked: timeTracker.exportCsv(timeTracker.reportPeriod, timeTracker.reportEntries) }
        Button { tooltipText: "Settings → Data"; text: "Shared folder, backup…"; iconText: root.icon.cog; onClicked: pickers.openSettings("data") }
      }
      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        opacity: 0.5
        font.pixelSize: Style.font.caption
        text: "Saved in " + timeTracker.timePath.replace(root.home, "~") + ". To share the time (with recurring issues and settings) between computers, or to export or import all of it, use Settings → Data."
      }
      Chip {
        tip: "Switch: post logged time to the issue as a comment"
        text: root.config.timeComments ? "Logged time is also posted to the issue as a comment" : "Logged time stays on this computer only (no Linear comments)"
        glyph: root.icon.comment
        tint: root.accent
        selected: root.config.timeComments
        onClicked: root.setConfig({ timeComments: !root.config.timeComments })
      }
      Label {
        opacity: 0.4
        font.pixelSize: Style.font.caption
        text: "? shortcuts"
      }
    }
  }
}
