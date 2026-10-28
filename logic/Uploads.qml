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
import "../Markdown.js" as Markdown

// Images and files: showing Linear images, pasting, dropping and uploading, deleting uploads.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `uploads`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: uploads
  visible: false

  // ---- showing images: Linear's uploads need the API key, so they are
  // downloaded into ~/.cache/omarchy-linear-board/images and shown from there.
  property var imageCache: ({})        // url → { path, w, h } | "pending" | "failed"
  property var imageQueue: []
  function requestImages(urls) {
    var add = (urls || []).filter(function(u) { return !(u in uploads.imageCache) && uploads.imageQueue.indexOf(u) < 0 })
    if (!add.length || !root.apiKey) return
    var c = {}
    for (var k in uploads.imageCache) c[k] = uploads.imageCache[k]
    add.forEach(function(u) { c[u] = "pending" })
    uploads.imageCache = c
    uploads.imageQueue = uploads.imageQueue.concat(add)
    if (!imageProc.running) uploads.nextImage()
  }
  function setImage(url, value) {
    var c = {}
    for (var k in uploads.imageCache) c[k] = uploads.imageCache[k]
    c[url] = value
    uploads.imageCache = c
  }
  function nextImage() {
    var url = uploads.imageQueue[0]
    if (!url) return
    imageProc.url = url
    // The file name: the URL without its scheme, made safe.
    var name = url.replace(/^https?:\/\//, "").replace(/[?#].*$/, "").replace(/[^A-Za-z0-9._-]+/g, "_").slice(-150)
    imageProc.command = ["sh", "-c", 'umask 077; d="$2/images"; mkdir -p "$d"; f="$d/$3"; ' +
      'if [ ! -s "$f" ]; then case "$1" in https://uploads.linear.app/*) curl -sSfL -H "Authorization: $LINEAR_KEY" -o "$f.part" -- "$1";; ' +
      '*) curl -sSfL --max-filesize 20000000 -o "$f.part" -- "$1";; esac && mv "$f.part" "$f" || { rm -f "$f.part"; exit 1; }; fi; ' +
      'case "$(file -b --mime-type -- "$f")" in image/*) ;; *) exit 3;; esac; ' +
      'printf "%s\n%s\n" "$f" "$(file -b -- "$f")"', "sh", url, root.cacheDir, name]
    imageProc.running = true
  }
  Process {
    id: imageProc
    property string url: ""
    environment: ({ LINEAR_KEY: root.apiKey })
    stdout: StdioCollector { id: imageOut }
    onExited: function(code) {
      var lines = imageOut.text.split("\n")
      if (code === 0 && lines[0]) {
        // The last "W x H" (JPEG descriptions mention the density first).
        var all = (lines[1] || "").match(/\d+\s*x\s*\d+/g) || []
        var dim = all.length ? /(\d+)\s*x\s*(\d+)/.exec(all[all.length - 1]) : null
        uploads.setImage(url, { path: lines[0], w: dim ? parseInt(dim[1]) : 0, h: dim ? parseInt(dim[2]) : 0 })
      } else uploads.setImage(url, "failed")
      uploads.imageQueue = uploads.imageQueue.slice(1)
      if (uploads.imageQueue.length) Qt.callLater(uploads.nextImage)
    }
  }

  // Deleting files uses a mutation Linear marks internal, so it may vanish.
  // "" not checked yet | "ok" | "gone": the delete buttons hide.
  property string deleteSupport: ""
  readonly property string goneText: "Linear no longer lets apps delete uploaded files, so the delete button is hidden. Delete the file in Linear itself."

  // Runs go() once Linear has confirmed (this session) that it still offers
  // the delete; otherwise nothing is changed.
  function withDeleteSupport(go) {
    if (uploads.deleteSupport === "ok") { go(); return }
    if (uploads.deleteSupport === "gone") { notices.notify(uploads.goneText, true); return }
    root.gql(Linear.Q_MUTATIONS, {}, function(d) {
      if (Linear.hasMutation(d, Linear.FILE_DELETE_FIELD)) { uploads.deleteSupport = "ok"; go() }
      else { uploads.deleteSupport = "gone"; notices.notify(uploads.goneText, true) }
    }, function(msg) { notices.notify("Could not ask Linear whether files can be deleted, nothing was changed: " + msg, true) })
  }

  // Delete an uploaded image from Linear for good: take it out of the text
  // and save that first, so nothing is left showing a broken image, then
  // delete the file. where: { kind: desc | comment | update | draft, … }.
  function deleteUpload(url, where) {
    uploads.withDeleteSupport(function() { uploads.confirmDelete(url, where) })
  }

  function confirmDelete(url, where) {
    pickers.ask("Delete this image from Linear for good? It is taken out of this text and saved first, so nothing breaks here. This cannot be undone. Only places with a copy of this same image link (e.g. an issue made with Duplicate) would show it broken; an image uploaded again is a separate file and is not affected.",
      "Delete", function() {
      var purge = function() {
        root.gql(Linear.M_FILE_DELETE, { assetUrl: url }, function(d) {
          if (!Linear.fileDeleted(d)) { notices.notify("Taken out of the text, but Linear did not delete the file.", true); return }
          var img = uploads.imageCache[url]
          if (img && img.path) Quickshell.execDetached(["rm", "-f", "--", img.path])
          uploads.setImage(url, "failed")
          notices.notify("Image deleted from Linear", false, root.icon.check)
        }, function(msg) {
          // Linear dropped the mutation between the check and now.
          if (Linear.isSchemaGone(msg)) { uploads.deleteSupport = "gone"; notices.notify("Taken out of the text, but the file stays in Linear. " + uploads.goneText, true) }
          else notices.notify("Taken out of the text, but Linear did not delete the file: " + msg, true)
        })
      }
      var failed = function(msg) { notices.notify("Could not save the text, so the image was not deleted: " + msg, true) }
      if (where.kind === "draft") { where.field.text = Markdown.removeImage(where.field.text, url); purge(); return }
      if (where.kind === "desc") {
        var before = editor.descField.text
        var text = Markdown.removeImage(before, url)
        editor.descField.text = text
        if (!ed.issueId) { purge(); return }
        var id = ed.issueId
        root.gql(Linear.M_ISSUE_UPDATE, { id: id, input: { description: text } }, function(d) {
          var issue = Linear.toIssue(d.issueUpdate.issue)
          root.storeIssue(issue)
          if (ed.issueId === id && ed.orig) {
            var o = {}
            for (var k in ed.orig) o[k] = ed.orig[k]
            o.description = issue.description
            ed.orig = o
          }
          purge()
        }, function(msg) { if (ed.issueId === id) editor.descField.text = before; failed(msg) })
        return
      }
      if (where.kind === "comment") {
        var c = where.comment
        root.gql(Linear.M_COMMENT_UPDATE, { id: c.id, input: { body: Markdown.removeImage(c.body, url) } }, function(d) {
          var updated = Linear.toComment(d.commentUpdate.comment)
          ed.comments = ed.comments.map(function(x) { return x.id === c.id ? updated : x })
          purge()
        }, failed)
        return
      }
      if (where.kind === "update") {
        var u = where.update
        var input = { body: Markdown.removeImage(u.body, url) }
        if (u.health) input.health = u.health
        root.gql(Linear.M_PROJECT_UPDATE_EDIT, { id: u.id, input: input }, function(d) {
          var nu = Linear.toProjectUpdate(d.projectUpdateUpdate.projectUpdate)
          projectOps.projectUpdates = projectOps.projectUpdates.map(function(x) { return x.id === u.id ? nu : x })
          purge()
        }, failed)
      }
    })
  }

  // ---- images and files: Ctrl+V or drag and drop into the description, a comment or a project update ----
  // Each file is uploaded to Linear and its Markdown goes where the cursor
  // (or the drop) was: images as images, other files as links. Dropped
  // links (an image dragged from a browser) are downloaded first. Uploads
  // run one at a time from a queue.
  property var pasteField: null
  property int pasteAt: 0
  property var uploadQueue: []         // [{ src, field, at, prepared: { type, size, path, temp, name } }]
  readonly property bool uploading: uploads.uploadQueue.length > 0
  function pasteInto(field) {
    if (pasteProc.running) return
    uploads.pasteField = field
    uploads.pasteAt = field.cursorPosition
    pasteProc.running = true
  }
  Process {
    id: pasteProc
    command: ["sh", "-c", 't=$(wl-paste --list-types 2>/dev/null | grep -m1 -xE "image/(png|jpeg|gif|webp)") || { echo none; exit 0; }; ' +
      'f="$1/paste-$(date +%s%N).${t#image/}"; wl-paste -t "$t" > "$f" && printf "%s %s %s\\n" "$t" "$(stat -c %s "$f")" "$f"', "sh", root.cacheDir]
    stdout: StdioCollector { id: pasteOut }
    onExited: function(code) {
      var field = uploads.pasteField
      var out = pasteOut.text.trim()
      if (!field) return
      if (code !== 0 || !out || out === "none") { field.paste(); return }
      var parts = out.split(" ")
      var type = parts[0]
      uploads.queueUpload({ src: "clipboard", field: field, at: uploads.pasteAt, prepared: { type: type, size: parseInt(parts[1]),
        path: parts.slice(2).join(" "), temp: true, name: "image-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + "." + type.replace("image/", "") } })
    }
  }

  // Dropped urls (file:// or http(s)://) into `field` at text position `at`.
  function dropFiles(urls, field, at) {
    var list = []
    for (var i = 0; i < urls.length; i++) list.push(String(urls[i]))
    list = list.filter(function(u) { return /^(file|https?):\/\//.test(u) })
    if (!list.length) { notices.notify("Only files or links to files can be dropped here.", true); return }
    list.forEach(function(u) { uploads.queueUpload({ src: u, field: field, at: at, prepared: null }) })
  }
  function queueUpload(item) {
    uploads.uploadQueue = uploads.uploadQueue.concat([item])
    if (uploads.uploadQueue.length === 1) uploads.nextUpload()
  }
  function finishUpload() {
    uploads.uploadQueue = uploads.uploadQueue.slice(1)
    if (uploads.uploadQueue.length) Qt.callLater(uploads.nextUpload)
  }
  function nextUpload() {
    var item = uploads.uploadQueue[0]
    if (!item) return
    if (item.prepared) { uploads.uploadFile(item); return }
    var src = /^file:\/\//.test(item.src) ? decodeURIComponent(item.src.replace(/^file:\/\//, "")) : item.src
    prepareProc.command = ["sh", "-c",
      'case "$1" in http://*|https://*) n=$(basename "${1%%[?#]*}"); f="$2/drop-$(date +%s%N)-${n:-file}"; curl -sSfL -o "$f" -- "$1" || exit 1; tmp=1;; ' +
      '*) f="$1"; tmp=0;; esac; [ -f "$f" ] || exit 2; ' +
      'printf "%s %s %s %s\\n" "$(file -b --mime-type -- "$f")" "$(stat -c %s -- "$f")" "$tmp" "$f"', "sh", src, root.cacheDir]
    prepareProc.running = true
  }
  Process {
    id: prepareProc
    stdout: StdioCollector { id: prepareOut }
    onExited: function(code) {
      var item = uploads.uploadQueue[0]
      if (!item) return
      var out = prepareOut.text.trim()
      if (code !== 0 || !out) {
        notices.notify(code === 2 ? "Only files can be dropped, not folders." : "Could not read " + item.src.replace(/^file:\/\//, ""), true)
        uploads.finishUpload()
        return
      }
      var parts = out.split(" ")
      var path = parts.slice(3).join(" ")
      var name = path.replace(/^.*\//, "").replace(/^drop-\d+-/, "")
      item.prepared = { type: parts[0] || "application/octet-stream", size: parseInt(parts[1]), temp: parts[2] === "1", path: path, name: name }
      uploads.uploadFile(item)
    }
  }
  function uploadFile(item) {
    var f = item.prepared
    if (!(f.size > 0)) { notices.notify("“" + f.name + "” is empty.", true); if (f.temp) Quickshell.execDetached(["rm", "-f", f.path]); uploads.finishUpload(); return }
    notices.notify("Uploading “" + f.name + "”…" + (uploads.uploadQueue.length > 1 ? " (" + (uploads.uploadQueue.length - 1) + " more waiting)" : ""), false, root.icon.upload)
    root.gql(Linear.M_FILE_UPLOAD, { contentType: f.type, filename: f.name, size: f.size }, function(d) {
      var up = d.fileUpload.uploadFile
      var args = ["curl", "-sS", "-f", "-X", "PUT", "-H", "Content-Type: " + f.type, "-H", "Cache-Control: public, max-age=31536000"]
      ;(up.headers || []).forEach(function(h) { args.push("-H", h.key + ": " + h.value) })
      args.push("--data-binary", "@" + f.path, up.uploadUrl)
      uploadProc.asset = up.assetUrl
      uploadProc.command = args
      uploadProc.running = true
    }, function(msg) {
      if (f.temp) Quickshell.execDetached(["rm", "-f", f.path])
      notices.notify("Could not upload “" + f.name + "”: " + msg, true)
      uploads.finishUpload()
    })
  }
  Process {
    id: uploadProc
    property string asset: ""
    stderr: StdioCollector { id: uploadErr }
    onExited: function(code) {
      var item = uploads.uploadQueue[0]
      if (!item) return
      var f = item.prepared
      if (f.temp) Quickshell.execDetached(["rm", "-f", f.path])
      if (code !== 0) { notices.notify("Could not upload “" + f.name + "”: " + (uploadErr.text.trim() || "curl failed"), true); uploads.finishUpload(); return }
      var field = item.field
      if (field) {
        var image = /^image\//.test(f.type)
        var label = image && item.src === "clipboard" ? "image" : f.name.replace(/[\[\]]/g, "")
        var md = (image ? "!" : "") + "[" + label + "](" + asset + ")"
        var pos = Math.min(item.at, field.text.length)
        var before = field.text.slice(0, pos)
        var text = (before && !/\n$/.test(before) ? "\n" : "") + md + "\n"
        field.insert(pos, text)
        // Later files dropped at the same place go after this one.
        uploads.uploadQueue.slice(1).forEach(function(q) { if (q.field === field && q.at >= pos) q.at += text.length })
      }
      notices.notify((/^image\//.test(f.type) ? "Image" : "File") + " “" + f.name + "” added", false, root.icon.check)
      uploads.finishUpload()
    }
  }
}
