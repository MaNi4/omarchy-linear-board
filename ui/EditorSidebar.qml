import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Recur.js" as Recur
import "../Time.js" as Time

// Part of the Linear board (mani4.linear-board): the issue editor's sidebar
// for a saved issue: triage, the properties (each a pill that opens its
// menu), repeat, time and actions. Created in ui/IssueEditor.qml as `sidebar`.
Rectangle {
  id: sidebar
  property alias sidePills: sidePills
  property alias edTimeField: edTimeField
  property alias edTimeDate: edTimeDate
  property alias edTimeNote: edTimeNote
  visible: editor.editing
  width: editor.editing ? editor.sidebarWidth : 0
  radius: root.radius
  color: Util.alpha(root.fg, 0.03)
  border.width: 1
  border.color: Util.alpha(root.fg, 0.08)

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.spacing.lg
    contentHeight: sideColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: sideColumn
      width: parent.width
      spacing: Style.spacing.xs

      // Triage: accept or decline first.
      Row {
        visible: !!(ed.orig && ed.orig.stateType === "triage")
        spacing: Style.spacing.sm
        bottomPadding: Style.spacing.md
        Chip { tip: "Accept into the backlog (A in the triage list)"; text: "Accept"; glyph: root.icon.check; strong: true; tint: root.tint("green"); onClicked: lists.triageAccept(ed.orig) }
        Chip { tip: "Decline: cancel it (D in the triage list)"; text: "Decline"; glyph: root.icon.close; strong: true; tint: root.urgent; onClicked: lists.triageDecline(ed.orig) }
      }

      // Properties: name on the left, the value as a pill that opens its menu.
      Repeater {
        id: sidePills
        model: editor.editing ? editor.pillKinds : []
        delegate: Item {
          required property var modelData
          property alias pill: sidePill
          readonly property var spec: editor.pillSpec(modelData)
          width: sideColumn.width
          height: sidePill.height
          Label {
            id: sideName
            width: Style.space(78)
            y: Math.min((parent.height - height) / 2, Style.space(8))
            text: editor.pillNames[modelData]
            opacity: 0.5
            font.pixelSize: Style.font.caption
          }
          PropPill {
            id: sidePill
            anchors.left: sideName.right
            anchors.right: parent.right
            wide: true
            glyph: spec.glyph
            glyphColor: spec.glyphColor
            showDot: spec.dot !== ""
            dotColor: spec.dot || "transparent"
            text: spec.unset ? "Set " + editor.pillNames[modelData].toLowerCase() : spec.text
            chips: spec.chips
            unset: spec.unset
            active: ed.menu === modelData || (modelData === "parent" && editor.parentOpen)
            tip: editor.pillTip(modelData)
            onClicked: editor.pillClicked(modelData, sidePill)
          }
        }
      }

      // ---- repeat (the board's own recurring issues) ----
      Item { width: 1; height: Style.spacing.lg; visible: !!editor.edRecur }
      SectionTitle { visible: !!editor.edRecur; text: "Repeat" }
      RowLayout {
        visible: !!editor.edRecur
        width: parent.width
        spacing: Style.spacing.sm
        Label { text: root.icon.repeat; color: root.accent }
        Label {
          Layout.fillWidth: true
          text: editor.edRecur ? Recur.recurLabel(editor.edRecur.every) + "  ·  next " + Recur.recurUpcoming(editor.edRecur, root.today) : ""
          font.pixelSize: Style.font.caption
        }
        Button {
          iconText: root.icon.trash
          foreground: root.urgent
          tooltipText: "Stop repeating (issues already made stay)"
          onClicked: { var r = editor.edRecur; pickers.ask("Stop repeating “" + r.title + "”? Issues already made stay.", "Stop", function() { issueOps.deleteRecurring(r.id) }) }
        }
      }

      // ---- time ----
      Item { width: 1; height: Style.spacing.lg }
      SectionTitle {
        text: "Time" + (timeTracker.timeTotals[ed.issueId] ? "  ·  " + Time.formatDuration(timeTracker.timeTotals[ed.issueId]) : "")
      }
      Button {
        readonly property bool isOn: timeTracker.isRunningOn(ed.issueId)
        width: parent.width
        iconText: isOn ? root.icon.stop : root.icon.play
        text: isOn ? "Stop  " + Time.formatClock(timeTracker.runningSeconds) : "Start timer"
        foreground: isOn ? root.accent : root.fg
        bordered: true
        tooltipText: timeTracker.running && !isOn ? "Stops the timer on " + timeTracker.running.identifier + " and logs it" : ""
        onClicked: timeTracker.toggleTimer(ed.orig)
      }
      Row {
        width: parent.width
        spacing: Style.spacing.xs
        TextField {
          id: edTimeField
          width: (parent.width - parent.spacing) * 0.45
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          placeholderText: "45m, 1h 30m"
          Keys.onReturnPressed: function(event) { edTimeAdd.clicked(); event.accepted = true }
        }
        TextField {
          id: edTimeDate
          width: (parent.width - parent.spacing) * 0.55
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          text: root.today
          Keys.onReturnPressed: function(event) { edTimeAdd.clicked(); event.accepted = true }
        }
      }
      Row {
        width: parent.width
        spacing: Style.spacing.xs
        TextField {
          id: edTimeNote
          width: parent.width - edTimeAdd.width - parent.spacing
          verticalPadding: 0
          implicitHeight: root.inlineHeight
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.bodySmall
          placeholderText: "Note"
          Keys.onReturnPressed: function(event) { edTimeAdd.clicked(); event.accepted = true }
        }
        Button {
          id: edTimeAdd
          iconText: root.icon.plus
          tooltipText: "Add the time"
          onClicked: if (timeTracker.addManualTime(ed.orig, edTimeField.text, edTimeDate.text, edTimeNote.text)) { edTimeField.text = ""; edTimeNote.text = "" }
        }
      }
      Repeater {
        model: editor.editing ? timeTracker.timeData.entries.filter(function(e) { return e.issueId === ed.issueId })
          .sort(function(a, b) { return a.start < b.start ? 1 : -1 }).slice(0, 4) : []
        delegate: RefRow {
          required property var modelData
          width: sideColumn.width
          lead: Time.formatDuration(modelData.seconds)
          title: Time.entryWhen(modelData) + (modelData.note ? "  ·  " + modelData.note : "")
          onOpened: lists.openTimeReport()
          onRemoved: timeTracker.deleteTimeEntry(modelData)
        }
      }

      // ---- actions ----
      Item { width: 1; height: Style.spacing.lg }
      SectionTitle { text: "Actions" }
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Chip { tip: "Make a copy of this issue"; text: "Duplicate"; glyph: root.icon.plus; onClicked: editorOps.duplicateIssue() }
        Chip { text: "Template"; glyph: root.icon.text; tip: "Save as a Linear issue template"; onClicked: editorOps.saveAsTemplate() }
        Chip {
          visible: root.onBoard(ed.issueId)
          text: "Archive"
          glyph: root.icon.archive
          tip: "Archive (Ctrl+Shift+X)"
          onClicked: editor.archiveOpen()
        }
        Chip { tip: "Delete: to Linear's trash for 30 days (Ctrl+Backspace or Delete outside a text field; G then X shows the trash)"; text: "Delete"; glyph: root.icon.trash; tint: root.urgent; onClicked: editorOps.deleteIssue(ed.issueId) }
      }
    }
  }
}
