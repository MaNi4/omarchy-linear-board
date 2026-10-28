import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Linear.js" as Linear
import "../Dates.js" as Dates
import "../Issues.js" as Issues
import "../Recur.js" as Recur

// The issue editor's property menu: a small searchable list under a pill
// (status, priority, assignee, labels, project, milestone, cycle, estimate,
// due date, team, template, more). Type to filter, ↑ ↓ to choose, Enter to
// pick, Esc to close. Labels stay open so several can be toggled.
// ed.menu holds which menu is open ("" when closed).
Item {
  id: menu
  anchors.fill: parent
  visible: ed.menu !== ""
  z: 100

  property real menuX: 0
  property var returnFocus: null      // what had the keyboard before the menu opened
  property real menuY: 0
  property int cursor: 0
  property string query: ""

  function openFor(kind, anchor) {
    if (ed.menu === kind) { close(); return }
    var p = anchor.mapToItem(menu, 0, anchor.height + Style.spacing.xs)
    menu.menuX = Math.max(Style.spacing.md, Math.min(p.x, menu.width - box.width - Style.spacing.md))
    // Below the pill, or above it when there is no room; always inside the editor.
    var boxH = Style.space(340)
    var top = anchor.mapToItem(menu, 0, 0).y
    var want = menu.height - p.y - Style.spacing.md >= boxH ? p.y : top - Style.spacing.xs - boxH
    menu.menuY = Math.max(Style.spacing.md, Math.min(want, menu.height - boxH - Style.spacing.md))
    menu.query = ""
    menu.cursor = 0
    searchBox.text = ""
    menu.returnFocus = menu.Window.activeFocusItem
    ed.menu = kind
    var sel = menu.items.findIndex(function(i) { return i.selected })
    menu.cursor = Math.max(0, sel)
    Qt.callLater(function() { searchBox.forceActiveFocus(); list.positionViewAtIndex(menu.cursor, ListView.Contain) })
  }
  function close() {
    ed.menu = ""
    menu.query = ""
    // Give the keyboard back (the title, or the pill the menu came from).
    var back = menu.returnFocus
    menu.returnFocus = null
    Qt.callLater(function() {
      if (back && back.visible) back.forceActiveFocus()
      else if (root.dialog === "issue") editor.titleField.forceActiveFocus()
    })
  }

  function day(n) { return Dates.isoDate(Dates.addDays(new Date(), n)) }
  readonly property var titles: ({ status: "Status", priority: "Priority", assignee: "Assignee", labels: "Labels", project: "Project",
    milestone: "Milestone", cycle: "Cycle", estimate: "Estimate", due: "Due date", team: "Team", template: "Template", more: "More" })

  // [{ id, label, hint, dot, glyph, glyphColor, selected }] for the open menu, filtered by the query.
  readonly property var items: {
    var k = ed.menu, out = []
    if (!k) return out
    if (k === "status") out = ed.team.states.map(function(s) { return { id: s.id, label: s.name, dot: s.color, selected: s.id === ed.stateId } })
    else if (k === "priority") out = Linear.PRIORITIES.map(function(p) {
      return { id: String(p.value), label: p.label, glyph: p.short || "—", glyphColor: p.value === 1 ? root.urgent : (p.value === 0 ? root.fg : root.tint(p.color)), selected: p.value === ed.priority }
    })
    else if (k === "assignee") {
      var people = ed.team.members.slice()
      var cur = ed.orig && ed.orig.assignee
      if (cur && !people.some(function(m) { return m.id === cur.id })) people.push(cur)
      out = [{ id: "", label: "Unassigned", glyph: root.icon.unassigned, selected: ed.assigneeId === "" }].concat(people.map(function(m) {
        var me = !!(root.viewer && m.id === root.viewer.id)
        return { id: m.id, label: me ? "Me (" + m.name + ")" : m.name, glyph: root.icon.account, selected: m.id === ed.assigneeId }
      }))
    }
    else if (k === "labels") {
      out = ed.team.labels.map(function(l) { return { id: l.id, label: l.name, dot: l.color, selected: ed.labels.indexOf(l.id) >= 0 } })
      var q0 = menu.query.trim()
      if (q0 && !ed.team.labels.some(function(l) { return l.name.toLowerCase() === q0.toLowerCase() }))
        out.push({ id: "__new", label: "Create label “" + q0 + "”", glyph: root.icon.plus, keep: true })
    }
    else if (k === "project") out = [{ id: "", label: "No project", glyph: root.icon.close, selected: !ed.projectId }].concat(
      ed.team.projects.map(function(p) { return { id: p.id, label: p.name, dot: p.color, hint: root.codeFor(p.id), selected: p.id === ed.projectId } }))
    else if (k === "milestone") out = [{ id: "", label: "No milestone", glyph: root.icon.close, selected: !ed.milestoneValid }].concat(
      ed.milestones.map(function(m) { return { id: m.id, label: m.name, glyph: root.icon.flag, hint: m.targetDate, selected: m.id === ed.milestoneValid } }))
    else if (k === "cycle") out = [{ id: "", label: "No cycle", glyph: root.icon.close, selected: !ed.cycleId }].concat(
      ed.team.cycles.map(function(c) { return { id: c.id, label: Issues.cycleLabel(c), glyph: root.icon.cycle, hint: lists.shortDay(c.startsAt) + " – " + lists.shortDay(c.endsAt), selected: c.id === ed.cycleId } }))
    else if (k === "estimate") out = [{ id: "", label: "No estimate", glyph: root.icon.close, selected: ed.estimate === null }].concat(
      ed.team.estimateOptions.map(function(o) { return { id: String(o.value), label: o.label, glyph: root.icon.estimate, selected: o.value === ed.estimate } }))
    else if (k === "due") {
      var due = editor.dueField.text
      var monday = (8 - new Date().getDay()) % 7 || 7
      out = [{ id: menu.day(0), label: "Today", hint: menu.day(0) }, { id: menu.day(1), label: "Tomorrow", hint: menu.day(1) },
        { id: menu.day(monday), label: "Next Monday", hint: menu.day(monday) }, { id: menu.day(7), label: "In a week", hint: menu.day(7) },
        { id: menu.day(14), label: "In two weeks", hint: menu.day(14) }].map(function(o) { o.glyph = root.icon.calendar; o.selected = o.id === due; return o })
      if (due) out.push({ id: "", label: "No due date", glyph: root.icon.close })
      var typed = Dates.parseDate(menu.query)
      if (menu.query.trim() && typed) return [{ id: typed, label: "Due " + typed, glyph: root.icon.calendar, selected: typed === due }]
    }
    else if (k === "team") out = root.teams.map(function(t) { return { id: t.id, label: t.name, hint: t.key, glyph: root.icon.account, selected: t.id === ed.team.id } })
    else if (k === "template") out = editorOps.edTemplates.map(function(t) { return { id: t.id, label: t.name, glyph: root.icon.text, template: t } })
    else if (k === "more") {
      out = Recur.RECUR_KINDS.map(function(r) { return { id: "repeat:" + r.id, label: "Repeat: " + r.label.toLowerCase(), glyph: root.icon.repeat } })
      if (ed.issueId) out = Dates.REMINDER_OPTIONS.map(function(r) { return { id: "remind:" + r.id, label: "Remind me " + r.label.charAt(0).toLowerCase() + r.label.slice(1), glyph: root.icon.bell } }).concat(out)
      out.push({ id: "template", label: "Save as template", glyph: root.icon.text })
      if (ed.issueId) out.push({ id: "duplicate", label: "Duplicate", glyph: root.icon.plus })
    }
    var q = menu.query.trim().toLowerCase()
    if (q && k !== "due") out = out.filter(function(i) { return i.id === "__new" || i.label.toLowerCase().indexOf(q) >= 0 || String(i.hint || "").toLowerCase().indexOf(q) >= 0 })
    return out
  }

  function apply(item) {
    if (!item) return
    var k = ed.menu
    if (k === "status") ed.stateId = item.id
    else if (k === "priority") ed.priority = parseInt(item.id)
    else if (k === "assignee") ed.assigneeId = item.id
    else if (k === "labels") {
      if (item.id === "__new") {
        var name = menu.query.trim()
        workspace.addLabel(name, function(l) { workspace.toggleEdLabel(l.id) })
        searchBox.text = ""
      } else workspace.toggleEdLabel(item.id)
      return   // stays open: pick several
    }
    else if (k === "project") ed.projectId = item.id
    else if (k === "milestone") ed.milestoneId = item.id
    else if (k === "cycle") ed.cycleId = item.id
    else if (k === "estimate") ed.estimate = item.id === "" ? null : Number(item.id)
    else if (k === "due") { editor.dueField.text = item.id; ed.dueError = false }
    else if (k === "team") issueOps.setEdTeam(item.id)
    else if (k === "template") editorOps.applyTemplate(item.template)
    else if (k === "more") {
      menu.close()
      if (item.id.indexOf("repeat:") === 0) issueOps.makeRecurring(item.id.slice(7))
      else if (item.id.indexOf("remind:") === 0) issueOps.remindIssues([ed.issueId], item.id.slice(7))
      else if (item.id === "template") editorOps.saveAsTemplate()
      else if (item.id === "duplicate") editorOps.duplicateIssue()
      return
    }
    menu.close()
  }

  // A click outside closes it.
  MouseArea { anchors.fill: parent; onClicked: menu.close() }

  Rectangle {
    id: box
    x: menu.menuX
    y: menu.menuY
    width: Style.space(300)
    height: Math.min(Style.space(340), searchBox.height + list.contentHeight + Style.spacing.md * 3)
    radius: root.radius
    color: Qt.lighter(root.bg, 1.12)
    border.width: 1
    border.color: Util.alpha(root.fg, 0.25)
    MouseArea { anchors.fill: parent }

    QQC.TextField {
      id: searchBox
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.md
      placeholderText: ed.menu === "due" ? "Type a date, e.g. 2026-12-31…" : (ed.menu === "labels" ? "Find or create a label…" : (menu.titles[ed.menu] || "") + "…")
      color: root.fg
      placeholderTextColor: Util.alpha(root.fg, 0.4)
      selectionColor: Util.alpha(root.accent, 0.35)
      font.family: root.font
      font.pixelSize: Style.font.bodySmall
      leftPadding: Style.spacing.md
      background: Rectangle { radius: root.radius; color: Util.alpha(root.fg, 0.05) }
      onTextChanged: { menu.query = text; menu.cursor = 0 }
      Keys.onDownPressed: function(event) { menu.cursor = Math.min(menu.items.length - 1, menu.cursor + 1); list.positionViewAtIndex(menu.cursor, ListView.Contain); event.accepted = true }
      Keys.onUpPressed: function(event) { menu.cursor = Math.max(0, menu.cursor - 1); list.positionViewAtIndex(menu.cursor, ListView.Contain); event.accepted = true }
      Keys.onReturnPressed: function(event) { menu.apply(menu.items[menu.cursor]); event.accepted = true }
      Keys.onEnterPressed: function(event) { menu.apply(menu.items[menu.cursor]); event.accepted = true }
      Keys.onEscapePressed: function(event) { menu.close(); event.accepted = true }
      Keys.onTabPressed: function(event) { menu.close(); event.accepted = true }
    }

    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchBox.bottom
      anchors.bottom: parent.bottom
      anchors.margins: Style.spacing.md
      anchors.topMargin: Style.spacing.sm
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: menu.items
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: list.width
        height: Style.spacing.popupRowHeight + Style.space(2)
        radius: root.radius
        color: index === menu.cursor ? Util.alpha(root.accent, 0.16) : "transparent"
        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.right: check.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.md
          Item {
            width: Style.space(16)
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            Dot { visible: !!modelData.dot; dotColor: modelData.dot || "transparent"; anchors.centerIn: parent }
            Label {
              visible: !modelData.dot && !!modelData.glyph
              anchors.centerIn: parent
              text: modelData.glyph || ""
              color: modelData.glyphColor || root.fg
              opacity: modelData.glyphColor ? 1 : 0.6
              font.pixelSize: Style.font.bodySmall + 1
            }
          }
          Label { text: modelData.label; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          Label { visible: !!modelData.hint; text: modelData.hint || ""; opacity: 0.4; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        }
        Label {
          id: check
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          visible: !!modelData.selected
          text: root.icon.check
          color: root.accent
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse) menu.cursor = index
          onClicked: menu.apply(modelData)
        }
      }
    }
    Label {
      anchors.centerIn: list
      visible: menu.items.length === 0
      text: "Nothing matches"
      opacity: 0.45
      font.pixelSize: Style.font.caption
    }
  }
}
