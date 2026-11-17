import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Markdown.js" as Markdown

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// Markdown from Linear (descriptions, comments), with clickable links.
// Markdown from Linear (descriptions, comments, project updates): text with
// clickable links, and images drawn between the paragraphs (Linear's
// uploads are downloaded first, see root.requestImages). Click an image to
// open it.
Column {
  id: mdv
  property string markdown: ""
  property string hoveredLink: ""
  // When the text is yours to change: images uploaded to Linear get a
  // "Delete from Linear" button on hover.
  property bool canDelete: false
  signal deleteImage(string url)
  // When the checklist ("- [ ] item") may be ticked here: a click on a box
  // asks for it with the item's line in `markdown` (see Markdown.toggleTask).
  property bool canToggle: false
  signal toggleTask(int line)
  readonly property var parts: Markdown.splitParts(markdown)
  readonly property string linkHex: String(root.accent).length === 7 ? String(root.accent) : "#" + String(root.accent).slice(3)
  spacing: Style.spacing.sm
  // Only Linear's own uploads are fetched to show inline; other images stay links (Markdown.autoImage).
  onMarkdownChanged: uploads.requestImages(Markdown.markdownImages(markdown).filter(Markdown.autoImage))
  // The parts are drawn anew: a box the mouse was over is gone.
  onPartsChanged: hoveredLink = ""
  Component.onCompleted: uploads.requestImages(Markdown.markdownImages(markdown).filter(Markdown.autoImage))

  Repeater {
    model: mdv.parts
    delegate: Item {
      id: part
      required property var modelData
      readonly property var img: modelData.image ? uploads.imageCache[modelData.url] : null
      readonly property bool showImage: !!(img && img.path)
      readonly property bool isTask: !!modelData.task
      // Images uploaded to Linear in your own text get a delete button on
      // hover: on the picture's corner, or after the link while it is not downloaded.
      readonly property bool deletable: mdv.canDelete && uploads.deleteSupport !== "gone" && !!modelData.image && /^https:\/\/uploads\.linear\.app\//.test(modelData.url)
      width: mdv.width
      height: isTask ? taskRow.height : showImage ? picture.height : Math.max(partText.implicitHeight, deletable ? delBtn.height : 0)

      // A checklist item: a box and its text. With canToggle a click on
      // either ticks it (links in the text still open).
      Item {
        id: taskRow
        visible: part.isTask
        x: part.isTask ? part.modelData.level * Style.space(18) : 0
        width: parent.width - x
        height: part.isTask ? Math.max(box.height, taskText.implicitHeight) : 0
        readonly property string tag: part.isTask ? "task:" + part.modelData.line : ""
        // The mouse over the box or the text (not the empty space after it).
        readonly property bool hot: part.isTask && rowHover.hovered && rowHover.point.position.x <= taskText.x + Math.min(taskText.width, taskText.implicitWidth) + Style.spacing.xs
        // Like a link: the description's "click to edit" leaves it alone.
        function showHover() { mdv.hoveredLink = taskText.hoveredLink || (hot ? tag : "") }
        onHotChanged: showHover()
        HoverHandler {
          id: rowHover
          cursorShape: taskText.hoveredLink || (taskRow.hot && mdv.canToggle) ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        // Under the text: Text takes only clicks on its links, the rest come here.
        // Up to the end of the text, so the empty space after it stays "click to edit".
        MouseArea {
          id: rowMouse
          x: -Style.spacing.xs
          y: -Style.spacing.xs
          width: Math.min(taskRow.width, taskText.x + Math.min(taskText.width, taskText.implicitWidth)) + Style.spacing.xs * 2
          height: taskRow.height + Style.spacing.xs * 2
          enabled: part.isTask
          onClicked: if (mdv.canToggle) mdv.toggleTask(part.modelData.line)
        }
        Rectangle {
          id: box
          readonly property bool checked: part.isTask && part.modelData.checked
          y: Math.max(0, Math.round((Math.min(taskText.implicitHeight, taskText.font.pixelSize * 1.5) - height) / 2))
          width: Math.round(Style.font.body * 1.05)
          height: width
          radius: Math.max(2, Math.round(width / 5))
          color: checked ? root.accent : (taskRow.hot && mdv.canToggle ? Util.alpha(root.accent, 0.15) : "transparent")
          border.width: Math.max(1, Style.space(1.5))
          border.color: checked ? root.accent : Util.alpha(root.fg, taskRow.hot && mdv.canToggle ? 0.8 : 0.45)
          Label {
            anchors.centerIn: parent
            visible: box.checked
            text: "✓"
            color: root.bg
            font.bold: true
            font.pixelSize: Math.round(box.width * 0.8)
          }
        }
        Text {
          id: taskText
          anchors.left: box.right
          anchors.leftMargin: Style.spacing.md
          anchors.right: parent.right
          text: part.isTask ? Markdown.displayMarkdown(part.modelData.text, mdv.linkHex) : ""
          textFormat: Text.MarkdownText
          wrapMode: Text.Wrap
          color: root.fg
          opacity: box.checked ? 0.55 : 1
          linkColor: root.accent
          font.family: root.font
          font.pixelSize: Style.font.body
          font.strikeout: box.checked
          onLinkActivated: function(link) { editorOps.openInLinear(link) }
          onHoveredLinkChanged: taskRow.showHover()
        }
      }

      Text {
        id: partText
        visible: !part.showImage && !part.isTask
        width: parent.width
        text: part.modelData.image
          ? Markdown.displayMarkdown("![" + part.modelData.alt + (part.img === "pending" ? " · loading…" : "") + "](" + part.modelData.url + ")", mdv.linkHex)
          : part.isTask ? "" : Markdown.displayMarkdown(part.modelData.text, mdv.linkHex)
        textFormat: Text.MarkdownText
        wrapMode: Text.Wrap
        color: root.fg
        linkColor: root.accent
        font.family: root.font
        font.pixelSize: Style.font.body
        onLinkActivated: function(link) { editorOps.openInLinear(link) }
        onHoveredLinkChanged: mdv.hoveredLink = hoveredLink
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
      }
      // Hovering the image (or the link) shows the delete button.
      HoverHandler { id: partHover }
      Rectangle {
        id: delBtn
        z: 2
        visible: part.deletable && (partHover.hovered || delMouse.containsMouse)
        y: part.showImage ? Style.spacing.sm : 0
        x: part.showImage ? Math.max(0, picture.width - width - Style.spacing.sm)
          : Math.min(part.width - width, partText.contentWidth + Style.spacing.md)
        width: delRow.implicitWidth + Style.spacing.lg * 2
        height: delRow.implicitHeight + Style.spacing.sm * 2
        radius: root.radius
        color: delMouse.containsMouse ? root.urgent : Util.alpha(root.bg, 0.9)
        border.width: 1
        border.color: root.urgent
        Row {
          id: delRow
          anchors.centerIn: parent
          spacing: Style.spacing.sm
          Label { text: root.icon.trash; color: delMouse.containsMouse ? root.bg : root.urgent; font.pixelSize: Style.font.caption + 1 }
          Label { text: "Delete from Linear"; color: delMouse.containsMouse ? root.bg : root.urgent; font.pixelSize: Style.font.caption }
        }
        MouseArea {
          id: delMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: mdv.deleteImage(part.modelData.url)
        }
      }
      Image {
        id: picture
        visible: part.showImage
        source: part.showImage ? "file://" + part.img.path : ""
        width: Math.min(parent.width, part.img && part.img.w ? part.img.w : parent.width)
        height: part.img && part.img.w && part.img.h ? Math.round(width * part.img.h / part.img.w) : (status === Image.Ready ? Math.round(width * implicitHeight / Math.max(1, implicitWidth)) : 0)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        MouseArea {
          id: picMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: mdv.hoveredLink = containsMouse ? part.modelData.url : ""
          onClicked: Quickshell.execDetached(["xdg-open", part.img.path])
        }
      }
    }
  }
}
