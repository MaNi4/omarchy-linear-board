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
// ================= bulk bar =================
Rectangle {
  id: bulkBar
  z: 40
  visible: root.mode === "board" && root.multi.length > 0
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.bottom: parent.bottom
  anchors.bottomMargin: Style.space(28)
  width: bulkRow.width + Style.spacing.lg * 2
  height: bulkRow.height + Style.spacing.md * 2
  radius: root.radius
  color: Qt.lighter(root.bg, 1.15)
  border.width: 1
  border.color: Util.alpha(root.accent, 0.6)
  MouseArea { anchors.fill: parent }

  // A Flow, so the buttons wrap instead of running off a narrow window.
  Flow {
    id: bulkRow
    anchors.centerIn: parent
    width: Math.min(Style.space(860), bulkBar.parent.width - Style.spacing.lg * 4)
    spacing: Style.spacing.sm
    Label {
      text: root.multi.length + " selected"
      font.bold: true
      color: root.accent
      height: bulkStateBtn.height
      verticalAlignment: Text.AlignVCenter
      rightPadding: Style.spacing.md
    }
    Button { tooltipText: "Status of the selected issues (S)"; id: bulkStateBtn; text: "Status"; iconText: root.icon.down; onClicked: bulk.openBulkPicker("bulkState", bulkStateBtn) }
    Button { tooltipText: "Assign the selected issues (A, or I to assign them to you)"; id: bulkAssignBtn; text: "Assign"; iconText: root.icon.account; onClicked: bulk.openBulkPicker("bulkAssignee", bulkAssignBtn) }
    Button { tooltipText: "Priority of the selected issues (P)"; id: bulkPrioBtn; text: "Priority"; iconText: root.icon.filter; onClicked: bulk.openBulkPicker("bulkPriority", bulkPrioBtn) }
    Button { tooltipText: "Add or remove a label (T)"; id: bulkLabelBtn; text: "Label"; iconText: root.icon.plus; onClicked: bulk.openBulkPicker("bulkLabel", bulkLabelBtn) }
    Button { tooltipText: "Project of the selected issues (Shift+P)"; id: bulkProjectBtn; text: "Project"; iconText: root.icon.down; onClicked: bulk.openBulkPicker("bulkProject", bulkProjectBtn) }
    Button { tooltipText: "Archive the selected issues (Ctrl+Shift+X)"; text: "Archive"; iconText: root.icon.archive; onClicked: bulk.archiveTargets() }
    Button { tooltipText: "Move the selected issues to Linear's trash (Ctrl+Backspace). Ctrl+Z undoes it."; text: "Delete"; iconText: root.icon.trash; foreground: root.urgent; onClicked: bulk.bulkDelete() }
    Button { text: "All"; tooltipText: "Select every visible card (Ctrl+A). X adds or removes one."; onClicked: bulk.selectAllVisible() }
    Button { iconText: root.icon.close; tooltipText: "Clear selection (Esc)"; onClicked: root.multi = [] }
  }
}
