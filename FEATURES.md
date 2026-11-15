# Linear Board: all features

The [README](README.md) covers installing and getting started. Press `?` in any window of the board to see its
shortcuts.

## Board

- **Columns** are your team's statuses. You can rename, recolor, reorder, add or archive them (this changes them in
  Linear), or just hide them on this board.
- **Cards** are issues. Drag them between columns or move them with `Shift` + arrow keys (or `Shift+H/J/K/L`). A card
  shows the priority, due date (red when overdue), estimate, cycle, milestone, parent issue and sub-issue progress.
- **View** (`V`): sort cards manually, by priority, due date, last update or creation date, and group them by
  assignee, priority, project or label.
- **List view** (`Ctrl+B`): one row per issue, grouped by status. You can drag rows too.
- **Completed issues** (`V` → Completed): choose how long done and canceled issues stay on the board, from none to
  all, like Linear's display options. The default is 2 weeks.
- **Filters** (`F`): by label (also keys `1`–`9`), assignee, priority, cycle and text (`/`). `G` then `M` shows only
  your issues, `Shift+F` clears the filters.
- **Projects**: switch between all issues and a single project, or create a new project.
- **Bulk changes**: select cards with `X`, `Space` or `Ctrl`+click (`Ctrl+A` selects all visible cards), then change
  their status, assignee, priority, labels, project, cycle, estimate or due date at once, or delete them.
- **Copying**: `Ctrl+.` copies the issue ID, `Ctrl+Shift+.` the git branch name, `Ctrl+Alt+.` the title,
  `Ctrl+Shift+,` the link and `Ctrl+Alt+,` a Markdown link.
- **Refresh**: the board reloads every minute while it's open and when you switch back to it. `Ctrl+R` reloads now.
- **Bar icon**: shows the number of unread notifications. Click it for the inbox, right-click it for the board.
  While a timer runs, the bar also shows the issue and the time.

## Issue editor

- **Editing**: click a card or press `Enter` to open it. You can change the title, description, status, priority,
  labels, project, milestone, assignee, due date, estimate, cycle and parent issue. Like in Linear, changes are saved
  right away, and the title and description are saved as you type. A new issue is created with `Ctrl+Enter`.
- **Sub-issues and relations**: add a sub-issue with "Add sub-issue" or `Ctrl+Shift+O`. Add relations (blocks,
  blocked by, duplicate of, related to) by typing an issue ID or part of its title.
- **Links** to other pages, such as Sentry or GitHub, and the issue's **history**.
- **Comments**: write, reply, edit and delete your own, mention people with `@`, and add emoji reactions to comments
  and to the issue.
- **Markdown**: descriptions and comments are shown formatted. Click the description to edit it, or press
  `Ctrl+Shift+P` to preview it.
- **Checklists**: `- [ ]` at the start of a line makes a checkbox. Click it to tick it off, and the change is saved
  to Linear. Typing `[]` and `Space` starts a checklist item, `Enter` adds the next one. Cards show the progress,
  for example ☑ 2/5.
- **Images and files**: paste an image with `Ctrl+V` or drag files onto the description, a comment or a project
  update. They're uploaded to Linear. Images appear right in the text, and you can delete images from your own text
  in Linear too.
- **Reminders** (`Shift+R`): Linear reminds you about the issue in 1 or 3 hours, tomorrow, next Monday or in a week.
- **Duplicate and templates**: "Duplicate" opens a copy of the issue to create. "Save as template" creates a Linear
  issue template, which you can then pick when creating an issue.

## Finding issues

- **Search**: typing in the search field filters the board. `Enter` searches all issues in all your teams in Linear,
  including old and done ones.
- **Open by link or ID**: paste a Linear issue link or type an ID such as `ENG-12` into the search field or `Ctrl+K`.
- **Command palette** (`Ctrl+K`): find any action by name, with its shortcut, or an issue by ID or title.
- **My issues** (`G` then `Y`): your open issues from all teams.
- **Cleanup** (`Ctrl+K` → "Show every issue"): all of the team's issues in one list, including done ones of any age.
  Select some and archive or delete them.

## Inbox

- Open it with `G` then `I`, the inbox button on the board or the bar icon. It shows your Linear notifications,
  grouped like in Linear: an issue assigned to you and its priority change are one row.
