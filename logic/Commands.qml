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

// The command palette (Ctrl+K).
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `commands`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: commands
  visible: false

  // ---- command palette (Ctrl+K) ----
  // Every action by name, plus issues by ID or title, plus "search Linear".
  property string paletteQuery: ""
  property int paletteCursor: 0
  function cmd(label, keys, run, keywords) { return { label: label, hint: keys || "", run: run, keywords: keywords || "" } }
  function paletteCommands() {
    var sel = root.selectedIssue
    var list = [
      commands.cmd("New issue", "C", function() { issueOps.newIssue(root.selCol) }, "create add"),
      commands.cmd("Search all of Linear…", "/ then Enter", function() { boardScreen.searchField.forceActiveFocus() }, "find"),
      commands.cmd("Inbox", "G then I", function() { inboxCtl.openInbox(inboxCtl.boardFilter) }, "notifications"),
      commands.cmd("My issues in all teams", "G then Y", lists.openMyIssues, "assigned mine"),
      commands.cmd("Cycle: current and others", "G then V", function() { lists.openCycles() }, "sprint active"),
      commands.cmd("Upcoming cycle", "G then W", function() { lists.openCycles("next") }, "sprint next"),
      commands.cmd("Add to the current cycle", "Ctrl+Shift+C", bulk.addToActiveCycle, "sprint active cycle"),
      commands.cmd("Project overview: status, milestones, updates", "G then U", function() { projectOps.openProject(root.config.projectId) }, "health target"),
      commands.cmd("Time report", "W", lists.openTimeReport, "hours timesheet"),
      commands.cmd("Undo the last change", "Ctrl+Z", undoer.undo, "revert back"),
      commands.cmd((root.config.layout || "board") === "list" ? "Show as board" : "Show as list", "Ctrl+B", workspace.toggleLayout, "layout view rows kanban"),
      commands.cmd("Sort and group", "V", function() { pickers.openPicker("view", boardScreen.viewButton.mapToItem(keyScope, 0, 0).x) }, "order"),
      commands.cmd("Filters", "F", function() { pickers.openPicker("filter", boardScreen.searchField.mapToItem(keyScope, 0, 0).x) }),
      commands.cmd("Clear all filters", "Alt+Shift+F", function() { workspace.clearFilters(true) }),
      commands.cmd("Clear filters, keep the assignee", "Shift+F", function() { workspace.clearFilters(false) }),
      commands.cmd("Filter by label…", "1 – 9", function() { pickers.openPicker("labelFilter", boardScreen.searchField.mapToItem(keyScope, 0, 0).x) }, "tags"),
      commands.cmd("Filter by priority…", "F", function() { pickers.openPicker("priority", boardScreen.priorityButton.mapToItem(keyScope, 0, 0).x) }, "urgent"),
      commands.cmd("Filter by assignee…", "O then U", function() { pickers.openPicker("assignee", boardScreen.assigneeButton.mapToItem(keyScope, 0, 0).x) }, "person user"),
      commands.cmd("Filter by text", "/", function() { boardScreen.searchField.forceActiveFocus() }, "search"),
      commands.cmd("Show every issue, done ones too (clean up)", "", root.showEverything, "all cleanup archive old completed done everything"),
      commands.cmd("All issues: no project, no filters", "G then E", function() { workspace.setProject(""); workspace.clearFilters(true) }, "everything"),
      commands.cmd("Go to the backlog column", "G then B", function() { bulk.jumpToType("backlog") }),
      commands.cmd("Go to the started column", "G then A", function() { bulk.jumpToType("started") }, "active in progress"),
      commands.cmd("Select every visible card", "Ctrl+A", bulk.selectAllVisible, "all bulk"),
      commands.cmd("Filter: current cycle", "", function() { workspace.setCycleFilter("current") }, "sprint"),
      commands.cmd("Filter by cycle…", "O then C", function() { pickers.openPicker("cycle", boardScreen.cycleButton.mapToItem(keyScope, 0, 0).x) }, "sprint"),
      commands.cmd("Only my issues on the board", "G then M", workspace.toggleMine, "mine"),
      commands.cmd("Switch team", "O then T", function() { pickers.openPicker("team", boardScreen.teamButton.mapToItem(keyScope, 0, 0).x) }),
      commands.cmd("Switch project", "O then P", function() { pickers.openPicker("project", boardScreen.projectButton.mapToItem(keyScope, 0, 0).x) }),
      commands.cmd("Recurring issues", "", function() { pickers.openSettings("recurring") }, "repeat schedule"),
      commands.cmd("Archived issues", "G then X", function() { lists.openArchived() }, "archive restore unarchive free plan limit cleanup"),
      commands.cmd("Trash: deleted issues", "G then X, Tab", function() { lists.openTrash() }, "deleted restore undelete bin"),
      commands.cmd("Cycle settings", "", function() { pickers.openSettings("team") }, "cycles length sprint upcoming turn on"),
      commands.cmd("Shared folder, export and import", "", function() { pickers.openSettings("data") }, "sync syncthing backup export import data"),
      commands.cmd("Settings: columns", "G then S", function() { pickers.openSettings("columns") }, "states workflow"),
      commands.cmd("Settings: labels", "", function() { pickers.openSettings("labels") }, "tags"),
      commands.cmd("Settings: projects (create, codes)", "G then P", function() { pickers.openSettings("projects") }, "new project"),
      commands.cmd("Settings: team (name, prefix, templates)", "", function() { pickers.openSettings("team") }, "templates"),
      commands.cmd("Settings: global keys", "", function() { pickers.openSettings("keys") }, "hotkey shortcut super"),
      commands.cmd("Settings: account (API key)", "", function() { pickers.openSettings("account") }, "disconnect"),
      commands.cmd("Archive old done issues…", "", function() { pickers.openSettings("team") }, "clean up limit"),
      commands.cmd("Refresh", "Ctrl+R", sync.refresh, "reload sync"),
      commands.cmd("Keyboard shortcuts", "?", function() { keyboard.openHelp("board") }, "help keys")
    ]
    if (lists.triageOn) list.splice(5, 0, commands.cmd("Triage (" + lists.triageIssues.length + ")", "G then T", lists.openTriage, "accept decline"))
    if (timeTracker.running) list.splice(1, 0, commands.cmd("Stop the timer on " + timeTracker.running.identifier, "Shift+T", timeTracker.stopTimer, "time"))
    if (sel) {
      var on = function(label, keys, run, kw) { return commands.cmd(sel.identifier + ": " + label, keys, run, kw) }
      var rest = list
      list = [
        on("Open", "Enter", function() { issueOps.editIssue(sel.id) }, "edit"),
        on("Status…", "S", function() { bulk.openActionPicker("bulkState") }, "move state"),
        on("Priority…", "P", function() { bulk.openActionPicker("bulkPriority") }),
        on("Assignee…", "A", function() { bulk.openActionPicker("bulkAssignee") }, "assign"),
        on("Assign to me", "I", bulk.assignToMe),
        on("Labels…", "T", function() { bulk.openActionPicker("bulkLabel") }, "tags"),
        on("Project…", "Shift+P", function() { bulk.openActionPicker("bulkProject") }),
        on("Milestone…", "Shift+M", function() { bulk.openActionPicker("bulkMilestone") }),
        on("Cycle…", "Shift+C", function() { bulk.openActionPicker("bulkCycle") }, "sprint"),
        on("Estimate…", "Shift+E", function() { bulk.openActionPicker("bulkEstimate") }, "points"),
        on("Due date…", "Ctrl+D", function() { bulk.openActionPicker("bulkDue") }, "deadline"),
        on("Remove the due date", "Ctrl+Shift+D", function() { bulk.applyBulk("bulkDue", "none") }, "deadline"),
        on("Add to the current cycle", "Ctrl+Shift+C", bulk.addToActiveCycle, "sprint"),
        on("Move to the next column", "Shift+L", function() { issueOps.shiftSelected(1, 0) }, "right status"),
        on("Move to the previous column", "Shift+H", function() { issueOps.shiftSelected(-1, 0) }, "left status"),
        on("Subscribe / unsubscribe", "Shift+S", bulk.subscribeSelected, "notifications follow"),
        on("Related to…", "M then R", function() { bulk.editForRelation("related") }, "relation link"),
        on("Blocks…", "M then X", function() { bulk.editForRelation("blocks") }, "relation blocking"),
        on("Blocked by…", "M then B", function() { bulk.editForRelation("blockedBy") }, "relation"),
        on("Remind me…", "Shift+R", function() { bulk.openActionPicker("bulkRemind") }, "reminder later"),
        on(timeTracker.isRunningOn(sel.id) ? "Stop the timer" : "Start the timer", "Shift+T", function() { timeTracker.toggleTimer(sel) }, "time track"),
        on("Comment", "Ctrl+M", function() { bulk.editForComment(sel.id) }),
        on("Rename", "R", function() { bulk.editForRename(sel.id) }, "title"),
        on("New sub-issue", "Ctrl+Shift+O", function() { issueOps.newIssue(root.selCol, { id: sel.id, identifier: sel.identifier, title: sel.title }) }, "child"),
        on("Copy ID", "Ctrl+.", function() { bulk.copyIssue(sel, "id") }),
        on("Copy git branch name", "Ctrl+Shift+.", function() { bulk.copyIssue(sel, "branch") }),
        on("Copy link", "Ctrl+Shift+,", function() { bulk.copyIssue(sel, "url") }, "url"),
        on("Copy Markdown link", "Ctrl+Alt+,", function() { bulk.copyIssue(sel, "markdown") }, "url md"),
        on("Copy title", "Ctrl+Alt+.", function() { bulk.copyIssue(sel, "title") }, "name"),
        on("Open in Linear", "Ctrl+O", function() { editorOps.openInLinear(sel.url) }, "browser"),
        on("Select / unselect", "X", function() { root.cursorShown = true; bulk.toggleMulti(sel.id) }, "bulk multi"),
        on("Archive", "Ctrl+Shift+X", bulk.archiveTargets),
        on("Delete", "Ctrl+Backspace", bulk.deleteTargets, "trash remove")
      ]
      // Right after "Open": the parent and a sub-issue, when there are any.
      var kid = root.issues.filter(function(i) { return i.parent && i.parent.id === sel.id })[0]
      if (kid) list.splice(1, 0, on("Open a sub-issue " + kid.identifier, "Ctrl+Shift+↓", function() { root.openIssueAnywhere(kid.id, "") }, "child down"))
      if (sel.parent) list.splice(1, 0, on("Open the parent " + sel.parent.identifier, "Ctrl+Shift+↑", function() { root.openIssueAnywhere(sel.parent.id, "") }, "up"))
      list = list.concat(rest)
    }
    return list
  }
  readonly property var paletteItems: {
    if (root.dialog !== "palette") return []
    var q = commands.paletteQuery.trim(), out = []
    var ref = Issues.parseIssueRef(q)
    if (ref) out.push(commands.cmd("Open " + ref, "Enter", function() { inboxCtl.openRef(ref) }))
    out = out.concat(Issues.paletteFilter(commands.paletteCommands(), q, q ? 12 : 60))
    if (q && !ref) {
      var lq = q.toLowerCase()
      var hits = root.issues.concat(root.extraIssues).filter(function(i) {
        return i.identifier.toLowerCase().indexOf(lq) === 0 || i.title.toLowerCase().indexOf(lq) >= 0
      }).slice(0, 8)
      hits.forEach(function(i) {
        out.push(commands.cmd(i.identifier + "  " + i.title, i.stateName, function() { root.openIssueAnywhere(i.id, i.url) }))
      })
      out.push(commands.cmd("Search Linear for “" + q + "”", "", function() { inboxCtl.searchLinear(q) }))
    }
    return out
  }
  function openPalette() {
    commands.paletteQuery = ""
    commands.paletteCursor = 0
    paletteDialog.paletteField.text = ""
    root.dialog = "palette"
    Qt.callLater(function() { paletteDialog.paletteField.forceActiveFocus() })
  }
  function runPalette(index) {
    var it = commands.paletteItems[index]
    pickers.closeDialog()
    if (it && it.run) Qt.callLater(it.run)
  }
}
