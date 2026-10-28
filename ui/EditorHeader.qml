import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Part of the Linear board (mani4.linear-board): the issue editor's top row.
// A new issue: team › project › New issue; a saved one: project code,
// identifier and copy buttons. Then template, open in Linear, the ⋯ menu,
// help and close. Created in ui/IssueEditor.qml as `edHeader`.
RowLayout {
  id: edHeader
  property alias teamPill: teamPill
  property alias projectPill: projectPill
  property alias morePill: morePill
  spacing: Style.spacing.md

  // New issue: team › New issue
  PropPill {
    id: teamPill
    visible: !editor.editing && root.teams.length > 1
    glyph: root.icon.down
    text: ed.team.name + (ed.teamLoading ? " …" : "")
    unset: false
    active: ed.menu === "team"
    tip: "Team  ·  Alt+Shift+T"
    onClicked: editor.propMenu.openFor("team", teamPill)
  }
  Label { visible: !editor.editing && root.teams.length > 1; text: "›"; opacity: 0.5 }
  PropPill {
    id: projectPill
    readonly property var spec: editor.pillSpec("project")
    visible: !editor.editing
    glyph: spec.glyph
    showDot: spec.dot !== ""
    dotColor: spec.dot || "transparent"
    text: spec.unset ? "No project" : spec.text
    unset: spec.unset
    active: ed.menu === "project"
    tip: editor.pillTip("project")
    onClicked: editor.propMenu.openFor("project", projectPill)
  }
  Label {
    visible: !editor.editing
    text: "›  " + (ed.parentIssue ? "New sub-issue of " + ed.parentIssue.identifier : "New issue" + (root.teams.length > 1 ? "" : " in " + ed.team.name))
    opacity: 0.7
  }
  // Saved issue: project code, identifier and copy buttons
  Rectangle {
    readonly property string code: editor.editing && ed.projectId && !ed.teamData ? root.codeFor(ed.projectId) : ""
    visible: code !== ""
    Layout.preferredWidth: codeLabel.implicitWidth + Style.spacing.md * 2
    Layout.preferredHeight: codeLabel.implicitHeight + Style.space(4)
    radius: root.radius
    color: Util.alpha(root.colorFor(ed.projectId), 0.22)
    Label { id: codeLabel; anchors.centerIn: parent; text: parent.code; font.bold: true; font.pixelSize: Style.font.caption; color: root.colorFor(ed.projectId) }
  }
  Label { visible: editor.editing; text: ed.identifier; font.bold: true; opacity: 0.8 }
  Button { visible: editor.editing; text: "ID"; tooltipText: "Copy the issue ID (Ctrl+.)"; onClicked: bulk.copyIssue(ed.orig, "id") }
  Button { visible: editor.editing; text: "Branch"; tooltipText: "Copy the git branch name (Ctrl+Shift+.)"; onClicked: bulk.copyIssue(ed.orig, "branch") }
  Button { visible: editor.editing; text: "Link"; tooltipText: "Copy the link (Ctrl+Shift+,); Markdown link: Ctrl+Alt+,"; onClicked: bulk.copyIssue(ed.orig, "url") }
  Item { Layout.fillWidth: true }
  PropPill {
    id: templatePill
    visible: !editor.editing && editorOps.edTemplates.length > 0
    glyph: root.icon.text
    text: "Template"
    unset: true
    active: ed.menu === "template"
    tip: "Fill in from a Linear issue template"
    onClicked: editor.propMenu.openFor("template", templatePill)
  }
  Button { visible: ed.url !== ""; iconText: root.icon.open; tooltipText: "Open in Linear (Ctrl+O)"; onClicked: editorOps.openInLinear(ed.url) }
  PropPill {
    id: morePill
    glyph: "⋯"
    text: ""
    unset: false
    active: ed.menu === "more"
    tip: "Remind me, repeat, save as template, duplicate (Shift+R)"
    onClicked: editor.propMenu.openFor("more", morePill)
  }
  Button { iconText: root.icon.help; tooltipText: "Shortcuts here (F1)"; onClicked: keyboard.openHelp("issue") }
  Button { iconText: root.icon.close; tooltipText: "Close without saving (Esc)"; onClicked: pickers.closeDialog() }
}