- In the inbox: `Enter` opens the issue, `U` marks a row read or unread, `S` snoozes it, `Shift+U` unsubscribes you
  from the issue, `X` archives it and `Shift+A` marks everything shown as read.
- Filter by team, project and kind (assigned, mentions, comments, status changes…). Opened from the board, the inbox
  shows the board's project or team first. Opened from the bar, it shows everything.
- New notifications also appear as desktop notifications. Clicking one opens it on the board. The bell button in the
  inbox turns them off.

## Time tracking

Linear has no time tracking, so the board adds it.

- **Timer**: start or stop it with the play button on a card, in the editor, with `Shift+T`, or stop it from the bar.
  A timer that ran less than 10 seconds is treated as a mis-click and discarded.
- **Adding time by hand**: type a duration like `45m`, `1h 30m`, `1.5h` or `1:30`, with a date and an optional note.
  You can edit and delete entries.
- **Report** (`W`): time by day, week or month, by issue or project, with a CSV export for timesheets.
- **Comments**: logged time is also posted to the issue as a comment. You can turn this off in the report.
- **Away time**: if you're idle for 5 minutes or the computer sleeps while a timer runs, a notification offers to
  remove that time.
- Entries are saved in `~/.local/share/omarchy-linear-board/time.json`, or in the shared folder (see
  [Using it on several computers](README.md#using-it-on-several-computers)).

## Cycles, projects and triage

- **Cycles** (`G` then `V`, or `G` then `W` for the next one): the cycle's issues and progress. `H` and `L` move to
  earlier and later cycles, `E` edits the name, description and dates. Turn cycles on and set their length in
  Settings → Team (Linear creates new cycles by itself).
- **Project overview** (`G` then `U`): status, target date, progress, milestones and project updates with their health
  (on track, at risk, off track). You can edit and delete your own updates.
- **Triage** (`G` then `T`, when the team uses triage): accept issues into the backlog with `A` or decline them with `D`.

## Recurring issues

- In the editor, choose ⋯ → Repeat: every day, weekday, week or month. On each date, the board creates a new copy
  of the issue with the checklist unticked. Earlier copies stay where they are.
- Linear's API can't create Linear's own recurring issues, so the board creates the copies itself while the shell is
  running. It checks Linear first, so a copy is never created twice, not even by two computers at the same time.
- If you rename the issue or move it to another project, later copies follow.
- Settings → Recurring lists all recurring issues. You can stop one there or in the editor.

## Archive and trash

- **Archive** an issue with `Ctrl+Shift+X` or the button in the editor. Settings → Team archives all issues closed
  more than a given number of days ago. Archived issues don't count toward the free plan's limit of 250.
- **Archived and trash** (`G` then `X`, `Tab` switches between them): restore issues with `R`, or delete them. Linear
  keeps deleted issues in the trash for 30 days. The footer shows how many issues count toward the free plan.

## Undo and offline

- **Undo** (`Ctrl+Z`): undoes your last change on the board, such as a move, a bulk change, an edit, a new or deleted
  issue, an archive, a comment or a relation. The last 30 changes are kept. You can also click the toast that appears
  after each change.
- **Offline**: changes you make without a connection are kept and sent in order when Linear is reachable again. The
  header shows "Offline · N waiting". A change is never sent twice and an older change never overwrites a newer one.
- **After sleep**: the board notices when the computer wakes up and replaces connections that stopped working, so it
  doesn't get stuck loading.

## Shortcuts

Most of Linear's shortcuts work the same way: `C` new issue, `Enter` or `E` open, `S` status, `P` priority,
`A` assignee, `I` assign to me, `Shift+P` project, `Shift+C` cycle, `Shift+E` estimate, `Shift+D` due date,
`R` rename, `Ctrl+M` comment, `M` then `R`, `X` or `B` for relations, `Shift+S` subscribe, and `G` or `O` followed by
a letter to go somewhere.

A few differ from Linear:

- `H`, `J`, `K`, `L` move the cursor, so labels are `T` instead of `L`.
- `Space` selects a card instead of opening a preview.
- `Shift+F` clears all filters except the assignee.

Press `?` for the full list.
