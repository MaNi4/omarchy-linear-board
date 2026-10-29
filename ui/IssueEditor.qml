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
import "../Issues.js" as Issues
import "../Markdown.js" as Markdown
import "../Recur.js" as Recur

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// The issue editor, laid out like Linear: a new issue is a title, a
// description and a row of property pills; a saved issue has its text,
// sub-issues, relations, links (EditorLinks) and comments (EditorActivity)
// on the left and its properties, time and actions in a sidebar
// (EditorSidebar). The top row is EditorHeader. Each pill opens a small searchable menu
// (PropMenu). A saved issue saves each change at once (logic/EditorOps.qml, saveChanges).
Rectangle {
  id: editor
  property alias commentField: activity.commentField
  property alias descField: descField
  property alias dueField: dueField
  property alias edTimeDate: sidebar.edTimeDate
  property alias edTimeField: sidebar.edTimeField
  property alias edTimeNote: sidebar.edTimeNote
  property alias editorFlick: editorFlick
  property alias linkField: links.linkField
  property alias newLabelField: newLabelField
  property alias parentField: parentField
  property alias relationField: links.relationField
  property alias titleField: titleField
  property alias propMenu: propMenu

  readonly property bool editing: ed.issueId !== ""
  property bool parentOpen: false      // the parent issue field is shown
  // The repeat rule of the open issue (Repeat… in the menu), or null.
  readonly property var edRecur: ed.issueId && ed.orig ? Recur.recurRuleFor(root.config.recurring, ed.orig) : null
  readonly property real sidebarWidth: Math.max(Style.space(220), Math.min(Style.space(280), width * 0.3))

  z: 62
  visible: root.dialog === "issue"
  onVisibleChanged: { parentOpen = false; ed.menu = "" }
  anchors.centerIn: parent
  width: editing ? Math.min(parent.width - Style.space(40), Style.space(1080)) : Math.min(parent.width - Style.space(40), Style.space(720))
  height: editing ? Math.min(parent.height - Style.space(40), Style.space(880))
    : Math.min(parent.height - Style.space(40), Math.max(Style.space(460),
      edHeader.height + editorColumn.implicitHeight + edFooter.height + Style.spacing.panelPadding * 2 + Style.spacing.xl * 3))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  clip: true
  MouseArea { anchors.fill: parent }

  // ---- what each property pill shows ----
  readonly property var pillKinds: {
    var k = ["status", "priority", "assignee", "labels"]
    if (editor.editing) k.push("project")
    if (ed.milestones.length || ed.milestoneValid) k.push("milestone")
    if (ed.team.cycles.length || ed.cycleId) k.push("cycle")
    if (ed.team.estimateOptions.length) k.push("estimate")
    k.push("due", "parent")
    return k
  }
  readonly property var pillNames: ({ status: "Status", priority: "Priority", assignee: "Assignee", labels: "Labels", project: "Project",
    milestone: "Milestone", cycle: "Cycle", estimate: "Estimate", due: "Due date", parent: "Parent" })
  // Hover hint with the property's shortcut, the same key as on the board.
  readonly property var pillKeys: ({ status: "S", priority: "P", assignee: "A", labels: "T", project: "Shift+P",
    milestone: "Shift+M", cycle: "Shift+C", estimate: "Shift+E", due: "Shift+D" })
  function pillTip(kind) {
    var name = editor.pillNames[kind] || kind
    if (kind === "parent") return name + "  ·  Alt+U"
    var k = editor.pillKeys[kind]
    // While typing: Alt + the letter; Shift only where Alt + the letter is taken (P priority, T labels).
    var alt = kind === "project" ? "Alt+Shift+P" : "Alt+" + (k || "").replace("Shift+", "")
    return k ? name + "  ·  " + k + "   (" + alt + " while typing)" : name
  }
  function pillSpec(kind) {
    var s = { glyph: "", glyphColor: root.fg, dot: "", text: editor.pillNames[kind] || kind, unset: true, chips: [] }
    if (kind === "status") {
      var st = ed.team.states.filter(function(x) { return x.id === ed.stateId })[0]
      if (st) { s.dot = st.color; s.text = st.name; s.unset = false }
    } else if (kind === "priority") {
      var p = Linear.priority(ed.priority)
      s.glyph = p.value ? p.short : "—"
      s.glyphColor = p.value === 1 ? root.urgent : root.tint(p.color)
      if (p.value) { s.text = p.label; s.unset = false }
    } else if (kind === "assignee") {
      s.glyph = root.icon.account
      var m = ed.team.members.filter(function(x) { return x.id === ed.assigneeId })[0] || (ed.orig && ed.orig.assignee && ed.orig.assignee.id === ed.assigneeId ? ed.orig.assignee : null)
      if (ed.assigneeId && m) { s.text = root.viewer && m.id === root.viewer.id ? "Me" : m.name; s.unset = false; s.glyphColor = root.accent }
    } else if (kind === "labels") {
      var ls = ed.labels.map(function(id) { return ed.team.labels.filter(function(l) { return l.id === id })[0] }).filter(function(l) { return l })
      s.glyph = root.icon.label
      if (ls.length) { s.chips = ls.map(function(l) { return { name: l.name, color: l.color } }); s.text = ""; s.unset = false }
    } else if (kind === "project") {
      s.glyph = root.icon.project
      var pr = ed.team.projects.filter(function(x) { return x.id === ed.projectId })[0]
      if (pr) { s.dot = pr.color; s.text = pr.name; s.unset = false }
    } else if (kind === "milestone") {
      s.glyph = root.icon.flag
      var ms = ed.milestones.filter(function(x) { return x.id === ed.milestoneValid })[0]
      if (ms) { s.text = ms.name; s.unset = false; s.glyphColor = root.accent }
    } else if (kind === "cycle") {
      s.glyph = root.icon.cycle
      if (ed.cycleId) {
        var c = ed.team.cycles.filter(function(x) { return x.id === ed.cycleId })[0]
        s.text = c ? (c.name || "Cycle " + c.number) : "Past cycle"
        s.unset = false
        s.glyphColor = c && c.isActive ? root.accent : root.fg
      }
    } else if (kind === "estimate") {
      s.glyph = root.icon.estimate
      if (ed.estimate !== null) {
        var opt = ed.team.estimateOptions.filter(function(o) { return o.value === ed.estimate })[0]
        s.text = opt ? opt.label : String(ed.estimate)
        s.unset = false
      }
    } else if (kind === "due") {
      s.glyph = root.icon.calendar
      var d = Dates.parseDate(dueField.text)
      if (d) {
        var info = Dates.dueInfo(d, root.today)
        s.text = info ? info.text : d
        s.unset = false
        s.glyphColor = info && info.level === "overdue" ? root.urgent : (info && info.level === "today" ? root.tint("orange") : root.accent)
      }
    } else if (kind === "parent") {
      s.glyph = root.icon.parent
      if (ed.parentIssue) { s.text = ed.parentIssue.identifier + "  " + ed.parentIssue.title; s.unset = false }
    }
    return s
  }
  // Is a text field of the editor taking the keys? Then letters are text,
  // not shortcuts.
  function typing() {
    return [titleField, descField, parentField, editor.commentField, editor.relationField, editor.linkField,
      editor.edTimeField, editor.edTimeDate, editor.edTimeNote]
      .some(function(f) { return f.activeFocus })
  }

  // Open a property's menu from the keyboard (Alt+S, Shift+D…): under its pill.
  function openMenu(kind) {
    if (kind === "project" && !editor.editing) { editor.pillClicked(kind, edHeader.projectPill); return }
    if (kind === "team") { if (!editor.editing && edHeader.teamPill.visible) propMenu.openFor("team", edHeader.teamPill); return }
    var i = editor.pillKinds.indexOf(kind)
    var item = i < 0 ? null : (editor.editing ? sidebar.sidePills.itemAt(i) : newPills.itemAt(i))
    if (item && editor.editing) item = item.pill
    if (item) editor.pillClicked(kind, item)
    else notices.notify({ milestone: "This project has no milestones", cycle: "This team has no cycles", estimate: "This team does not use estimates" }[kind] || "Not available here")
  }
  // The ⋯ menu (remind me, repeat, template, duplicate): Shift+R.
  function openMore() { propMenu.openFor("more", edHeader.morePill) }
  // Ctrl+Shift+X, like the Archive chip: only for issues on the board.
  function archiveOpen() {
    if (!root.onBoard(ed.issueId)) { notices.notify("Archive it from Linear: it is not on this board", true); return }
    var id = ed.issueId, ident = ed.identifier
    pickers.closeDialog()
    pickers.ask("Archive " + ident + "?", "Archive", function() { bulk.archiveIds([id], ident) })
  }

  // A parent was picked (or another issue opened): close the field.
  Connections { target: ed; function onParentIssueChanged() { editor.parentOpen = false } }
  function pillClicked(kind, item) {
    if (kind === "parent") { editor.parentOpen = !editor.parentOpen; if (editor.parentOpen) Qt.callLater(function() { parentField.forceActiveFocus() }); return }
    propMenu.openFor(kind, item)
  }

  // Values the board's logic reads and sets but that are picked from menus now.
  TextBox { id: dueField; visible: false; onTextChanged: ed.dueError = false }
  TextBox { id: newLabelField; visible: false }

  // ================= header =================
  // ================= header =================
  EditorHeader {
    id: edHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
  }

  // ================= main column =================
  Flickable {
    id: editorFlick
    anchors.left: parent.left
    anchors.right: editor.editing ? sidebar.left : parent.right
    anchors.top: edHeader.bottom
    anchors.bottom: edFooter.top
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.topMargin: Style.spacing.xl
    anchors.bottomMargin: Style.spacing.lg
    contentHeight: editorColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: editorColumn
      width: parent.width
      spacing: Style.spacing.xl

      // Opened from the inbox, search or a link: say why it is not on the board.
      Label {
        readonly property string reason: ed.issueId && ed.orig ? root.offBoardReason(ed.orig) : ""
        visible: reason !== ""
        width: parent.width
        text: root.icon.info + "  Not on the board: " + reason
        color: root.accent
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
      }

      // Title: big, without a frame, like Linear.
      TextBox {
        id: titleField
        Keys.onPressed: function(event) { keyboard.altMenu(event) }
        width: parent.width
        placeholderText: "Issue title"
        color: root.fg
        placeholderTextColor: Util.alpha(root.fg, 0.35)
        selectionColor: Util.alpha(root.accent, 0.35)
        font.family: root.font
        font.pixelSize: Style.font.heading + 2
        font.bold: true
        padLeft: 0
        padRight: 0
        background: Rectangle {
          color: "transparent"
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Math.max(1, Style.space(2)); color: root.urgent; visible: ed.titleError }
        }
        onTextChanged: if (text.trim()) ed.titleError = false
        Keys.onReturnPressed: function(event) {
          if (event.modifiers & Qt.ControlModifier) editorOps.saveIssue()
          else { ed.descPreview = false; Qt.callLater(function() { descField.forceActiveFocus() }) }
          event.accepted = true
        }
        Keys.onEnterPressed: function(event) { editorOps.saveIssue(); event.accepted = true }
      }

      // Saved descriptions show rendered (and Preview shows the one being
      // written); a click or Edit goes back to writing.
      Item {
        visible: ed.descPreview
        width: parent.width
        height: descPreview.implicitHeight
        MarkdownView {
          id: descPreview
          width: parent.width
          markdown: ed.descPreview ? descField.text : ""
          canDelete: true
          onDeleteImage: function(url) { uploads.deleteUpload(url, { kind: "desc" }) }
          canToggle: true
          onToggleTask: function(line) { editorOps.toggleDescTask(line) }
        }
        HoverHandler { id: descHover }
        TapHandler {
          onTapped: if (!descPreview.hoveredLink) { ed.descPreview = false; Qt.callLater(function() { descField.forceActiveFocus() }) }
        }
        DropArea {
          anchors.fill: parent
          onEntered: function(drag) { drag.accepted = drag.hasUrls }
          onDropped: function(drop) {
            if (!drop.hasUrls) return
            ed.descPreview = false
            uploads.dropFiles(drop.urls, descField, descField.text.length)
            drop.accept()
          }
        }
        Button {
          tooltipText: "Edit the description (E)"
          visible: descHover.hovered
          anchors.top: parent.top
          anchors.right: parent.right
          text: "Edit"
          onClicked: { ed.descPreview = false; Qt.callLater(function() { descField.forceActiveFocus() }) }
        }
      }

      QQC.ScrollView {
        id: descScroll
        visible: !ed.descPreview
        width: parent.width
        height: Math.max(editor.editing ? Style.space(140) : Style.space(110), Math.min(Style.space(380), descField.implicitHeight))
        TextBox {
          id: descField
          multiline: true
          imagePaste: true
          flickable: descScroll.contentItem
          width: descScroll.availableWidth
          height: Math.max(implicitHeight, descScroll.availableHeight)
          placeholderText: "Add a description…  (Markdown; paste or drop images and files)"
          wrapMode: TextEdit.Wrap
          color: root.fg
          placeholderTextColor: Util.alpha(root.fg, 0.35)
          selectionColor: Util.alpha(root.accent, 0.35)
          font.family: root.font
          font.pixelSize: Style.font.body
          padLeft: 0
          padRight: 0
          topPadding: Style.spacing.sm
          bottomPadding: Style.spacing.sm
          background: Item {}
          // Drop files here (images from a browser too): uploaded to Linear.
          DropArea {
            anchors.fill: parent
            onEntered: function(drag) { drag.accepted = drag.hasUrls }
            onDropped: function(drop) {
              if (!drop.hasUrls) return
              uploads.dropFiles(drop.urls, descField, descField.positionAt(drop.x, drop.y))
              drop.accept()
            }
            Rectangle {
              anchors.fill: parent
              visible: parent.containsDrag
              radius: root.radius
              color: Util.alpha(root.accent, 0.12)
              border.width: Math.max(1, Style.space(2))
              border.color: root.accent
              Label { anchors.centerIn: parent; text: root.icon.upload + "  Drop to upload to Linear"; color: root.accent }
            }
          }
          Keys.onPressed: function(event) {
            if (keyboard.altMenu(event)) return
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
              editorOps.saveIssue()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              // Tab moves on (to the property pills), it does not type a tab.
              var next = descField.nextItemInFocusChain(event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))
              if (next) next.forceActiveFocus(event.key === Qt.Key_Tab ? Qt.TabFocusReason : Qt.BacktabFocusReason)
              event.accepted = true
            } else if (editorOps.markdownKey(descField, event)) event.accepted = true
          }
        }
      }
      // See how the Markdown will look before saving.
      Row {
        visible: !ed.descPreview && descField.text.trim() !== ""
        spacing: Style.spacing.md
        Button {
          text: "Preview"
          iconText: root.icon.eye
          tooltipText: "Show the description as Linear will (Ctrl+Shift+P); Edit or a click goes back"
          onClicked: issueOps.toggleDescPreview()
        }
        Label {
          readonly property int images: Markdown.markdownImages(descField.text).length
          visible: images > 0
          text: images + (images === 1 ? " image" : " images") + ": Preview shows them (and can delete them from Linear)"
          color: root.accent
          opacity: 0.8
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // New issue: the properties as a row of pills.
      Flow {
        visible: !editor.editing
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          id: newPills
          model: editor.editing ? [] : editor.pillKinds
          delegate: PropPill {
            id: newPill
            required property var modelData
            readonly property var spec: editor.pillSpec(modelData)
            glyph: spec.glyph
            glyphColor: spec.glyphColor
            showDot: spec.dot !== ""
            dotColor: spec.dot || "transparent"
            text: spec.text.length > 32 ? spec.text.slice(0, 31) + "…" : spec.text
            chips: spec.chips
            unset: spec.unset
            active: ed.menu === modelData || (modelData === "parent" && editor.parentOpen)
            tip: editor.pillTip(modelData)
            onClicked: editor.pillClicked(modelData, newPill)
          }
        }
      }

      // Parent issue: picked by ID or title (with suggestions).
      Column {
        visible: editor.parentOpen
        width: parent.width
        spacing: Style.spacing.sm
        Row {
          spacing: Style.spacing.sm
          TextBox {
            id: parentField
            width: Math.min(editorColumn.width - (removeParent.visible ? removeParent.width + Style.spacing.sm : 0), Style.space(380))
            verticalPadding: 0
            height: root.inlineHeight
            verticalAlignment: TextEdit.AlignVCenter
            font.pixelSize: Style.font.bodySmall
            placeholderText: (ed.parentIssue ? "Change the parent: " : "Parent: ") + "ID or title, e.g. " + (ed.team.key || "ENG") + "-12"
            onTextChanged: if (activeFocus) editorOps.updateSuggest("parent", text)
            onActiveFocusChanged: if (!activeFocus && ed.suggestFor === "parent") Qt.callLater(function() { if (!parentField.activeFocus && ed.suggestFor === "parent") editorOps.clearSuggest() })
            Keys.onPressed: function(event) {
              if (keyboard.altMenu(event)) return
              if (editorOps.suggestKey(event, "parent", parentField)) { event.accepted = true; return }
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { editorOps.setParentFromText(text); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { editor.parentOpen = false; event.accepted = true }
            }
          }
          Chip {
            tip: "Remove the parent issue"
            id: removeParent
            visible: !!ed.parentIssue
            text: "Remove parent"
            glyph: root.icon.close
            onClicked: { ed.parentIssue = null; editor.parentOpen = false }
          }
        }
        SuggestList { kind: "parent"; width: parent.width }
      }

      // Reactions on the issue itself (saved issues).
      Flow {
        visible: ed.issueId !== ""
        width: parent.width
        spacing: Style.spacing.xs
        Repeater {
          model: ed.issueId ? Issues.reactionSummary(ed.reactions, root.viewer ? root.viewer.id : "") : []
          delegate: Chip {
            required property var modelData
            text: modelData.char + " " + modelData.count
            selected: modelData.mine !== ""
            tint: root.accent
            fontSize: Style.font.caption
            tip: modelData.names.join(", ")
            onClicked: editorOps.toggleIssueReaction(modelData.char.charAt(0) === ":" ? modelData.emoji : modelData.char)
          }
        }
        Chip {
          text: ed.issueReactShown ? "✕" : "🙂+"
          fontSize: Style.font.caption
          opacity: 0.7
          tip: "React to the issue"
          onClicked: ed.issueReactShown = !ed.issueReactShown
        }
        Repeater {
          model: ed.issueReactShown ? Linear.REACTION_EMOJIS : []
          delegate: Chip {
            required property var modelData
            text: modelData
            fontSize: Style.font.caption
            onClicked: editorOps.toggleIssueReaction(modelData)
          }
        }
      }

      // Saved issues: sub-issues, relations, links; then comments and history.
      EditorLinks { id: links; visible: editor.editing; width: parent.width }
      EditorActivity { id: activity; visible: editor.editing; width: parent.width }
    }
  }

  // ================= sidebar (saved issues) =================
  EditorSidebar {
    id: sidebar
    anchors.right: parent.right
    anchors.top: edHeader.bottom
    anchors.bottom: edFooter.top
    anchors.topMargin: Style.spacing.lg
    anchors.bottomMargin: Style.spacing.lg
    anchors.rightMargin: Style.spacing.panelPadding
  }


  // ================= footer =================
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: edFooter.top
    anchors.bottomMargin: Style.spacing.md
    height: 1
    color: Util.alpha(root.fg, 0.1)
  }
  RowLayout {
    id: edFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    anchors.topMargin: 0
    spacing: Style.spacing.lg
    Chip {
      visible: !editor.editing
      text: "Create more"
      glyph: ed.createMore ? root.icon.check : "○"
      selected: ed.createMore
      tint: root.accent
      tip: "After creating, start the next issue with the same properties (everything except title and description)"
      onClicked: ed.createMore = !ed.createMore
    }
    Item { Layout.fillWidth: true }
    Label {
      readonly property string st: editor.editing ? editorOps.saveStatus : ""
      text: !editor.editing ? "Ctrl+Enter creates"
        : st === "waiting" || st === "saving" ? "Saving…"
        : st === "offline" ? "Offline: saved here, sent when Linear is back"
        : st === "error" ? "Not saved, see the message"
        : st === "saved" ? root.icon.check + " Saved"
        : "Changes are saved as you make them"
      color: st === "error" ? root.urgent : root.fg
      opacity: st === "error" ? 1 : 0.5
      font.pixelSize: Style.font.caption
    }
    Button { visible: !editor.editing; tooltipText: "Close without creating (Esc)"; text: "Cancel"; onClicked: pickers.closeDialog() }
    Button {
      tooltipText: editor.editing ? "Close (Esc or Ctrl+Enter); every change is already saved" : "Create (Ctrl+Enter)"
      text: editor.editing ? "Close" : "Create issue"
      bordered: true
      selected: true
      onClicked: editorOps.saveIssue()
    }
  }

  PropMenu { id: propMenu }
}
