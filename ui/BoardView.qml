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
// ================= board =================
Item {
  id: boardScreen
  property alias assigneeButton: header.assigneeButton
  property alias boardFlick: boardFlick
  property alias colRepeater: colRepeater
  property alias cycleButton: header.cycleButton
  property alias footer: footer
  property alias header: header
  property alias listFlick: listFlick
  property alias listGroups: listGroups
  property alias priorityButton: header.priorityButton
  property alias projectButton: header.projectButton
  property alias searchField: header.searchField
  property alias teamButton: header.teamButton
  property alias viewButton: header.viewButton
  anchors.fill: parent
  visible: root.mode === "board"

  // ---- header ----
  BoardHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
  }

  // ---- label filter ----
  Flow {
    id: filterRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    spacing: Style.spacing.sm
    visible: root.labels.length > 0 || root.anyFilter
    height: visible ? implicitHeight : 0

    Repeater {
      model: root.labels.length
      delegate: Chip {
        required property int index
        readonly property var label: root.labels[index]
        text: label ? label.name : ""
        showDot: true
        dotColor: label ? label.color : "transparent"
        tint: label ? label.color : root.fg
        selected: label ? root.labelFilter.indexOf(label.id) >= 0 : false
        onClicked: workspace.toggleLabelFilter(label.id)
      }
    }
    Chip {
      tip: "Search every team in Linear, old done issues too (Enter in the search field)"
      visible: root.query.trim() !== ""
      // An issue ID: what Linear has under it (archived ones too).
      text: inboxCtl.refChipText || ("Not here? Search all teams in Linear for “" + root.query.trim() + "”  (Enter)")
      glyph: root.icon.search
      tint: root.accent
      strong: true
      onClicked: inboxCtl.searchLinear(root.query)
    }
    Chip {
      tip: "Clear all filters (Alt+Shift+F). Shift+F keeps the assignee."
      visible: root.anyFilter
      text: "Clear filters"
      glyph: root.icon.close
      onClicked: workspace.clearFilters(true)
    }
  }

  // ---- columns ----
  Flickable {
    id: boardFlick
    visible: !root.listLayout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterRow.bottom
    anchors.bottom: footer.top
    anchors.topMargin: Style.spacing.xxl
    anchors.bottomMargin: Style.spacing.lg
    contentWidth: boardRow.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    interactive: !bulk.dragging

    readonly property int columnWidth: {
      var n = Math.max(1, root.columns.length)
      var w = (width - root.gap * (n - 1)) / n
      return Math.max(Style.space(240), Math.min(Style.space(380), Math.floor(w)))
    }

    Row {
      id: boardRow
      height: boardFlick.height
      spacing: root.gap

      Repeater {
        id: colRepeater
        model: root.columns.length

        delegate: BoardColumn {
          width: boardFlick.columnWidth
          height: boardRow.height
        }
      }
    }
  }


  // ---- list layout (Ctrl+B): one row per issue, grouped by column ----
  Flickable {
    id: listFlick
    visible: root.listLayout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterRow.bottom
    anchors.bottom: footer.top
    anchors.topMargin: Style.spacing.xxl
    anchors.bottomMargin: Style.spacing.lg
    contentHeight: listColumn.implicitHeight + Style.space(60)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: listColumn
      width: listFlick.width
      spacing: Style.spacing.lg

      Repeater {
        id: listGroups
        model: root.listLayout ? root.columns.length : 0
        delegate: ListGroup { width: listColumn.width }
      }
    }
  }

  Label {
    anchors.centerIn: boardFlick
    visible: root.columns.length === 0
    text: root.loadingTeam || root.pending > 0 ? "Loading board…" : (root.team ? "All columns are hidden. Open settings (,) to show some." : "Choose a team")
    opacity: 0.6
  }

  // ---- footer ----
  Item {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(20)

    Label {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      opacity: 0.45
      font.pixelSize: Style.font.caption
      text: "C new issue  ·  X select  ·  Ctrl+K commands  ·  Ctrl+Z undo  ·  ? shortcuts"
    }

  }
}
