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
// shortcut help (for the window it was opened from)
Rectangle {
  id: helpOverlay
  anchors.fill: parent
  z: 75
  visible: keyboard.helpContext !== ""
  color: Util.alpha(root.bg, 0.55)
  MouseArea { anchors.fill: parent; onClicked: keyboard.closeHelp() }

  Rectangle {
    id: helpBox
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), keyboard.helpContext === "board" ? Style.space(1000) : Style.space(600))
    height: Math.min(parent.height - Style.space(40), helpHead.height + helpFlow.implicitHeight + Style.spacing.panelPadding * 2 + Style.spacing.xl)
    radius: root.radius
    color: root.bg
    border.width: 1
    border.color: Util.alpha(root.accent, 0.5)
    MouseArea { anchors.fill: parent }

    RowLayout {
      id: helpHead
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      Label {
        text: "Help  ·  " + (keyboard.helpTitles[keyboard.helpContext] || "")
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }
      Label { text: "any key closes"; opacity: 0.4; font.pixelSize: Style.font.caption }
      Button { tooltipText: "Close (any key)"; iconText: root.icon.close; onClicked: keyboard.closeHelp() }
    }

    Flickable {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: helpHead.bottom
      anchors.bottom: parent.bottom
      anchors.margins: Style.spacing.panelPadding
      anchors.topMargin: Style.spacing.xl
      contentHeight: helpFlow.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      // Sections side by side when there is room.
      Flow {
        id: helpFlow
        width: parent.width
        spacing: Style.spacing.xxl
        readonly property int columns: width > Style.space(900) ? 3 : (width > Style.space(520) ? 2 : 1)
        readonly property real sectionWidth: Math.floor((width - spacing * (columns - 1)) / columns)

        Repeater {
          model: keyboard.helpContext ? (keyboard.helpSections[keyboard.helpContext] || []) : []
          delegate: Column {
            id: helpSection
            required property var modelData
            width: helpFlow.sectionWidth
            spacing: Style.spacing.sm
            SectionTitle { text: helpSection.modelData.title }
            Repeater {
              model: helpSection.modelData.rows
              delegate: Item {
                id: helpRow
                required property var modelData
                readonly property bool hasKeys: modelData[0].length > 0
                width: helpSection.width
                height: Math.max(helpKeys.implicitHeight, helpText.implicitHeight)
                Row {
                  id: helpKeys
                  spacing: Style.spacing.xs
                  Repeater {
                    model: helpRow.modelData[0]
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool isWord: modelData === "then" || modelData === "+" || modelData === "–"
                      width: keyLabel.implicitWidth + (isWord ? 0 : Style.spacing.md * 2)
                      height: keyLabel.implicitHeight + Style.space(4)
                      radius: Style.space(4)
                      color: isWord ? "transparent" : Util.alpha(root.fg, 0.08)
                      border.width: isWord ? 0 : 1
                      border.color: Util.alpha(root.fg, 0.22)
                      Label {
                        id: keyLabel
                        anchors.centerIn: parent
                        text: parent.modelData
                        font.pixelSize: Style.font.caption
                        font.bold: !parent.isWord
                        color: parent.isWord ? Util.alpha(root.fg, 0.5) : root.accent
                      }
                    }
                  }
                }
                Label {
                  id: helpText
                  x: helpRow.hasKeys ? Math.round(helpSection.width * 0.45) : 0
                  width: helpSection.width - x
                  text: helpRow.modelData[1]
                  opacity: helpRow.hasKeys ? 0.85 : 0.5
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  elide: Text.ElideNone
                }
              }
            }
          }
        }
      }
    }
  }
}
