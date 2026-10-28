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
// search results
Rectangle {
  id: issueListDialog
  property alias searchList: searchList
  property alias binField: binField
  z: 62
  visible: root.dialog === "search"
  anchors.centerIn: parent
  width: Math.min(parent.width - Style.space(40), Style.space(760))
  height: Math.min(parent.height - Style.space(40), Style.space(620))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  MouseArea { anchors.fill: parent }

  RowLayout {
    id: searchHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
    Button {
      visible: lists.listMode === "cycle"
      iconText: "‹"
      enabled: lists.allCycles.length > 0 && lists.allCycles[0].id !== lists.cycleViewId
      tooltipText: "Earlier cycle (H)"
      onClicked: lists.stepCycle(-1)
    }
    Label {
      text: {
        var n = lists.searchResults.length
        if (lists.listMode === "mine") return "My issues in all teams" + (lists.searchLoading ? "" : "  ·  " + n)
        if (lists.listMode === "triage") return "Triage  ·  " + n + " waiting"
        if (lists.listMode === "archived") return "Archived  ·  " + (lists.searchLoading ? "" : n + " in " + (root.team ? root.team.name : "the team"))
        if (lists.listMode === "trash") return "Trash  ·  " + (lists.searchLoading ? "" : n + " deleted in the last " + Linear.TRASH_DAYS + " days")
        if (lists.listMode === "cycle") {
          var c = lists.cycleView
          if (!c) return lists.searchLoading ? "Cycles" : "This team has no cycles"
          return (c.name || "Cycle " + c.number) + (c.isActive ? " (current)" : "") + "  ·  " + lists.shortDay(c.startsAt) + " – " + lists.shortDay(c.endsAt)
        }
        return "Search in Linear: “" + lists.searchTerm + "” in all teams" +
          (lists.searchLoading ? "" : "  ·  " + n + (n === 50 ? "+" : "") + " found")
      }
      font.pixelSize: Style.font.title
      font.bold: true
      Layout.fillWidth: true
    }
    Button {
      tooltipText: "Settings → Team → Cycles"
      visible: lists.listMode === "cycle" && !lists.cycleView && !lists.searchLoading
      text: "Turn cycles on…"
      bordered: true
      onClicked: pickers.openSettings("team")
    }
    Button {
      visible: lists.listMode === "cycle" && !!lists.cycleView
      text: lists.cycleEditing ? "Close" : "Edit"
      tooltipText: "Name, dates, start today, archive (E)"
      onClicked: lists.cycleEditing = !lists.cycleEditing
    }
    Button {
      visible: lists.listMode === "cycle"
      iconText: "›"
      enabled: lists.allCycles.length > 0 && lists.allCycles[lists.allCycles.length - 1].id !== lists.cycleViewId
      tooltipText: "Later cycle (L)"
      onClicked: lists.stepCycle(1)
    }
    Button { iconText: root.icon.help; tooltipText: "Shortcuts here (?)"; onClicked: keyboard.openHelp("search") }
    Button { tooltipText: "Close (Esc)"; iconText: root.icon.close; onClicked: pickers.closeDialog() }
  }
  Label {
    anchors.centerIn: searchList
    visible: lists.searchResults.length === 0
    text: lists.searchLoading ? "Loading…" : ({ mine: "Nothing assigned to you is open", triage: "Triage is empty", trash: "The trash is empty", archived: lists.binQuery ? "Nothing archived matches “" + lists.binQuery + "”" : "Nothing archived in this team", cycle: lists.cycleView ? "No issues in this cycle" : "Turn them on in Settings → Team: Linear then makes them by itself" }[lists.listMode] || "Nothing found")
    opacity: 0.5
  }
  // Archived and trash: filter, switch between them, act on several at once.
  RowLayout {
    id: binBar
    visible: lists.isBin
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: searchHeader.bottom
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.topMargin: visible ? Style.spacing.lg : 0
    height: visible ? implicitHeight : 0
    spacing: Style.spacing.sm
    TextField {
      id: binField
      visible: lists.isBin
      Layout.fillWidth: true
      placeholderText: root.icon.search + "  ID or title  (/)"
      onTextChanged: if (text !== lists.binQuery) lists.setBinQuery(text)
      // Enter or arrows: back to the list keys (J, K, X, R…); Esc clears the filter.
      Keys.onReturnPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
      Keys.onDownPressed: function(event) { keyScope.forceActiveFocus(); lists.searchCursor = Math.min(lists.searchResults.length - 1, lists.searchCursor + 1); event.accepted = true }
      Keys.onEscapePressed: function(event) { text = ""; keyScope.forceActiveFocus(); event.accepted = true }
    }
    Chip { visible: lists.isBin; text: "Archived"; tint: root.accent; selected: lists.listMode === "archived"; tip: "Archived issues (Tab switches)"; onClicked: if (lists.listMode !== "archived") lists.openArchived() }
    Chip { visible: lists.isBin; text: "Trash"; tint: root.accent; selected: lists.listMode === "trash"; tip: "Deleted issues, kept 30 days (Tab switches)"; onClicked: if (lists.listMode !== "trash") lists.openTrash() }
    Button {
      visible: lists.isBin && lists.searchResults.length > 0
      text: lists.binPicked.length === lists.searchResults.length ? "Pick none" : "Pick all"
      tooltipText: "Pick every issue in the list (Ctrl+A); X or Ctrl+click picks one"
      onClicked: lists.pickAllBin()
    }
    Button {
      visible: lists.isBin && lists.binPicked.length > 0
      text: "Restore " + lists.binPicked.length
      iconText: root.icon.check
      bordered: true
      tooltipText: "Restore the picked issues (R)"
      onClicked: lists.restoreTrashed(null, true)
    }
    Button {
      visible: lists.listMode === "archived" && lists.binPicked.length > 0
      text: "Delete " + lists.binPicked.length
      foreground: root.urgent
      tooltipText: "Move the picked issues to the trash (30 days, can be restored) (Delete)"
      onClicked: lists.trashArchived(null, true)
    }
    Button {
      visible: lists.listMode === "trash" && lists.binPicked.length > 0
      text: "Delete " + lists.binPicked.length + " for good"
      foreground: root.urgent
      tooltipText: "Delete the picked issues for good; cannot be undone, workspace admins only (Delete)"
      onClicked: lists.deleteForever(null, true)
    }
  }

  // Editing the cycle shown: name, dates, description, start today, archive.
  Column {
    id: cycleEdit
    readonly property var cycle: lists.cycleView
    visible: lists.listMode === "cycle" && !!cycle && lists.cycleEditing
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: binBar.bottom
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.topMargin: visible ? Style.spacing.lg : 0
    height: visible ? implicitHeight : 0
    spacing: Style.spacing.sm
    onVisibleChanged: if (visible && cycle) {
      cycleNameField.text = cycle.name
      cycleStartField.text = Dates.isoDate(new Date(cycle.startsAt))
      cycleEndField.text = Dates.isoDate(new Date(cycle.endsAt))
      cycleDescField.text = cycle.description
      cycleNameField.forceActiveFocus()
    }
    function save() { lists.saveCycle(cycleNameField.text, cycleStartField.text, cycleEndField.text, cycleDescField.text) }
    function cancel() { lists.cycleEditing = false; keyScope.forceActiveFocus() }
    RowLayout {
      width: parent.width
      spacing: Style.spacing.sm
      TextField {
        id: cycleNameField
        Layout.fillWidth: true
        placeholderText: cycleEdit.cycle ? "Name (empty: Cycle " + cycleEdit.cycle.number + ")" : "Name"
        Keys.onReturnPressed: function(event) { cycleEdit.save(); event.accepted = true }
        Keys.onEscapePressed: function(event) { cycleEdit.cancel(); event.accepted = true }
      }
      TextField {
        id: cycleStartField
        Layout.preferredWidth: Style.space(120)
        placeholderText: "Starts"
        Keys.onReturnPressed: function(event) { cycleEdit.save(); event.accepted = true }
        Keys.onEscapePressed: function(event) { cycleEdit.cancel(); event.accepted = true }
      }
      Label { text: "–" }
      TextField {
        id: cycleEndField
        Layout.preferredWidth: Style.space(120)
        placeholderText: "Ends"
        Keys.onReturnPressed: function(event) { cycleEdit.save(); event.accepted = true }
        Keys.onEscapePressed: function(event) { cycleEdit.cancel(); event.accepted = true }
      }
    }
    TextField {
      id: cycleDescField
      width: parent.width
      placeholderText: "Description (optional)"
      Keys.onReturnPressed: function(event) { cycleEdit.save(); event.accepted = true }
      Keys.onEscapePressed: function(event) { cycleEdit.cancel(); event.accepted = true }
    }
    RowLayout {
      width: parent.width
      spacing: Style.spacing.sm
      Button { tooltipText: "Save (Enter)"; text: "Save"; iconText: root.icon.check; bordered: true; onClicked: cycleEdit.save() }
      Button { tooltipText: "Stop editing (Esc)"; text: "Cancel"; onClicked: cycleEdit.cancel() }
      Button {
        visible: !!cycleEdit.cycle && cycleEdit.cycle.isNext
        text: "Start today"
        iconText: root.icon.play
        tooltipText: "Start this upcoming cycle now; the current one ends"
        onClicked: lists.startCycleToday()
      }
      Item { Layout.fillWidth: true }
      Button { text: "Settings…"; iconText: root.icon.cog; tooltipText: "Cycle length, start day, how many ahead (Settings → Team)"; onClicked: pickers.openSettings("team") }
      Button { tooltipText: "Archive this cycle; its issues leave it"; text: "Archive"; iconText: root.icon.archive; foreground: root.urgent; onClicked: lists.archiveCycle() }
    }
    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      opacity: 0.5
      font.pixelSize: Style.font.caption
      text: "Dates like 2026-11-02 or 2.11.2026. Linear makes new cycles itself from the team's cycle settings; creating one by hand is not in its API."
    }
  }
  // Cycle progress: done / started / not started.
  Column {
    id: cycleBar
    visible: lists.listMode === "cycle" && !!lists.cycleView && lists.searchResults.length > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: cycleEdit.bottom
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.topMargin: visible ? Style.spacing.lg : 0
    height: visible ? implicitHeight : 0
    spacing: Style.spacing.sm
    Label {
      visible: !!lists.cycleView && lists.cycleView.description !== "" && !lists.cycleEditing
      width: parent.width
      text: lists.cycleView ? lists.cycleView.description : ""
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      font.pixelSize: Style.font.bodySmall
    }
    Rectangle {
      width: parent.width
      height: Style.space(6)
      radius: height / 2
      color: Util.alpha(root.fg, 0.1)
      Row {
        anchors.fill: parent
        Rectangle { width: parent.width * lists.listStats.done / Math.max(1, lists.listStats.total); height: parent.height; radius: height / 2; color: root.tint("green") }
        Rectangle { width: parent.width * lists.listStats.started / Math.max(1, lists.listStats.total); height: parent.height; color: root.tint("yellow") }
      }
    }
    Label {
      text: lists.listStats.percent + "% done  ·  " + lists.listStats.done + " done, " + lists.listStats.started + " in progress, " + lists.listStats.todo + " not started"
      opacity: 0.6
      font.pixelSize: Style.font.caption
    }
  }
  ListView {
    id: searchList
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: cycleBar.bottom
    anchors.bottom: searchFooter.top
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.xl
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds
    model: lists.searchResults
    delegate: Rectangle {
      id: resRow
      required property var modelData
      required property int index
      readonly property bool otherTeam: !!(root.team && modelData.teamId && modelData.teamId !== root.team.id)
      readonly property bool picked: lists.isBin && lists.isBinPicked(modelData.id)
      width: searchList.width
      height: resContent.implicitHeight + Style.spacing.lg * 2
      radius: root.radius
      color: resRow.picked ? Util.alpha(root.accent, index === lists.searchCursor ? 0.24 : 0.14)
        : (index === lists.searchCursor ? Util.alpha(root.fg, 0.1) : (resMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent"))
      border.width: resRow.picked ? 1 : 0
      border.color: Util.alpha(root.accent, 0.6)
      MouseArea {
        id: resMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) lists.searchCursor = resRow.index
        onClicked: function(mouse) {
          if (lists.isBin && (mouse.modifiers & Qt.ControlModifier)) lists.toggleBinPick(resRow.modelData)
          else if (lists.isBin) lists.openBinResult(resRow.modelData)
          else lists.openSearchResult(resRow.modelData)
        }
      }
      Row {
        id: resContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.md
        Label { visible: lists.isBin; text: resRow.picked ? "☑" : "☐"; color: resRow.picked ? root.accent : root.fg; opacity: resRow.picked ? 1 : 0.4; anchors.verticalCenter: parent.verticalCenter
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lists.toggleBinPick(resRow.modelData) } }
        Dot { dotColor: resRow.modelData.stateColor || "#888888"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: resRow.modelData.identifier; opacity: 0.55; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        Label {
          text: resRow.modelData.title
          width: Math.max(0, resContent.width - x - resProject.width - resState.implicitWidth - Style.spacing.md * 2
            - (lists.listMode === "triage" ? Style.space(190) : 0) - (lists.isBin ? Style.space(240) : 0))
          anchors.verticalCenter: parent.verticalCenter
        }
        // The project comes first: it tells most about where the issue belongs.
        Row {
          id: resProject
          visible: resRow.modelData.projectName !== ""
          width: visible ? implicitWidth : 0
          spacing: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          Dot { dotColor: resRow.modelData.projectColor || root.accent; width: Style.space(8); anchors.verticalCenter: parent.verticalCenter }
          Label { text: resRow.modelData.projectName; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        }
        Label {
          id: resState
          text: lists.listMode === "archived"
            ? "archived " + lists.shortDay(resRow.modelData.archivedAt) + "  ·  " + resRow.modelData.stateName
            : lists.listMode === "trash"
            ? "deleted " + lists.shortDay(resRow.modelData.deletedAt) + "  ·  gone " + lists.shortDay(resRow.modelData.purgeAt)
            : [resRow.modelData.teamName, resRow.modelData.stateName, resRow.modelData.assignee ? resRow.modelData.assignee.name : ""]
              .filter(function(x) { return x }).join("  ·  ")
          opacity: 0.5
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Button {
          visible: lists.listMode === "triage"
          text: "Accept"
          tooltipText: "Accept into the backlog (A)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: lists.triageAccept(resRow.modelData)
        }
        Button {
          visible: lists.isBin
          text: "Restore"
          tooltipText: lists.listMode === "archived" ? "Back on the board; counts toward the Free plan again (R)" : "Back where it was (R)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: lists.restoreTrashed(resRow.modelData)
        }
        Button {
          visible: lists.listMode === "archived"
          text: "Delete"
          foreground: root.urgent
          tooltipText: "To Linear's trash for 30 days, then gone (Delete)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: lists.trashArchived(resRow.modelData)
        }
        Button {
          visible: lists.listMode === "trash"
          text: "Delete for good"
          foreground: root.urgent
          tooltipText: "Cannot be undone; workspace admins only (Delete)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: lists.deleteForever(resRow.modelData)
        }
        Button {
          visible: lists.listMode === "triage"
          text: "Decline"
          foreground: root.urgent
          tooltipText: "Decline: cancel it (D)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: lists.triageDecline(resRow.modelData)
        }
      }
    }
  }
  Label {
    id: searchFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    opacity: 0.45
    font.pixelSize: Style.font.caption
    text: ({
      mine: "Open issues assigned to you in every team; another team's issue switches the board to it  ·  ? shortcuts",
      cycle: "H / L earlier or later cycle  ·  E edit the cycle  ·  Enter open  ·  ? shortcuts",
      archived: (lists.usageText ? lists.usageText + "\n" : "") + "Linear keeps archived issues for good  ·  Tab trash  ·  X pick  ·  Ctrl+A all  ·  R restore  ·  Delete to the trash  ·  Enter open in Linear",
      trash: (lists.usageText ? lists.usageText + "\n" : "") + "Deleted issues stay " + Linear.TRASH_DAYS + " days  ·  Tab archived  ·  X pick  ·  Ctrl+A all  ·  R restore  ·  Delete delete for good  ·  Enter open in Linear",
      triage: "A accept into the backlog  ·  D decline  ·  Enter open  ·  ? shortcuts"
    }[lists.listMode]) || "All your teams, old done issues too; another team's issue switches the board to it  ·  ? shortcuts"
  }
}
