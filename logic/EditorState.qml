import QtQuick
import "../Issues.js" as Issues

// The issue being edited: its fields, what was loaded for it (comments,
// relations, history…) and the editor's open menus and autocomplete.
// Part of the Linear board (mani4.linear-board): created in Board.qml as
// `ed`; the editor (ui/IssueEditor.qml) shows it and logic/EditorOps.qml and
// logic/IssueOps.qml change it.
QtObject {
  id: ed

  property string issueId: ""
  property var orig: null           // the issue as it was when the editor opened
  property string stateId: ""
  property int priority: 0
  property var labels: []
  property string projectId: ""
  property string assigneeId: ""
  property var estimate: null
  property string cycleId: ""
  property var parentIssue: null         // { id, identifier, title }
  property string milestoneId: ""
  property bool createMore: false    // after creating, open a new issue with the same choices
  property string menu: ""           // the editor's open property menu (status, labels…), "" when closed
  property string extra: ""          // "" | remind | repeat: the options row under the editor's header
  // Milestones of the project chosen in the editor.
  readonly property var milestones: {
    var all = ed.team.projects || []
    for (var i = 0; i < all.length; i++) if (all[i].id === ed.projectId) return all[i].milestones || []
    return []
  }
  readonly property string milestoneValid: ed.milestones.some(function(m) { return m.id === ed.milestoneId }) ? ed.milestoneId : ""
  property string identifier: ""
  property string url: ""
  property bool titleError: false
  property bool dueError: false
  property var comments: []
  property var subIssues: []
  property bool detailLoading: false
  property bool posting: false
  property int seq: 0
  property bool descPreview: false
  // A new issue for another team than the board's: that team's lists.
  property var teamData: null
  property bool teamLoading: false
  property int teamSeq: 0
  readonly property var team: ed.teamData || ({
    id: root.team ? root.team.id : "", key: root.team ? root.team.key : "", name: root.team ? root.team.name : "",
    states: root.states, labels: root.labels, projects: root.projects, members: root.members, cycles: root.cycles,
    estimateOptions: root.estimateOptions
  })
  property var relations: []
  property var attachments: []
  property var history: []
  property bool historyShown: false
  property bool historyLoading: false
  property string relKind: "related"
  property string editingCommentId: ""
  property var replyTo: null         // { id, author }: the comment a new comment answers
  property bool commentPreview: false
  property var reactions: []          // reactions on the issue itself
  property bool issueReactShown: false
  property string reactFor: ""       // comment showing its emoji choices
  readonly property var thread: Issues.threadComments(ed.comments)
  property var mention: null      // { query, start } while typing @name in a comment
  // Autocomplete for the relation and parent fields.
  property string suggestFor: ""       // relation | parent
  property string suggestText: ""
  property var suggestItems: []
  property var suggestRemote: []       // matches Linear search found for ed.suggestText
  property int suggestCursor: 0

}
