import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Dates.js" as Dates
import "../Inbox.js" as Inbox

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// inbox
Rectangle {
  id: inboxDialog
  property alias inboxList: inboxList
  z: 62
  visible: root.dialog === "inbox"
  anchors.centerIn: parent
  width: Math.min(parent.width - Style.space(40), Style.space(860))
  height: Math.min(parent.height - Style.space(40), Style.space(680))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  MouseArea { anchors.fill: parent }

  RowLayout {
    id: inboxHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.sm
    Label {
      text: "Inbox" + (inboxCtl.filtered ? "  " + inboxCtl.matchingUnread + " unread here, " + inboxCtl.unreadCount + " in all"
        : (inboxCtl.unreadCount > 0 ? "  " + inboxCtl.unreadCount + " unread" : ""))
      Layout.fillWidth: true
      Layout.minimumWidth: Style.space(60)
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Chip { tip: "Unread only (A switches)"; text: "Unread"; tint: root.accent; selected: inboxCtl.unreadOnly; onClicked: { inboxCtl.unreadOnly = true; inboxCtl.clampInboxCursor() } }
    Chip { tip: "Read ones too (A switches)"; text: "All"; tint: root.accent; selected: !inboxCtl.unreadOnly; onClicked: { inboxCtl.unreadOnly = false; inboxCtl.clampInboxCursor() } }
    Button { iconText: root.icon.checkAll; text: inboxDialog.width < Style.space(640) ? "" : "Mark all read"; tooltipText: "Mark all read (Shift+A)"; onClicked: inboxCtl.markAllRead() }
    Button {
      iconText: root.icon.bell
      foreground: root.config.desktopNotify ? root.accent : Util.alpha(root.fg, 0.4)
      tooltipText: root.config.desktopNotify ? "Desktop notifications on: click to turn off" : "Desktop notifications off: click to turn on"
      onClicked: inboxCtl.toggleDesktopNotify()
    }
    Button { iconText: root.icon.help; tooltipText: "Shortcuts here (?)"; onClicked: keyboard.openHelp("inbox") }
    Button { tooltipText: "Close (Esc)"; iconText: root.icon.close; onClicked: pickers.closeDialog() }
  }

  Column {
    id: inboxFilters
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inboxHeader.bottom
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.lg
    spacing: Style.spacing.sm

    Repeater {
      // One row per filter: teams, projects, kinds. A row is shown
      // when the inbox has more than one choice for it.
      model: [
        { key: "teamId", all: "All teams", items: inboxCtl.facets.teams },
        { key: "projectId", all: "All projects", items: inboxCtl.facets.projects },
        { key: "category", all: "All kinds", items: inboxCtl.facets.categories }
      ]
      delegate: Flow {
        id: facetRow
        required property var modelData
        width: inboxFilters.width
        spacing: Style.spacing.sm
        // Teams also when the only team is not the board's own, so you can see where they come from.
        visible: modelData.items.length > 1 || inboxCtl.filter[modelData.key] !== ""
          || (modelData.key === "teamId" && modelData.items.length === 1 && !!root.team && modelData.items[0].id !== root.team.id)
        Chip {
          tip: "Do not filter by this"
          text: facetRow.modelData.all
          tint: root.accent
          selected: inboxCtl.filter[facetRow.modelData.key] === ""
          onClicked: { var p = {}; p[facetRow.modelData.key] = ""; inboxCtl.setInboxFilter(p) }
        }
        Repeater {
          model: facetRow.modelData.items
          delegate: Chip {
            required property var modelData
            text: modelData.label + (modelData.unread ? "  " + modelData.unread : "")
            showDot: !!modelData.color
            dotColor: modelData.color || "transparent"
            tint: root.accent
            selected: inboxCtl.filter[facetRow.modelData.key] === modelData.id
            onClicked: {
              var p = {}
              p[facetRow.modelData.key] = inboxCtl.filter[facetRow.modelData.key] === modelData.id ? "" : modelData.id
              inboxCtl.setInboxFilter(p)
            }
          }
        }
      }
    }
  }

  Label {
    anchors.centerIn: inboxList
    visible: inboxCtl.shown.length === 0
    text: inboxCtl.loading ? "Loading…" : (inboxCtl.unreadOnly ? "All caught up" : "No notifications")
    opacity: 0.5
  }

  ListView {
    id: inboxList
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inboxFilters.bottom
    anchors.bottom: inboxFooter.top
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.lg
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds
    model: inboxCtl.shown
    delegate: Rectangle {
      id: noteRow
      required property var modelData
      required property int index
      readonly property bool current: index === inboxCtl.cursor
      width: inboxList.width
      height: noteCol.implicitHeight + Style.spacing.lg * 2
      radius: root.radius
      color: current ? Util.alpha(root.fg, 0.1) : (noteMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")

      MouseArea {
        id: noteMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) inboxCtl.cursor = noteRow.index
        onClicked: inboxCtl.openNotification(noteRow.modelData)
      }

      Dot {
        id: unreadDot
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        y: Style.spacing.lg + Style.space(6)
        dotColor: noteRow.modelData.read ? "transparent" : root.accent
      }

      Column {
        id: noteCol
        anchors.left: unreadDot.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: noteActions.left
        anchors.rightMargin: Style.spacing.md
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.lg
        spacing: Style.spacing.xs
        Row {
          width: parent.width
          spacing: Style.spacing.md
          Label {
            id: noteIdent
            visible: text !== ""
            text: (noteRow.modelData.projectId && root.projectById(noteRow.modelData.projectId) ? root.codeFor(noteRow.modelData.projectId) + " · " : "") + noteRow.modelData.identifier
            opacity: 0.55
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Label {
            width: parent.width - (noteIdent.visible ? noteIdent.width + parent.spacing : 0) - noteAgo.width - parent.spacing
            text: noteRow.modelData.title
            font.bold: !noteRow.modelData.read
            opacity: noteRow.modelData.read ? 0.7 : 1
          }
          Label {
            id: noteAgo
            text: Dates.ago(noteRow.modelData.createdAt, new Date())
            opacity: 0.45
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: noteRow.modelData.subtitle
          opacity: 0.65
          font.pixelSize: Style.font.bodySmall
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: Inbox.inboxEventsText(noteRow.modelData)
          opacity: 0.5
          font.pixelSize: Style.font.caption
        }
        Flow {
          visible: inboxCtl.snoozeId === noteRow.modelData.id
          width: parent.width
          spacing: Style.spacing.sm
          Label { text: "Snooze until:"; opacity: 0.6; font.pixelSize: Style.font.caption }
          Repeater {
            model: Dates.SNOOZE_OPTIONS
            delegate: Chip {
              required property var modelData
              required property int index
              text: (index + 1) + "  " + modelData.label
              tint: root.accent
              onClicked: inboxCtl.snoozeNotification(noteRow.modelData, modelData.id)
            }
          }
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: noteRow.modelData.snippet
          opacity: 0.55
          font.pixelSize: Style.font.bodySmall
          font.italic: true
          wrapMode: Text.Wrap
          maximumLineCount: 2
        }
      }

      Row {
        id: noteActions
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        Button {
          iconText: noteRow.modelData.read ? root.icon.mail : root.icon.mailOpen
          tooltipText: noteRow.modelData.read ? "Mark unread (u)" : "Mark read (u)"
          onClicked: inboxCtl.setRead(noteRow.modelData, !noteRow.modelData.read)
        }
        Button {
          iconText: root.icon.clock
          tooltipText: "Snooze (s)"
          onClicked: inboxCtl.snoozeId = inboxCtl.snoozeId === noteRow.modelData.id ? "" : noteRow.modelData.id
        }
        Button {
          visible: noteRow.modelData.issueId !== ""
          iconText: root.icon.bellOff
          tooltipText: "Unsubscribe from this issue (Shift+U)"
          onClicked: inboxCtl.unsubscribeNotification(noteRow.modelData)
        }
        Button {
          iconText: root.icon.archive
          tooltipText: "Archive (x)"
          onClicked: inboxCtl.archiveNotification(noteRow.modelData)
        }
      }
    }
  }

  Label {
    id: inboxFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    opacity: 0.45
    font.pixelSize: Style.font.caption
    text: "? shortcuts"
  }
}
