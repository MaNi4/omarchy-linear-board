import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One property of an issue as a pill in the editor (status, priority,
// labels…): its glyph or color dot and its value, dim when unset. A click
// opens the editor's property menu for it (PropMenu).
Rectangle {
  id: pill
  property string glyph: ""
  property color glyphColor: root.fg
  property color dotColor: "transparent"
  property bool showDot: false
  property string text: ""
  property bool unset: false          // shows the property's name dimmed, e.g. "Priority"
  property bool active: false         // its menu is open
  property bool wide: false           // fills its row (the sidebar), text left-aligned
  property var chips: []              // [{ name, color }]: several values, each with its own dot (labels)
  property string tip: ""
  signal clicked()

  readonly property bool hasChips: chips && chips.length > 0
  implicitWidth: (hasChips ? (wide ? chipFlow.implicitWidth : chipRow.implicitWidth) : pillRow.implicitWidth) + Style.spacing.lg * 2
  implicitHeight: Math.max(Style.space(30), (hasChips ? (wide ? chipFlow.implicitHeight : chipRow.implicitHeight) : pillRow.implicitHeight) + Style.spacing.sm * 2)
  radius: root.radius
  color: active ? Util.alpha(root.accent, 0.16) : (pillMouse.containsMouse ? Util.alpha(root.fg, 0.1) : (wide ? "transparent" : Util.alpha(root.fg, 0.05)))
  border.width: activeFocus ? Math.max(1, Style.space(2)) : (wide ? 0 : 1)
  border.color: activeFocus || active ? Util.alpha(root.accent, 0.8) : Util.alpha(root.fg, pillMouse.containsMouse ? 0.22 : 0.12)

  // Reachable with Tab; Enter or Space opens it.
  activeFocusOnTab: true
  Keys.onReturnPressed: function(event) { pill.clicked(); event.accepted = true }
  Keys.onEnterPressed: function(event) { pill.clicked(); event.accepted = true }
  Keys.onSpacePressed: function(event) { pill.clicked(); event.accepted = true }

  // Several values: every one with its color. One line in the pill row, wrapped in the sidebar.
  component ChipItem: Row {
    required property var modelData
    spacing: Style.spacing.xs
    Dot { dotColor: modelData.color || root.accent; width: Style.space(8); anchors.verticalCenter: parent.verticalCenter }
    Label { text: modelData.name; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
  }
  Row {
    id: chipRow
    visible: pill.hasChips && !pill.wide
    anchors.centerIn: parent
    spacing: Style.spacing.md
    Repeater { model: pill.hasChips && !pill.wide ? pill.chips : []; delegate: ChipItem {} }
  }
  Flow {
    id: chipFlow
    visible: pill.hasChips && pill.wide
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.md
    Repeater { model: pill.hasChips && pill.wide ? pill.chips : []; delegate: ChipItem {} }
  }

  Row {
    id: pillRow
    visible: !pill.hasChips
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: pill.wide ? parent.left : undefined
    anchors.leftMargin: pill.wide ? Style.spacing.md : 0
    anchors.horizontalCenter: pill.wide ? undefined : parent.horizontalCenter
    spacing: Style.spacing.sm
    Dot {
      visible: pill.showDot
      dotColor: pill.dotColor
      width: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      visible: !pill.showDot && pill.glyph !== ""
      text: pill.glyph
      color: pill.unset ? root.fg : pill.glyphColor
      opacity: pill.unset ? 0.45 : 1
      font.pixelSize: Style.font.bodySmall + 1
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      text: pill.text
      opacity: pill.unset ? 0.5 : 1
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      width: pill.wide ? Math.min(implicitWidth, pill.width - x - Style.spacing.md * 2) : implicitWidth
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: pillMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.clicked()
  }
  PanelToolTip {
    visible: pill.tip !== "" && pillMouse.containsMouse && !pill.active
    text: pill.tip
  }
}
