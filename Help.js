.pragma library

// Shortcut help shown per window (board, issue editor, inbox…): titles and
// sections of [keys, text] rows. In a key list, "then", "+" and "–" are words between keys.

var TITLES = { board: "Board", issue: "Issue editor", inbox: "Inbox", search: "Search and lists", time: "Time", settings: "Settings", project: "Project overview" }

var SECTIONS = {
  board: [
    { title: "Start here", rows: [
      [["Click"], "Open the issue in the editor"], [["Drag"], "Move a card to another column or place"],
      [["Ctrl+click"], "Select several cards, then change them all"], [["Hover", "then", "▶"], "Timer on the card"],
      [["Double-click"], "Empty part of a column: new issue there; column title: columns settings"],
      [[], "Hover any button to see what it does and its key."],
      [["Ctrl+K"], "Find any action by name, with its key"], [["?"], "Help for the window you are in (F1 also while typing)"] ] },
    { title: "Move", rows: [
      [["H", "J", "K", "L"], "Left, down, up, right (or arrows)"],
      [["Shift", "+", "H J K L"], "Move the issue, or all picked ones (or Shift + arrows)"], [["Enter"], "Open the issue (or E)"], [["C"], "New issue (or N)"] ] },
    { title: "Change the issue", rows: [
      [["S"], "Status"], [["P"], "Priority"], [["A"], "Assignee"], [["I"], "Assign to me"],
      [["T"], "Labels (tags): add, or remove when ✓ (or Ctrl+L)"], [["Shift+P"], "Project"], [["Shift+C"], "Cycle"], [["Ctrl+Shift+C"], "Current cycle"],
      [["Shift+E"], "Estimate"], [["Shift+D"], "Due date (or Ctrl+D)"], [["Ctrl+Shift+D"], "Remove the due date"], [["R"], "Rename"], [["Ctrl+M"], "Comment"],
      [["Shift+S"], "Subscribe"], [["Shift+M"], "Milestone"], [["Shift+R"], "Remind me"] ] },
    { title: "Select several", rows: [
      [["X"], "Select / unselect the card (or Space)"], [["Ctrl+A"], "Select every visible card"],
      [["Esc"], "Clear the selection"], [[], "The keys for changing an issue then change every selected card."] ] },
    { title: "Copy", rows: [
      [["Ctrl+."], "Issue ID"], [["Ctrl+Alt+."], "Title"], [["Ctrl+Shift+."], "Git branch name"], [["Ctrl+Shift+,"], "Link"],
      [["Ctrl+Alt+,"], "Markdown link"] ] },
    { title: "Sub-issues and relations", rows: [
      [["Ctrl+Shift+O"], "New sub-issue"], [["Ctrl+Shift+↑"], "Open the parent"], [["Ctrl+Shift+↓"], "Open a sub-issue"],
      [["M", "then", "R"], "Related to…"], [["M", "then", "X"], "Blocks…"], [["M", "then", "B"], "Blocked by…"] ] },
    { title: "Find and view", rows: [
      [["/"], "Filter by text; Enter searches all of Linear"], [["F"], "Filters: assignee, priority, labels, project, cycle, text"],
      [["Shift+F"], "Clear filters (keeps the assignee)"], [["Alt+Shift+F"], "Clear all filters"],
      [["1", "–", "9"], "Filter by label"], [["V"], "Layout, sort, group, and how long done issues stay"], [["Ctrl+B"], "Board or list"],
      [["Ctrl+K"], "Command palette: any action, issue ID or Linear link"] ] },
    { title: "Go to", rows: [
      [["G", "then", "I"], "Inbox"], [["G", "then", "M"], "My issues"], [["G", "then", "E"], "All issues"],
      [["G", "then", "B"], "Backlog"], [["G", "then", "A"], "Started (active)"], [["G", "then", "S"], "Settings (or ,)"],
      [["G", "then", "P"], "Project settings"], [["O", "then", "T"], "Another team"],
      [["O", "then", "P"], "A project"], [["O", "then", "U"], "A person's issues"],
      [["O", "then", "C"], "A cycle (filter the board)"], [["G", "then", "D"], "The board (from the list layout)"],
      [["G", "then", "Y"], "My issues in all teams"], [["G", "then", "V"], "Current cycle (or G then C)"], [["G", "then", "W"], "Upcoming cycle"],
      [["G", "then", "U"], "Project overview"], [["G", "then", "T"], "Triage (or G then R)"], [["G", "then", "X"], "Archived issues (Tab: trash)"] ] },
    { title: "Time and more", rows: [
      [["Ctrl+Z"], "Undo the last change"], [["Shift+T"], "Start / stop the timer"], [["W"], "Time report"], [["Ctrl+Shift+X"], "Archive"],
      [["Ctrl+Backspace"], "Delete (or Delete)"], [["Ctrl+O"], "Open in Linear"], [["Ctrl+R"], "Refresh (or F5)"],
      [["?"], "This help (F1 also while typing)"] ] }
  ],
  issue: [
    { title: "Start here", rows: [
      [["Click a pill"], "Change status, priority, labels… (or the letter key below)"],
      [["Click the text"], "Edit the description; Preview shows it as Linear will"],
      [["Drag a file"], "Upload it to Linear into the description or a comment"],
      [[], "Hover any button or pill to see what it does and its key. In a saved issue every change goes to Linear at once, like in Linear: a property change shows a toast that undoes it, text saves as you type (the footer says Saved). A new issue is made with Create (Ctrl+Enter)."] ] },
    { title: "Save and close", rows: [
      [["Ctrl+Enter"], "New issue: create it. Saved issue: close (in a comment: send it)"], [["Esc"], "Close (a new issue is not created)"], [["Ctrl+Z"], "Undo the last change"], [["Enter"], "In the title: go to the description"] ] },
    { title: "Checklists", rows: [
      [["[ ]", "Space"], "At the start of a line: a checklist item"], [["Enter"], "Next item (in an empty item: end the list)"],
      [["Click ☐ or its text"], "Tick it; saved to Linear at once"] ] },
    { title: "Copy", rows: [
      [["Ctrl+."], "Issue ID"], [["Ctrl+Shift+."], "Git branch name"], [["Ctrl+Shift+,"], "Link"], [["Ctrl+Alt+,"], "Markdown link"] ] },
    { title: "Jump", rows: [
      [["Ctrl+M"], "Write a comment"], [["Ctrl+Shift+D"], "Remove the due date"],
      [["Ctrl+Shift+O"], "New sub-issue"], [["Ctrl+Shift+↑"], "Open the parent"], [["Ctrl+Shift+↓"], "Open a sub-issue"],
      [["Ctrl+Shift+P"], "Preview the description (or the comment being written)"] ] },
    { title: "Same keys as on the board", rows: [
      [["S"], "Status"], [["P"], "Priority"], [["A"], "Assignee"], [["I"], "Assign to me"], [["T"], "Labels"],
      [["Shift+P"], "Project"], [["Shift+M"], "Milestone"], [["Shift+C"], "Cycle"], [["Shift+E"], "Estimate"],
      [["Shift+D"], "Due date"], [["R"], "Rename (to the title)"], [["E"], "Edit the description"], [["Shift+T"], "Start / stop the timer"],
      [["Shift+R"], "Remind me, repeat, template, duplicate (⋯ menu)"], [["Ctrl+Shift+C"], "Current cycle"],
      [["Ctrl+Backspace"], "Delete (or Delete)"], [["Ctrl+Shift+X"], "Archive"], [["Ctrl+O"], "Open in Linear"],
      [[], "They work when you are not typing in a field; Esc leaves a field. While typing, use Alt + the letter: Alt+S, Alt+D, Alt+M… (only project is Alt+Shift+P, since Alt+P is priority)"] ] },
    { title: "More properties", rows: [
      [["Alt+U"], "Parent issue"], [["Alt+Shift+T"], "Team (new issue)"], [["Tab"], "Next field or pill; Enter / Space opens a pill"],
      [["↑", "↓", "Enter"], "In a menu: choose; typing filters, Esc closes"] ] },
    { title: "While typing", rows: [
      [["@"], "Mention someone in a comment"], [["Ctrl+V"], "Paste an image (uploaded to Linear)"], [["Tab"], "Pick the first suggestion"],
      [["↑", "↓"], "Choose in issue suggestions"], [["Enter"], "Use the suggestion"] ] }
  ],
  inbox: [
    { title: "Inbox", rows: [
      [["J"], "Down"], [["K"], "Up"], [["Enter"], "Open"], [["U"], "Read / unread"], [["S"], "Snooze, then 1 – 3"],
      [["Shift+U"], "Unsubscribe from the issue"], [["X"], "Archive"], [["Shift+A"], "Mark what is shown as read"],
      [["A"], "Unread only / everything"], [["Esc"], "Close"] ] }
  ],
  search: [
    { title: "Search results", rows: [
      [["J"], "Down"], [["K"], "Up"], [["Enter"], "Open in the editor"], [["O"], "Open in Linear"], [["Esc"], "Close"] ] },
    { title: "Cycles", rows: [ [["H"], "Earlier cycle"], [["L"], "Later cycle"], [["E"], "Edit the cycle: name, dates, start today, archive"],
      [["Enter"], "In the cycle fields: save"], [["Esc"], "In the cycle fields: stop editing"] ] },
    { title: "Archived and trash", rows: [ [["Tab"], "Archived ↔ trash"], [["/"], "Filter by ID or title words (Esc clears)"],
      [["X"], "Pick / unpick (or Space, Ctrl+click)"], [["Ctrl+A"], "Pick all shown (again: none)"], [["Esc"], "Clear what is picked"],
      [["R"], "Restore the picked ones (or the one under the cursor)"], [["Delete"], "Archived: to the trash. Trash: delete for good (admins only)"],
      [["Enter"], "Open in Linear"], [[], "Archived issues do not count toward the Free plan's 250; the footer shows how many do."] ] },
    { title: "Triage", rows: [ [["A"], "Accept into the backlog"], [["D"], "Decline (cancel)"] ] }
  ],
  project: [
    { title: "Project overview", rows: [
      [["Enter"], "In a field: save it"], [["Ctrl+Enter"], "Post the update (or save the one you edit)"], [["Ctrl+V"], "Paste an image into the update"],
      [["Esc"], "Stop editing an update, else close"], [[], "Edit / Delete next to your own updates change them in Linear."] ] }
  ],
  time: [
    { title: "Time report", rows: [
      [["D"], "Day"], [["W"], "Week"], [["M"], "Month"], [["←"], "Earlier"], [["→"], "Later"],
      [["Shift+T"], "Stop the running timer"], [["Enter"], "In the fields: add the time"], [["Esc"], "Close"] ] }
  ],
  settings: [
    { title: "Settings", rows: [ [["Enter"], "Save the field"], [["Esc"], "Close"] ] }
  ]
}
