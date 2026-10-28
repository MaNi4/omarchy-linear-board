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
import "../Time.js" as Time

// Part of the Linear board (mani4.linear-board): the board's top row. On the
// left the team, project and filter buttons and the search field (they wrap
// when the window is narrow); on the right sync state, timer, inbox,
// refresh, new issue, layout, commands, settings and help.
// Created in ui/BoardView.qml as `header`.
Item {
  id: header
  property alias teamButton: teamButton
  property alias projectButton: projectButton
  property alias assigneeButton: assigneeButton
  property alias priorityButton: priorityButton
  property alias cycleButton: cycleButton
  property alias viewButton: viewButton
  property alias searchField: searchField
  height: Math.max(headerLeft.implicitHeight, headerRight.implicitHeight)
  readonly property bool narrow: width < Style.space(1100)

  Flow {
    id: headerLeft
    anchors.rightMargin: Style.spacing.lg
    spacing: Style.spacing.lg

    Chip {
      id: teamButton
      text: root.team ? root.team.name : (root.teams.length ? "Choose team" : "Loading teams…")
      glyph: root.icon.down
      strong: true
      tint: root.accent
      fontSize: Style.font.title
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "Team (O then T)"
      onClicked: pickers.openPicker("team", teamButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      tip: "Project on the board (O then P)"
      id: projectButton
      text: root.currentProject ? root.currentProject.name : "All issues"
      glyph: root.icon.down
      showDot: !!root.currentProject
      dotColor: root.currentProject ? root.currentProject.color : "transparent"
      fontSize: Style.font.subtitle
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      onClicked: pickers.openPicker("project", projectButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      id: assigneeButton
      text: workspace.assigneeFilterLabel
      glyph: root.config.assignee === "none" ? root.icon.unassigned : root.icon.account
      selected: !!root.config.assignee
      tint: root.accent
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "Assignee filter (O then U; G then M: mine)"
      onClicked: pickers.openPicker("assignee", assigneeButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      id: priorityButton
      text: root.priorityFilter < 0 ? "Any priority" : Linear.priority(root.priorityFilter).label
      glyph: root.icon.filter
      selected: root.priorityFilter >= 0
      tint: root.priorityFilter === 1 ? root.urgent : root.accent
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "Priority filter (F)"
      onClicked: pickers.openPicker("priority", priorityButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      id: cycleButton
      visible: root.cycles.length > 0 || root.cycleFilter !== ""
      text: root.cycleFilterLabel
      glyph: root.icon.cycle
      selected: root.cycleFilter !== ""
      tint: root.accent
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "Cycle filter (O then C; G then V shows the cycle)"
      onClicked: pickers.openPicker("cycle", cycleButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      id: viewButton
      text: {
        var s = (root.config.sort || "manual"), g = (root.config.group || "none")
        var parts = []
        if (s !== "manual") parts.push(Issues.SORTS.filter(function(o) { return o.id === s })[0].label)
        if (g !== "none") parts.push("by " + Issues.GROUPS.filter(function(o) { return o.id === g })[0].label.toLowerCase())
        return parts.length ? parts.join(", ") : "View"
      }
      glyph: root.icon.down
      selected: (root.config.sort || "manual") !== "manual" || (root.config.group || "none") !== "none"
      tint: root.accent
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "Layout, sort and group (v)"
      onClicked: pickers.openPicker("view", viewButton.mapToItem(keyScope, 0, 0).x)
    }
    Chip {
      visible: lists.triageOn
      text: "Triage " + lists.triageIssues.length
      glyph: root.icon.inbox
      selected: lists.triageIssues.length > 0
      tint: root.tint("orange")
      implicitHeight: Style.spacing.controlHeight + Style.space(4)
      tip: "New issues waiting to be accepted (G then T)"
      onClicked: lists.openTriage()
    }

    TextField {
      id: searchField
      width: Math.min(Style.space(280), headerLeft.width)
      placeholderText: root.icon.search + "  Filter board · an issue ID or Enter: search Linear"
      onTextChanged: { root.query = text; root.clampSelection() }
      // Typing filters the cards on the board; Enter also looks through
      // every issue of the team in Linear (old done ones, other projects).
      Keys.onReturnPressed: function(event) {
        if (text.trim()) inboxCtl.searchLinear(text)
        else keyScope.forceActiveFocus()
        event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (text.trim()) inboxCtl.searchLinear(text)
        else keyScope.forceActiveFocus()
        event.accepted = true
      }
      Keys.onDownPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
      Keys.onEscapePressed: function(event) { text = ""; keyScope.forceActiveFocus(); event.accepted = true }
    }

  }

  Row {
    id: headerRight
    spacing: Style.spacing.lg

    Label {
      visible: !header.narrow || sync.outbox.length > 0
      text: sync.outbox.length ? "Offline · " + sync.outbox.length + " waiting"
        : (root.pending > 0 || root.loadingTeam ? "Syncing…" : (root.syncedAt ? "Synced " + root.syncedAt : ""))
      color: sync.outbox.length ? root.urgent : root.fg
      opacity: 0.5
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
    Button {
      iconText: timeTracker.running ? root.icon.stop : root.icon.timer
      text: timeTracker.running ? timeTracker.running.identifier + "  " + Time.formatClock(timeTracker.runningSeconds) : ""
      foreground: timeTracker.running ? root.accent : root.fg
      tooltipText: timeTracker.running ? "Stop the timer on " + timeTracker.running.identifier + " (Shift+T). Time report: W" : "Time report (W)"
      onClicked: timeTracker.running ? timeTracker.stopTimer() : lists.openTimeReport()
    }
    Button {
      iconText: root.icon.inbox
      text: inboxCtl.boardUnread > 0 ? String(inboxCtl.boardUnread) : ""
      foreground: inboxCtl.boardUnread > 0 ? root.accent : root.fg
      tooltipText: (inboxCtl.boardUnread > 0 ? inboxCtl.boardUnread + " unread" : "Nothing unread")
        + (root.currentProject ? " in " + root.currentProject.name : " in Linear inbox") + " (G then I)"
      onClicked: inboxCtl.openInbox(inboxCtl.boardFilter)
    }
    Button {
      iconText: root.icon.refresh
      tooltipText: (root.syncedAt ? "Synced " + root.syncedAt + ". " : "") + "Refresh (Ctrl+R)"
      onClicked: sync.refresh()
    }
    Button {
      text: header.narrow ? "" : "New issue"
      iconText: root.icon.plus
      tooltipText: "New issue (C)"
      bordered: true
      selected: true
      onClicked: issueOps.newIssue(root.selCol)
    }
    Button {
      iconText: (root.config.layout || "board") === "list" ? root.icon.board : root.icon.list
      tooltipText: (root.config.layout || "board") === "list" ? "Show as board (Ctrl+B)" : "Show as list (Ctrl+B)"
      onClicked: workspace.toggleLayout()
    }
    Button { iconText: root.icon.console; tooltipText: "Command palette (Ctrl+K)"; onClicked: commands.openPalette() }
    Button { iconText: root.icon.cog; tooltipText: "Settings (G then S)"; onClicked: pickers.openSettings("columns") }
    Button { iconText: root.icon.help; tooltipText: "Shortcuts (?)"; onClicked: keyboard.openHelp("board") }
  }
}
