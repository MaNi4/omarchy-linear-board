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
import "../Inbox.js" as Inbox
import "../Issues.js" as Issues

// The inbox: loading notifications, desktop notifications and the inbox actions.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `inboxCtl`; it uses the board's state through the id `root` and the other
// parts through their ids (e.g. editor, issueOps).
Item {
  id: inboxCtl
  visible: false

  // ---- state: the notifications and the inbox window --------------------------------
  property var items: []
  property int unreadCount: 0
  property string since: ""      // newest notification seen, to spot new ones
  property bool loading: false
  property bool unreadOnly: true
  property int cursor: 0
  property string snoozeId: ""   // row showing its snooze choices
  property bool seenLoaded: false
  // For the bar widget (inbox.json): when this board started, the last good
  // check and the last error, so it can tell an old count from a current one.
  property string startedAt: ""
  property string checkedAt: ""
  property string lastError: ""
  property double loadingSince: 0
  property int loadSeq: 0
  // Linear stopped answering its internal inbox fields: use Q_INBOX_PUBLIC.
  property bool publicOnly: false
  Component.onCompleted: inboxCtl.startedAt = new Date().toISOString()
  // Set each time the inbox opens: from the board it starts on the board's
  // project, from the bar (or a summary notification) on everything.
  property var filter: ({ teamId: "", projectId: "", category: "" })
  readonly property bool filtered: !!(inboxCtl.filter.teamId || inboxCtl.filter.projectId || inboxCtl.filter.category)
  readonly property var matching: inboxCtl.items.filter(function(n) { return Inbox.inboxMatches(n, inboxCtl.filter) })
  readonly property var shown: inboxCtl.unreadOnly ? inboxCtl.matching.filter(function(n) { return !n.read }) : inboxCtl.matching
  readonly property int matchingUnread: inboxCtl.matching.filter(function(n) { return !n.read }).length
  readonly property var facets: Inbox.inboxFacets(inboxCtl.items, inboxCtl.filter)
  // The board's own inbox button counts only what the board shows: its
  // project, or with "All issues" its team (the bar widget counts everything).
  readonly property var boardFilter: ({ teamId: root.config.projectId || !root.team ? "" : root.team.id, projectId: root.config.projectId || "", category: "" })
  readonly property int boardUnread: root.config.projectId || root.team
    ? inboxCtl.items.filter(function(n) { return !n.read && Inbox.inboxMatches(n, inboxCtl.boardFilter) }).length
    : inboxCtl.unreadCount

  // ---- inbox ---------------------------------------------------------------------------
  // Checked every minute, also while the board is closed, so the bar widget
  // count and desktop notifications stay current.
  Timer {
    id: inboxTimer
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: root.keyChecked && root.apiKey !== "" && root.dirsReady && inboxCtl.seenLoaded
    onTriggered: {
      if (inboxCtl.loading && Inbox.loadStuck(inboxCtl.loadingSince, Date.now())) {
        console.warn("linear-board: an inbox check did not come back, starting a new one")
        inboxCtl.loading = false
      }
      if (!inboxCtl.loading) inboxCtl.loadInbox()
      issueOps.runRecurring()
    }
  }

  // The newest notification already seen, kept across shell restarts so
  // notifications that arrive meanwhile are still announced.
  FileView {
    id: seenFile
    path: root.dirsReady ? root.cacheDir + "/inbox-seen" : ""
    printErrors: false
    atomicWrites: true
    onLoaded: { if (!inboxCtl.since) inboxCtl.since = text().trim(); inboxCtl.seenLoaded = true }
    onLoadFailed: inboxCtl.seenLoaded = true
  }

  FileView {
    id: inboxFile
    path: root.dirsReady ? root.runtimeDir + "/inbox.json" : ""
    printErrors: false
    atomicWrites: true
  }

  function loadInbox() {
    if (!root.apiKey) return
    var seq = ++inboxCtl.loadSeq
    var publicOnly = inboxCtl.publicOnly
    inboxCtl.loading = true
    inboxCtl.loadingSince = Date.now()
    var count = -1   // Linear's unread count; -1 without it (the fallback query)
    var done = function() { if (seq === inboxCtl.loadSeq) inboxCtl.loading = false }
    sync.gqlAll(publicOnly ? Linear.Q_INBOX_PUBLIC : Linear.Q_INBOX, {}, function(d) {
      if (typeof d.notificationsUnreadCount === "number") count = d.notificationsUnreadCount
      return d.notifications
    }, function(nodes) {
      if (seq !== inboxCtl.loadSeq) return   // given up on, a newer check runs
      try {
        var list = Linear.toInbox(nodes, new Date().toISOString())
        var fresh = Inbox.newUnread(list, inboxCtl.since)
        inboxCtl.items = list
        inboxCtl.unreadCount = count >= 0 ? count : list.filter(function(n) { return !n.read }).length
        var newest = Inbox.newestTime(list)
        if (newest > inboxCtl.since) {
          inboxCtl.since = newest
          privateFiles.write(seenFile, newest + "\n")
        }
        inboxCtl.checkedAt = new Date().toISOString()
        inboxCtl.lastError = ""
        inboxCtl.clampInboxCursor()
        if (root.config.desktopNotify) inboxCtl.announce(fresh)
      } catch (e) {
        // An answer of an unexpected shape must not stop the next checks.
        console.warn("linear-board: could not read the inbox: " + e)
        inboxCtl.lastError = "Linear's answer could not be read"
      }
      done()
      inboxCtl.writeInboxState()
    }, function(msg) {
      if (seq !== inboxCtl.loadSeq) return
      done()
      if (!publicOnly && Linear.internalFieldsGone(msg)) {
        console.warn("linear-board: Linear no longer answers the internal inbox fields, using the public ones")
        inboxCtl.publicOnly = true
        inboxCtl.loadInbox()
        return
      }
      inboxCtl.lastError = msg
      inboxCtl.writeInboxState()
      if (panel.visible) notices.notify("Inbox: " + msg, true)
    }, publicOnly ? Linear.INBOX_PUBLIC_PAGES : Linear.INBOX_PAGES, function(nodes) {
      return Inbox.enoughUnread(Linear.toInbox(nodes, new Date().toISOString()), count)
    })
  }

  function writeInboxState() {
    if (!root.dirsReady) return
    var unread = inboxCtl.items.filter(function(n) { return !n.read }).slice(0, 5).map(function(n) {
      return { title: n.title, subtitle: n.subtitle, identifier: n.identifier }
    })
    var r = timeTracker.timeData.running
    privateFiles.write(inboxFile, JSON.stringify({ connected: !!root.apiKey, unread: inboxCtl.unreadCount, items: unread,
      startedAt: inboxCtl.startedAt, checkedAt: inboxCtl.checkedAt, error: inboxCtl.lastError,
      timer: r ? { identifier: r.identifier, title: r.title, startedAt: r.startedAt, projectName: r.projectName || "",
        projectCode: r.projectId && root.projectById(r.projectId) ? root.codeFor(r.projectId)
          : (r.projectName ? Issues.projectCode({ id: r.projectId || "", name: r.projectName }, root.config.projectCodes) : "") } : null,
      updatedAt: new Date().toISOString() }) + "\n")
  }

  // Desktop notifications for new unread ones; a summary when many arrive at once.
  function announce(fresh) {
    if (!fresh.length) return
    if (panel.visible && card.Window.active && root.dialog === "inbox") return
    if (fresh.length > 3) {
      inboxCtl.desktopNotify("Linear", fresh.length + " new notifications", "")
      return
    }
    fresh.forEach(function(n) {
      var body = [n.identifier, n.subtitle].filter(function(x) { return x }).join("  ·  ")
      if (n.snippet) body += (body ? "\n" : "") + n.snippet
      inboxCtl.desktopNotify(n.title || "Linear", body, n.id)
    })
  }

  // A desktop notification; clicking it opens that notification on the board
  // (or the inbox, for a summary).
  function desktopNotify(title, body, notificationId) {
    notices.desktopNote(title, body, notificationId ? { notification: notificationId } : { inbox: true }, 1)
  }

  function setInboxFilter(patch) {
    var f = {}
    for (var k in inboxCtl.filter) f[k] = inboxCtl.filter[k]
    for (var p in patch) f[p] = patch[p]
    inboxCtl.filter = f
    inboxCtl.cursor = 0
  }

  // filter: null for everything.
  function openInbox(filter) {
    inboxCtl.filter = filter || { teamId: "", projectId: "", category: "" }
    inboxCtl.cursor = 0
    root.dialog = "inbox"
    keyScope.forceActiveFocus()
    if (!inboxCtl.loading) inboxCtl.loadInbox()
  }

  function clampInboxCursor() {
    inboxCtl.cursor = Math.max(0, Math.min(inboxCtl.cursor, inboxCtl.shown.length - 1))
  }

  function patchNotification(id, patch) {
    inboxCtl.items = inboxCtl.items.map(function(n) {
      if (n.id !== id) return n
      var next = {}
      for (var k in n) next[k] = n[k]
      for (var p in patch) next[p] = patch[p]
      return next
    })
  }

  function setRead(n, read) {
    if (!n || n.read === read) return
    inboxCtl.patchNotification(n.id, { read: read })
    inboxCtl.unreadCount = Math.max(0, inboxCtl.unreadCount + (read ? -1 : 1))
    inboxCtl.clampInboxCursor()
    inboxCtl.writeInboxState()
    // A row can group several notifications; all of them change together.
    root.gql(Linear.markReadDocument(n.ids.length), Linear.markReadVariables(n.ids, read ? new Date().toISOString() : null),
      null, function(msg) { notices.notify("Could not update the notification: " + msg, true); inboxCtl.loadInbox() })
  }

  // A Linear link or an issue ID (ENG-12) opens that issue right away;
  // anything else searches.
  function openRef(ref, orElse) {
    var known = Issues.issueByIdentifier(root.issues.concat(root.extraIssues), ref)
    if (known) { pickers.closeDialog(); boardScreen.searchField.text = ""; root.openIssueAnywhere(known.id, known.url); return }
    root.gql(Linear.Q_ISSUE, { id: ref }, function(d) {
      var issue = Linear.toIssue(d.issue)
      if (!issue) { if (orElse) orElse(); else notices.notify("No issue " + ref + " in Linear.", true); return }
      boardScreen.searchField.text = ""
      lists.openSearchResult(issue)
    }, function() { if (orElse) orElse(); else notices.notify("No issue " + ref + " in Linear.", true) })
  }

  // An issue ID typed in the board's search field that is not on the board:
  // looked up in Linear (archived ones too) after a short pause, so the
  // field can say what it is and that Enter opens it.
  property string refAsked: ""
  property var refFound: null          // the issue, or null
  property bool refMissing: false      // Linear has no such issue
  readonly property string typedRef: {
    var ref = Issues.parseIssueRef(root.query)
    return ref && !Issues.issueByIdentifier(root.issues, ref) ? ref : ""
  }
  onTypedRefChanged: { inboxCtl.refFound = null; inboxCtl.refMissing = false; if (inboxCtl.typedRef) refTimer.restart() }
  Timer {
    id: refTimer
    interval: 350
    onTriggered: {
      var ref = inboxCtl.typedRef
      if (!ref || !root.apiKey) return
      inboxCtl.refAsked = ref
      root.gql(Linear.Q_ISSUE, { id: ref }, function(d) {
        if (inboxCtl.typedRef !== ref) return
        inboxCtl.refFound = Linear.toIssue(d.issue)
        inboxCtl.refMissing = !inboxCtl.refFound
      }, function() { if (inboxCtl.typedRef === ref) inboxCtl.refMissing = true })
    }
  }
  readonly property string refChipText: {
    var i = inboxCtl.refFound
    if (!inboxCtl.typedRef) return ""
    if (inboxCtl.refMissing) return "No issue " + inboxCtl.typedRef + " in Linear  ·  Enter searches the text"
    if (!i) return "Looking up " + inboxCtl.typedRef + " in Linear…"
    var where = i.archivedAt ? "archived" : (i.stateName || "")
    var title = i.title.length > 60 ? i.title.substring(0, 58) + "…" : i.title
    return "Open " + i.identifier + "  “" + title + "”  ·  " + where + (i.projectName ? " · " + i.projectName : "") + "  (Enter)"
  }

  function searchLinear(term) {
    term = String(term || "").trim()
    if (!term || !root.team) return
    var ref = Issues.parseIssueRef(term)
    if (ref) { inboxCtl.openRef(ref, function() { lists.runSearch(term) }); return }
    lists.runSearch(term)
  }

  function snoozeNotification(n, option) {
    if (!n) return
    var until = Dates.snoozeUntil(option, new Date())
    inboxCtl.snoozeId = ""
    inboxCtl.items = inboxCtl.items.filter(function(x) { return x.id !== n.id })
    if (!n.read) inboxCtl.unreadCount = Math.max(0, inboxCtl.unreadCount - 1)
    inboxCtl.clampInboxCursor()
    inboxCtl.writeInboxState()
    notices.notify("Snoozed until " + Qt.formatDateTime(until, "ddd d MMM HH:mm"))
    var vars = Linear.idVariables(n.ids)
    vars.until = until.toISOString()
    root.gql(Linear.snoozeDocument(n.ids.length), vars, null, function(msg) { notices.notify("Could not snooze: " + msg, true); inboxCtl.loadInbox() })
  }

  // Stop notifications about this issue (Linear's "Unsubscribe").
  function unsubscribeNotification(n) {
    if (!n || !n.issueId) return
    root.gql(Linear.M_UNSUBSCRIBE, { id: n.issueId }, function() {
      notices.notify("Unsubscribed from " + (n.identifier || "the issue"))
      inboxCtl.setRead(n, true)
    }, function(msg) { notices.notify("Could not unsubscribe: " + msg, true) })
  }

  function archiveNotification(n) {
    if (!n) return
    inboxCtl.items = inboxCtl.items.filter(function(x) { return x.id !== n.id })
    if (!n.read) inboxCtl.unreadCount = Math.max(0, inboxCtl.unreadCount - 1)
    inboxCtl.clampInboxCursor()
    inboxCtl.writeInboxState()
    root.gql(Linear.archiveDocument(n.ids.length), Linear.idVariables(n.ids), null,
      function(msg) { notices.notify("Could not archive: " + msg, true); inboxCtl.loadInbox() })
  }

  // Marks read what the inbox filter shows (all of it when there is no filter).
  function markAllRead() {
    var rows = inboxCtl.matching.filter(function(n) { return !n.read })
    if (!rows.length) return
    var rowIds = rows.map(function(n) { return n.id })
    var ids = [].concat.apply([], rows.map(function(n) { return n.ids }))
    inboxCtl.items = inboxCtl.items.map(function(n) {
      if (n.read || rowIds.indexOf(n.id) < 0) return n
      var next = {}
      for (var k in n) next[k] = n[k]
      next.read = true
      return next
    })
    inboxCtl.unreadCount = Math.max(0, inboxCtl.unreadCount - rows.length)
    inboxCtl.clampInboxCursor()
    inboxCtl.writeInboxState()
    root.gql(Linear.markReadDocument(ids.length), Linear.markReadVariables(ids, new Date().toISOString()),
      function() { inboxCtl.loadInbox() }, function(msg) { notices.notify("Could not mark all read: " + msg, true); inboxCtl.loadInbox() })
  }

  // Open what a notification is about: the issue editor when the issue is on
  // this board, Linear otherwise.
  function openNotification(n) {
    if (!n) return
    inboxCtl.setRead(n, true)
    if (n.issueId) {
      pickers.closeDialog()
      if (root.team && n.teamId && n.teamId !== root.team.id) lists.switchTeamAndEdit(n.teamId, n.issueId)
      else root.openIssueAnywhere(n.issueId, n.url)
    } else editorOps.openInLinear(n.url)
  }

  function toggleDesktopNotify() {
    root.setConfig({ desktopNotify: !root.config.desktopNotify })
  }
}
