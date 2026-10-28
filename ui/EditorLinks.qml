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
import "../Issues.js" as Issues

// Part of the Linear board (mani4.linear-board): what a saved issue is
// connected to, in the issue editor: its sub-issues, relations (blocks,
// duplicate of…) and links. Created in ui/IssueEditor.qml as `links`.
Column {
  id: links
  property alias relationField: relationField
  property alias linkField: linkField
  spacing: Style.spacing.xl

    // ---- sub-issues (saved issues only) ----
    RowLayout {
      visible: ed.issueId !== ""
      width: parent.width
      SectionTitle {
        text: "Sub-issues" + (ed.subIssues.length ? "  " + ed.subIssues.filter(function(c) { return c.done }).length + "/" + ed.subIssues.length : "")
        Layout.fillWidth: true
      }
      Button { tooltipText: "New sub-issue (Ctrl+Shift+O)"; text: "Add sub-issue"; iconText: root.icon.plus; onClicked: editorOps.addSubIssue() }
    }
    Column {
      visible: ed.issueId !== "" && ed.subIssues.length > 0
      width: parent.width
      spacing: Style.spacing.xs
      Repeater {
        model: ed.subIssues
        delegate: Rectangle {
          required property var modelData
          width: links.width
          height: childRow.implicitHeight + Style.spacing.md * 2
          radius: root.radius
          color: childMouse.containsMouse ? Util.alpha(root.fg, 0.08) : Util.alpha(root.fg, 0.04)
          Row {
            id: childRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.lg
            spacing: Style.spacing.md
            Dot { dotColor: modelData.stateColor; anchors.verticalCenter: parent.verticalCenter }
            Label { text: modelData.identifier; opacity: 0.55; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            Label {
              text: modelData.title
              width: Math.max(0, childRow.width - x - stateText.implicitWidth - Style.spacing.md)
              opacity: modelData.done ? 0.6 : 1
              anchors.verticalCenter: parent.verticalCenter
            }
            Label { id: stateText; text: modelData.stateName; opacity: 0.5; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea {
            id: childMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: editorOps.saveAndEdit(modelData.id, modelData.url)
          }
        }
      }
    }

    // ---- relations (saved issues only) ----
    SectionTitle { visible: ed.issueId !== ""; text: "Relations" + (ed.relations.length ? "  " + ed.relations.length : "") }
    Column {
      visible: ed.issueId !== "" && ed.relations.length > 0
      width: parent.width
      spacing: Style.spacing.xs
      Repeater {
        model: ed.relations
        delegate: RefRow {
          required property var modelData
          width: links.width
          lead: Linear.relationLabel(modelData.type, modelData.inverse)
          dotColor: modelData.issue.stateColor
          ident: modelData.issue.identifier
          title: modelData.issue.title
          trail: modelData.issue.stateName
          dim: modelData.issue.done
          onOpened: editorOps.saveAndEdit(modelData.issue.id, modelData.issue.url)
          onRemoved: editorOps.removeRelation(modelData)
        }
      }
    }
    Flow {
      visible: ed.issueId !== ""
      width: parent.width
      spacing: Style.spacing.sm
      Repeater {
        model: Linear.RELATION_KINDS
        delegate: Chip {
          required property var modelData
          text: modelData.label
          tint: root.accent
          selected: ed.relKind === modelData.id
          onClicked: ed.relKind = modelData.id
        }
      }
      TextField {
        id: relationField
        width: Style.space(260)
        verticalPadding: 0
        implicitHeight: root.inlineHeight
        verticalAlignment: TextInput.AlignVCenter
        font.pixelSize: Style.font.bodySmall
        placeholderText: "ID or title, e.g. " + (ed.team.key || "ENG") + "-12"
        onTextChanged: if (activeFocus) editorOps.updateSuggest("relation", text)
        onActiveFocusChanged: if (!activeFocus && ed.suggestFor === "relation") Qt.callLater(function() { if (!relationField.activeFocus && ed.suggestFor === "relation") editorOps.clearSuggest() })
        Keys.onPressed: function(event) {
          if (keyboard.altMenu(event)) return
          if (editorOps.suggestKey(event, "relation", relationField)) { event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { editorOps.addRelation(text); event.accepted = true }
        }
      }
    }
    SuggestList { kind: "relation"; width: parent.width }

    // ---- links / attachments (saved issues only) ----
    SectionTitle { visible: ed.issueId !== ""; text: "Links" + (ed.attachments.length ? "  " + ed.attachments.length : "") }
    Column {
      visible: ed.issueId !== "" && ed.attachments.length > 0
      width: parent.width
      spacing: Style.spacing.xs
      Repeater {
        model: ed.attachments
        delegate: RefRow {
          required property var modelData
          width: links.width
          lead: Issues.sourceLabel(modelData.source, modelData.url)
          title: modelData.title + (modelData.subtitle ? "  ·  " + modelData.subtitle : "")
          onOpened: editorOps.openInLinear(modelData.url)
          onRemoved: editorOps.removeAttachment(modelData)
        }
      }
    }
    TextField {
      id: linkField
      Keys.onPressed: function(event) { keyboard.altMenu(event) }
      visible: ed.issueId !== ""
      width: Math.min(parent.width, Style.space(420))
      verticalPadding: 0
      implicitHeight: root.inlineHeight
      verticalAlignment: TextInput.AlignVCenter
      font.pixelSize: Style.font.bodySmall
      placeholderText: "Add a link (URL) ↵"
      Keys.onReturnPressed: function(event) { editorOps.addLink(text); event.accepted = true }
      Keys.onEnterPressed: function(event) { editorOps.addLink(text); event.accepted = true }
    }
}
