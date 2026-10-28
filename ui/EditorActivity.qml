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

// Part of the Linear board (mani4.linear-board): a saved issue's comments
// (threads, reactions, editing your own), the comment being written with
// @mentions and its preview, and the issue's history. Created in
// ui/IssueEditor.qml as `activity`.
Column {
  id: activity
  property alias commentField: commentField
  spacing: Style.spacing.xl

    // ---- comments (saved issues only) ----
    SectionTitle {
      visible: ed.issueId !== ""
      text: "Comments" + (ed.comments.length ? "  " + ed.comments.length : "") + (ed.detailLoading ? "  · loading…" : "")
    }
    Repeater {
      model: ed.issueId !== "" ? ed.thread : []
      delegate: Column {
        id: commentItem
        required property var modelData
        readonly property var c: modelData.comment
        readonly property var reactions: Issues.reactionSummary(c.reactions, root.viewer ? root.viewer.id : "")
        width: activity.width - x
        x: modelData.depth ? Style.space(28) : 0
        spacing: Style.spacing.xs
        Row {
          spacing: Style.spacing.md
          Label { text: (commentItem.modelData.depth ? "↳ " : "") + commentItem.c.author; font.bold: true; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          Label {
            text: Dates.shortDateTime(commentItem.c.createdAt) + (commentItem.c.edited ? "  (edited)" : "")
            opacity: 0.45
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          // Only your own comments can be changed.
          Button {
            tooltipText: "Edit your comment"
            visible: !!(root.viewer && commentItem.c.authorId === root.viewer.id)
            text: "Edit"
            onClicked: editorOps.startEditComment(commentItem.c)
          }
          Button {
            tooltipText: "Delete your comment"
            visible: !!(root.viewer && commentItem.c.authorId === root.viewer.id)
            text: "Delete"
            foreground: root.urgent
            onClicked: editorOps.deleteComment(commentItem.c)
          }
        }
        MarkdownView {
          width: parent.width
          markdown: commentItem.c.body
          opacity: ed.editingCommentId === commentItem.c.id ? 0.4 : 0.9
          canDelete: !!(root.viewer && commentItem.c.authorId === root.viewer.id)
          onDeleteImage: function(url) { uploads.deleteUpload(url, { kind: "comment", comment: commentItem.c }) }
          canToggle: !!(root.viewer && commentItem.c.authorId === root.viewer.id) && ed.editingCommentId !== commentItem.c.id
          onToggleTask: function(line) { editorOps.toggleCommentTask(commentItem.c, line) }
        }
        // Reactions: yours are highlighted, click to add or take back.
        Flow {
          width: parent.width
          spacing: Style.spacing.xs
          Repeater {
            model: commentItem.reactions
            delegate: Chip {
              required property var modelData
              text: modelData.char + " " + modelData.count
              selected: modelData.mine !== ""
              tint: root.accent
              fontSize: Style.font.caption
              tip: modelData.names.join(", ")
              onClicked: editorOps.toggleReaction(commentItem.c, modelData.char.charAt(0) === ":" ? modelData.emoji : modelData.char)
            }
          }
          Chip {
            text: ed.reactFor === commentItem.c.id ? "✕" : "🙂+"
            fontSize: Style.font.caption
            opacity: 0.7
            tip: "React"
            onClicked: ed.reactFor = ed.reactFor === commentItem.c.id ? "" : commentItem.c.id
          }
          Repeater {
            model: ed.reactFor === commentItem.c.id ? Linear.REACTION_EMOJIS : []
            delegate: Chip {
              required property var modelData
              text: modelData
              fontSize: Style.font.caption
              onClicked: editorOps.toggleReaction(commentItem.c, modelData)
            }
          }
          Chip {
            tip: "Reply in a thread"
            text: "Reply"
            glyph: root.icon.reply
            fontSize: Style.font.caption
            opacity: 0.7
            onClicked: editorOps.replyTo(commentItem.c)
          }
        }
      }
    }
    Flow {
      visible: ed.issueId !== "" && !!ed.mention && mentionRepeater.count > 0
      width: parent.width
      spacing: Style.spacing.sm
      Label { text: "Mention:"; opacity: 0.5; font.pixelSize: Style.font.caption }
      Repeater {
        id: mentionRepeater
        model: ed.mention ? Markdown.mentionMatches(root.members, ed.mention.query) : []
        delegate: Chip {
          required property var modelData
          required property int index
          text: "@" + modelData.name + (index === 0 ? "  ⇥" : "")
          tint: root.accent
          selected: index === 0
          onClicked: editorOps.insertMention(modelData)
        }
      }
    }
    Chip {
      visible: ed.issueId !== "" && !!ed.replyTo
      text: ed.replyTo ? "Replying to " + ed.replyTo.author + "  ✕" : ""
      glyph: root.icon.reply
      tint: root.accent
      selected: true
      tip: "Click to write a new comment instead"
      onClicked: ed.replyTo = null
    }
    RowLayout {
      visible: ed.issueId !== ""
      width: parent.width
      spacing: Style.spacing.md
      QQC.ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(70)
        QQC.TextArea {
          id: commentField
          placeholderText: ed.replyTo ? "Reply… Ctrl+Enter sends" : "Write a comment… @ mentions, paste or drop images, Ctrl+Enter sends"
          onTextChanged: editorOps.updateMention()
          onCursorPositionChanged: editorOps.updateMention()
          wrapMode: TextEdit.Wrap
          color: root.fg
          placeholderTextColor: Util.alpha(root.fg, 0.4)
          selectionColor: Util.alpha(root.accent, 0.35)
          font.family: root.font
          font.pixelSize: Style.font.body
          padding: Style.spacing.lg
          background: Rectangle {
            radius: root.radius
            color: Util.alpha(root.fg, 0.04)
            border.width: 1
            border.color: commentField.activeFocus ? root.accent : Util.alpha(root.fg, 0.2)
          }
          // Drop files here (images from a browser too): uploaded to Linear.
          DropArea {
            anchors.fill: parent
            onEntered: function(drag) { drag.accepted = drag.hasUrls }
            onDropped: function(drop) {
              if (!drop.hasUrls) return
              uploads.dropFiles(drop.urls, commentField, commentField.positionAt(drop.x, drop.y))
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
              editorOps.postComment()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab && ed.mention) {
              var m = Markdown.mentionMatches(root.members, ed.mention.query)
              if (m.length) { editorOps.insertMention(m[0]); event.accepted = true }
            } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier)) {
              uploads.pasteInto(commentField)
              event.accepted = true
            } else if (event.key === Qt.Key_Escape && (ed.editingCommentId || ed.replyTo)) {
              if (ed.editingCommentId) editorOps.cancelEditComment()
              ed.replyTo = null
              event.accepted = true
            } else if (editorOps.markdownKey(commentField, event)) event.accepted = true
          }
        }
      }
      Column {
        spacing: Style.spacing.xs
        Button {
          tooltipText: "Send (Ctrl+Enter)"
          text: ed.posting ? "Sending…" : (ed.editingCommentId ? "Save" : "Comment")
          iconText: root.icon.send
          bordered: true
          onClicked: editorOps.postComment()
        }
        Button {
          tooltipText: "Stop editing the comment"
          visible: ed.editingCommentId !== ""
          text: "Cancel"
          onClicked: editorOps.cancelEditComment()
        }
        Button {
          visible: commentField.text.trim() !== ""
          text: ed.commentPreview ? "Hide preview" : "Preview"
          iconText: root.icon.eye
          tooltipText: "Show the comment as Linear will (Ctrl+Shift+P while writing it)"
          onClicked: ed.commentPreview = !ed.commentPreview
        }
      }
    }
    // The comment being written, rendered.
    Rectangle {
      visible: ed.issueId !== "" && ed.commentPreview && commentField.text.trim() !== ""
      width: parent.width
      height: commentPreview.implicitHeight + Style.spacing.lg * 2
      radius: root.radius
      color: Util.alpha(root.fg, 0.03)
      border.width: 1
      border.color: Util.alpha(root.accent, 0.4)
      MarkdownView {
        id: commentPreview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.lg
        markdown: ed.commentPreview ? commentField.text : ""
        canDelete: true
        onDeleteImage: function(url) { uploads.deleteUpload(url, { kind: "draft", field: commentField }) }
        canToggle: true
        onToggleTask: function(line) { editorOps.toggleDraftTask(commentField, line) }
      }
    }

    // ---- history (saved issues only) ----
    Button {
      tooltipText: "What changed on the issue, and who changed it"
      visible: ed.issueId !== ""
      text: ed.historyShown ? "Hide history" : "Show history"
      iconText: root.icon.down
      onClicked: editorOps.showHistory()
    }
    Column {
      visible: ed.issueId !== "" && ed.historyShown
      width: parent.width
      spacing: Style.spacing.xs
      Label { visible: ed.historyLoading; text: "Loading…"; opacity: 0.5 }
      Label { visible: !ed.historyLoading && ed.history.length === 0; text: "No changes recorded"; opacity: 0.5 }
      Repeater {
        model: ed.historyShown ? ed.history : []
        delegate: Row {
          required property var modelData
          width: activity.width
          spacing: Style.spacing.md
          Label {
            id: histTime
            text: Dates.shortDateTime(modelData.createdAt)
            opacity: 0.45
            font.pixelSize: Style.font.caption
            width: Style.space(110)
          }
          Label {
            width: parent.width - histTime.width - parent.spacing
            text: modelData.text
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: Style.font.bodySmall
            opacity: 0.8
          }
        }
      }
    }
}
