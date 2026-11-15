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

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// project overview
Rectangle {
  id: projectDialog
  property alias projUpdateField: projUpdateField
  z: 62
  visible: root.dialog === "project"
  anchors.centerIn: parent
  width: Math.min(parent.width - Style.space(40), Style.space(760))
  height: Math.min(parent.height - Style.space(40), Style.space(760))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  MouseArea { anchors.fill: parent }
  readonly property var pr: projectOps.projectDetail

  RowLayout {
    id: projHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
    Dot { dotColor: parent.parent.pr ? parent.parent.pr.color : root.accent }
    Label {
      text: (parent.parent.pr ? parent.parent.pr.name : "Project") + (projectOps.projectLoading ? "  · loading…" : "")
      font.pixelSize: Style.font.title
      font.bold: true
      Layout.fillWidth: true
    }
    Button {
      tooltipText: "Open the project in Linear"
      visible: !!(parent.parent.pr && parent.parent.pr.url)
      text: "Open in Linear"
      iconText: root.icon.open
      onClicked: editorOps.openInLinear(parent.parent.pr.url)
    }
    Button { iconText: root.icon.help; tooltipText: "Shortcuts here (?)"; onClicked: keyboard.openHelp("project") }
    Button { tooltipText: "Close (Esc)"; iconText: root.icon.close; onClicked: pickers.closeDialog() }
  }

  Flickable {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: projHeader.bottom
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.lg
    contentHeight: projBody.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: projBody
      width: parent.width
      spacing: Style.spacing.lg
      readonly property var pr: projectOps.projectDetail

      // Other projects of the team, to switch.
      Flow {
        visible: root.projects.length > 1
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.dialog === "project" ? root.projects : []
          delegate: Chip {
            required property var modelData
            text: (root.codeFor(modelData.id) ? root.codeFor(modelData.id) + "  " : "") + modelData.name
            showDot: true
            dotColor: modelData.color
            tint: root.accent
            selected: projectOps.projectViewId === modelData.id
            onClicked: projectOps.openProject(modelData.id)
          }
        }
      }

      // Progress and lead.
      Column {
        width: parent.width
        spacing: Style.spacing.sm
        Rectangle {
          width: parent.width
          height: Style.space(6)
          radius: height / 2
          color: Util.alpha(root.fg, 0.1)
          Rectangle {
            width: parent.width * (projBody.pr ? projBody.pr.progress : 0)
            height: parent.height
            radius: height / 2
            color: projBody.pr && projBody.pr.color ? projBody.pr.color : root.accent
          }
        }
        Label {
          text: projBody.pr ? Math.round(projBody.pr.progress * 100) + "% done" + (projBody.pr.lead ? "  ·  lead " + projBody.pr.lead : "")
            + (projBody.pr.startDate ? "  ·  started " + projBody.pr.startDate : "") : ""
          opacity: 0.6
          font.pixelSize: Style.font.caption
        }
      }

      SectionTitle { text: "Status" }
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.dialog === "project" ? projectOps.projectStatuses : []
          delegate: Chip {
            required property var modelData
            text: modelData.name
            showDot: true
            dotColor: modelData.color
            tint: root.accent
            selected: !!(projBody.pr && projBody.pr.status && projBody.pr.status.id === modelData.id)
            onClicked: projectOps.saveProject(projectOps.projectViewId, { statusId: modelData.id })
          }
        }
      }

      SectionTitle { text: "Target date" }
      RowLayout {
        width: parent.width
        TextBox {
          id: projTargetField
          Layout.preferredWidth: Style.space(200)
          text: projBody.pr ? projBody.pr.targetDate : ""
          placeholderText: "2026-12-31"
          Keys.onReturnPressed: function(event) { projectOps.setProjectTarget(text); keyScope.forceActiveFocus(); event.accepted = true }
        }
        Button { tooltipText: "Set the target date (Enter)"; text: "Set"; onClicked: projectOps.setProjectTarget(projTargetField.text) }
        Button { tooltipText: "Remove the target date"; text: "Clear"; onClicked: { projTargetField.text = ""; projectOps.setProjectTarget("") } }
        Item { Layout.fillWidth: true }
      }

      SectionTitle { text: "Milestones" + (projBody.pr && projBody.pr.milestones.length ? "  " + projBody.pr.milestones.length : "") }
      Repeater {
        model: projBody.pr ? projBody.pr.milestones : []
        delegate: RowLayout {
          required property var modelData
          width: projBody.width
          spacing: Style.spacing.md
          readonly property int count: root.issues.filter(function(i) { return i.milestoneId === modelData.id }).length
          Label { text: root.icon.flag; color: root.accent }
          TextBox {
            id: msName
            Layout.fillWidth: true
            text: modelData.name
            Keys.onReturnPressed: function(event) { projectOps.updateMilestone(modelData, msName.text, msDate.text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          TextBox {
            id: msDate
            Layout.preferredWidth: Style.space(140)
            text: modelData.targetDate
            placeholderText: "Target date"
            Keys.onReturnPressed: function(event) { projectOps.updateMilestone(modelData, msName.text, msDate.text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          Label { text: parent.count + (parent.count === 1 ? " issue" : " issues") + " here"; opacity: 0.5; font.pixelSize: Style.font.caption }
          Button { iconText: root.icon.check; tooltipText: "Save (Enter)"; onClicked: projectOps.updateMilestone(modelData, msName.text, msDate.text) }
          Button { iconText: root.icon.trash; foreground: root.urgent; tooltipText: "Delete"; onClicked: projectOps.deleteMilestone(modelData) }
        }
      }
      RowLayout {
        width: parent.width
        TextBox {
          id: newMsName
          Layout.fillWidth: true
          placeholderText: "New milestone, e.g. Launch"
          Keys.onReturnPressed: function(event) { if (projectOps.addMilestone(newMsName.text, newMsDate.text)) { newMsName.text = ""; newMsDate.text = "" } event.accepted = true }
        }
        TextBox {
          id: newMsDate
          Layout.preferredWidth: Style.space(140)
          placeholderText: "Target date"
          Keys.onReturnPressed: function(event) { if (projectOps.addMilestone(newMsName.text, newMsDate.text)) { newMsName.text = ""; newMsDate.text = "" } event.accepted = true }
        }
        Button { tooltipText: "Add the milestone (Enter)"; text: "Add"; iconText: root.icon.plus; bordered: true; onClicked: if (projectOps.addMilestone(newMsName.text, newMsDate.text)) { newMsName.text = ""; newMsDate.text = "" } }
      }

      SectionTitle { text: "Updates" }
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: Linear.HEALTH
          delegate: Chip {
            required property var modelData
            text: modelData.label
            showDot: true
            dotColor: modelData.color
            tint: modelData.color
            selected: projectOps.updateHealth === modelData.id
            onClicked: projectOps.updateHealth = modelData.id
          }
        }
      }
      QQC.ScrollView {
        id: projUpdateScroll
        width: parent.width
        height: Style.space(90)
        TextBox {
          id: projUpdateField
          multiline: true
          imagePaste: true
          flickable: projUpdateScroll.contentItem
          width: projUpdateScroll.availableWidth
          height: Math.max(implicitHeight, projUpdateScroll.availableHeight)
          placeholderText: projectOps.projectEditUpdateId ? "Edit your update (Ctrl+Enter saves, Esc cancels)" : "What changed since the last update? (Markdown, Ctrl+Enter posts)"
          wrapMode: TextEdit.Wrap
          color: root.fg
          placeholderTextColor: Util.alpha(root.fg, 0.4)
          selectionColor: Util.alpha(root.accent, 0.35)
          font.family: root.font
          font.pixelSize: Style.font.body
          padLeft: Style.spacing.lg
          padRight: Style.spacing.lg
          topPadding: Style.spacing.lg
          bottomPadding: Style.spacing.lg
          background: Rectangle {
            radius: root.radius
            color: Util.alpha(root.fg, 0.04)
            border.width: 1
            border.color: projUpdateField.activeFocus ? root.accent : Util.alpha(root.fg, 0.2)
          }
          // Drop files here (images from a browser too): uploaded to Linear.
          DropArea {
            anchors.fill: parent
            onEntered: function(drag) { drag.accepted = drag.hasUrls }
            onDropped: function(drop) {
              if (!drop.hasUrls) return
              uploads.dropFiles(drop.urls, projUpdateField, projUpdateField.positionAt(drop.x, drop.y))
              drop.accept()
            }
            Rectangle {
              anchors.fill: parent
              visible: parent.containsDrag
              radius: root.radius
              color: Util.alpha(root.accent, 0.12)
              border.width: Math.max(1, Style.space(2))
              border.color: root.accent
              Label { anchors.centerIn: parent; text: root.icon.upload + "  Drop to upload to Linear"; color: root.accent }
            }
          }
          Keys.onPressed: function(event) {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
              if (projectOps.postProjectUpdate(projUpdateField.text)) projUpdateField.text = ""
              event.accepted = true
            } else if (event.key === Qt.Key_Escape && projectOps.projectEditUpdateId) {
              projectOps.cancelProjectUpdateEdit()
              event.accepted = true
            } else if (editorOps.markdownKey(projUpdateField, event)) event.accepted = true
          }
        }
      }
      Row {
        spacing: Style.spacing.md
        Button {
          tooltipText: "Post (Ctrl+Enter)"
          text: projectOps.projectEditUpdateId ? "Save changes" : "Post update"
          iconText: projectOps.projectEditUpdateId ? root.icon.check : root.icon.send
          bordered: true
          onClicked: if (projectOps.postProjectUpdate(projUpdateField.text)) projUpdateField.text = ""
        }
        Button {
          tooltipText: "Stop editing (Esc)"
          visible: projectOps.projectEditUpdateId !== ""
          text: "Cancel"
          onClicked: projectOps.cancelProjectUpdateEdit()
        }
      }
      Label { visible: !projectOps.projectLoading && projectOps.projectUpdates.length === 0; text: "No updates yet"; opacity: 0.5 }
      Repeater {
        model: root.dialog === "project" ? projectOps.projectUpdates : []
        delegate: Column {
          required property var modelData
          width: projBody.width
          spacing: Style.spacing.xs
          Row {
            spacing: Style.spacing.md
            Dot { visible: !!Linear.healthInfo(modelData.health); dotColor: Linear.healthInfo(modelData.health) ? Linear.healthInfo(modelData.health).color : "transparent"; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Linear.healthInfo(modelData.health) ? Linear.healthInfo(modelData.health).label : ""; font.bold: true; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
            Label { text: modelData.author + "  ·  " + Dates.shortDateTime(modelData.createdAt); opacity: 0.5; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            // Only your own updates can be changed.
            Button {
              tooltipText: "Edit your update"
              visible: !!(root.viewer && modelData.authorId === root.viewer.id)
              text: "Edit"
              anchors.verticalCenter: parent.verticalCenter
              onClicked: projectOps.editProjectUpdate(modelData)
            }
            Button {
              tooltipText: "Delete your update (Linear archives it)"
              visible: !!(root.viewer && modelData.authorId === root.viewer.id)
              text: "Delete"
              foreground: root.urgent
              anchors.verticalCenter: parent.verticalCenter
              onClicked: projectOps.deleteProjectUpdate(modelData)
            }
          }
          MarkdownView {
            width: parent.width
            markdown: modelData.body
            opacity: 0.9
            canDelete: !!(root.viewer && modelData.authorId === root.viewer.id)
            onDeleteImage: function(url) { uploads.deleteUpload(url, { kind: "update", update: modelData }) }
            canToggle: !!(root.viewer && modelData.authorId === root.viewer.id) && projectOps.projectEditUpdateId !== modelData.id
            onToggleTask: function(line) { projectOps.toggleUpdateTask(modelData, line) }
          }
        }
      }
    }
  }
}
