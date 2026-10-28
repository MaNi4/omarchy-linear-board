import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Issues.js" as Issues

// Part of the Linear board (mani4.linear-board): one column of the board,
// a workflow state: its header (name, count, new issue) and its cards
// (ui/IssueCard.qml), with the drop marker while a card is dragged.
// Created by ui/BoardView.qml for each shown column.
Rectangle {
  id: colItem
  required property int index
  readonly property var ws: root.columns[index] || ({ id: "", name: "", color: "#888888", type: "" })
  readonly property var cards: root.visibleByColumn[index] || []
  readonly property int total: Issues.issuesIn(root.issues, ws.id).length
  readonly property bool dropHere: bulk.dragging && bulk.dropCol === index
  // The keyboard cursor in a column without cards: mark the column itself.
  readonly property bool cursorHere: root.cursorShown && !bulk.dragging && root.selCol === index && cards.length === 0

  radius: root.radius
  color: dropHere ? Util.alpha(root.accent, 0.08) : (cursorHere ? Util.alpha(root.accent, 0.06) : Util.alpha(root.fg, 0.03))
  border.width: cursorHere ? Math.max(1, Style.space(2)) : (dropHere ? 1 : 0)
  border.color: cursorHere ? root.accent : Util.alpha(root.accent, 0.5)

  function dropIndexAt(y) {
    var p = colItem.mapToItem(cardColumn, 0, y)
    for (var i = 0; i < cardRepeater.count; i++) {
      var it = cardRepeater.itemAt(i)
      if (it && p.y < it.y + it.height / 2) return i
    }
    return cardRepeater.count
  }

  function ensureCardVisible(i) {
    var it = cardRepeater.itemAt(i)
    if (!it) return
    if (it.y < cardFlick.contentY) cardFlick.contentY = it.y
    else if (it.y + it.height > cardFlick.contentY + cardFlick.height)
      cardFlick.contentY = it.y + it.height - cardFlick.height
  }

  // header
  Item {
    id: colHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.lg
    height: Style.spacing.controlHeight

    Dot { id: colDot; dotColor: colItem.ws.color; anchors.verticalCenter: parent.verticalCenter }
    Label {
      id: colName
      anchors.left: colDot.right
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - Style.space(90))
      text: colItem.ws.name
      font.bold: true
      font.pixelSize: Style.font.subtitle
    }
    Label {
      anchors.left: colName.right
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: colItem.cards.length === colItem.total ? String(colItem.total) : colItem.cards.length + "/" + colItem.total
      opacity: 0.5
    }
    MouseArea {
      anchors.fill: parent
      onDoubleClicked: pickers.openSettings("columns")
    }
    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.icon.plus
      tooltipText: "New issue in " + colItem.ws.name
      onClicked: issueOps.newIssue(colItem.index)
    }
  }

  Flickable {
    id: cardFlick
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: colHeader.bottom
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md
    anchors.topMargin: Style.spacing.md
    contentHeight: cardColumn.implicitHeight + Style.space(40)
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    interactive: !bulk.dragging

    MouseArea {
      width: cardFlick.width
      height: Math.max(cardFlick.height, cardFlick.contentHeight)
      onDoubleClicked: issueOps.newIssue(colItem.index)
    }

    Column {
      id: cardColumn
      width: cardFlick.width
      spacing: Style.spacing.md

      Repeater {
        id: cardRepeater
        model: colItem.cards.length

        delegate: IssueCard {
          column: colItem
          width: cardColumn.width
        }
      }

      Rectangle {
        visible: colItem.dropHere && bulk.dropIdx >= cardRepeater.count
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: root.accent
      }

      Chip {
        tip: "New issue in this column (C)"
        width: parent.width
        text: "Add issue"
        glyph: root.icon.plus
        opacity: 0.6
        color: "transparent"
        onClicked: issueOps.newIssue(colItem.index)
      }
    }
  }
}
