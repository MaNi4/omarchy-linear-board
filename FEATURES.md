# Linear Board: every feature

The full list. [README.md](README.md) has the install, the basics and what the board keeps outside Linear.
Press `?` in any window of the board for its keys.

## The board

- **Columns**: your team's workflow states. Rename, recolor, reorder, add or archive them (this changes Linear), or just hide them from this board.
- **Cards**: issues. Drag them between columns or press Shift+arrows. Cards show the due date (red when overdue), estimate, cycle, parent issue and sub-issue progress.
- **Cursor**: in a column with no cards, the column itself is outlined, so you can see where the cursor is.
- **View** (`v`): sort columns manually, by priority, due date, last updated or newest, and group cards by assignee, priority, project or label.
- **List layout** (`Ctrl+B`, or `v`): one row per issue, grouped by column; J/K run through the whole list; drag rows to another group or position.
- **Completed issues** (`V` → Completed): how long done and canceled issues stay on the board: none, past week, 2 weeks (the default), month, 3 months or all, like Linear's display options. An issue opened from the inbox, search or a link that is not on the board says why at the top of the editor (done long ago, another project or team, a hidden column, the filters, archived).
- **Filters** (`F` opens the list): labels (chips, keys 1–9, or F → Labels for any label), assignee (`a`, or `m` for your own issues), priority (`P`), cycle (the Cycle chip, or F → Cycle: current, none or a given cycle) and search (`/`).
- **Labels**: team and workspace labels; create new ones from the editor or settings.
- **Projects**: switch between "All issues" and one Linear project, or create new projects.
- **Bulk actions**: pick cards with Space or Ctrl+click (Ctrl+A picks every visible card), then change status, assignee, priority, label or project for all of them at once, or delete them (x).
- **Copy for development**: Ctrl+. issue ID, Ctrl+Shift+. git branch name (Linear's suggestion), Ctrl+Shift+, link, Ctrl+Alt+, Markdown link; also buttons in the editor. A toast says what was copied.
- **Sync**: the board refreshes every minute while it is open and when its window gets focus (not while an editor or dialog is open). Every list is paged, so big teams load completely.
- **Bar widget** "Linear inbox": the unread count in the bar. Click for the inbox, right click for the board. The board checks the inbox every minute, also while it is closed, and writes the count to `$XDG_RUNTIME_DIR/omarchy-linear-board/inbox.json` for the widget.

## The issue editor

- **Editor**: click a card to edit title, description, status, priority, labels, project, assignee (anyone in the team), due date, estimate, cycle and parent issue. It also lists sub-issues (add one with "Add sub-issue" or `N` on the board) and comments, and you can write new comments. Like in Linear, a saved issue saves itself: a change of status, labels, assignee… goes to Linear at once with a toast that undoes it, and the title and description save while you type (the footer says Saving… / Saved; `Ctrl+Z` outside the field undoes the typing); only the fields you changed are sent. A new issue is made with Create (`Ctrl+Enter`).
- **Editor extras**: descriptions and comments show as formatted Markdown (click the description to edit it); relations (blocks, blocked by, duplicate of, related; marking a duplicate moves the issue like Linear does) and the parent issue, both picked by typing an ID or words of the title with suggestions from the board and from Linear; links and attachments such as Sentry or GitHub (add a URL, remove one); the issue's history; edit or delete your own comments; type `@` in a comment to mention a teammate (Tab picks the first).
- **Markdown preview**: Preview under the description (or `Ctrl+Shift+P`) shows it as Linear will before you save; the same for a comment being written.
- **Checklists**: `- [ ] item` in a description, comment or project update shows a checkbox. Click the box or the item's text to tick it (links in it still open): in a saved description it is saved to Linear at once (if the description has other unsaved edits, it waits for Save with them), and in your own comments and updates too. Typing `[]` or `[ ]` and Space at the start of a line makes a checklist item, Enter starts the next one (Enter in an empty item ends the list; bullets and numbered lists continue the same way). Cards show the progress, e.g. ☑ 2/5.
- **Reactions and comments**: react with emoji to the issue (under its description) and to comments (click a reaction to add or take back yours); reply in a thread.
- **Images and files**: `Ctrl+V` with an image on the clipboard (e.g. a screenshot), or drag files (or an image from a browser) onto the description, a comment or a project update: they are uploaded to Linear and inserted, images as images, other files as links. Images in descriptions, comments and updates show inline (downloaded with your API key into `~/.cache/omarchy-linear-board/images`); click one to open it. On images in your own text (description, your comments and updates, a comment being written) hovering shows **Delete from Linear**: after asking, it takes the image out of the text, saves it, then deletes the file in Linear for good (Linear's internal `fileUploadDangerouslyDelete`). Before it changes any text, the board asks Linear once per session whether that mutation still exists; if Linear has dropped it, nothing is changed and the button hides.
- **Milestones**: pick one in the editor (after the project) or with `Shift+M`; cards show it. Add, rename, date or delete them in the project overview.
- **Remind me** (`Shift+R`, or in the editor): Linear's inbox reminds you in 1 or 3 hours, tomorrow, next Monday or in a week.
- **Duplicate and templates**: "Duplicate" in the editor; "Save as template" makes a Linear issue template, offered when creating issues (right click a template to delete it).

## Finding issues

- **Search all of Linear**: typing in the search field filters the board; Enter (or the chip under it) searches every issue in all your teams in Linear, old done ones and other projects included. Each result shows its project, team and status; opening one from another team switches the board to that team and opens it in the editor.
- **Open by link or ID**: paste `https://linear.app/…/issue/ENG-12/…` or type `ENG-12` into the search field (or the palette) and press Enter to open it in the editor.
- **Command palette** (`Ctrl+K`): every action by name (with its shortcut), issues by ID or title, a pasted Linear link, or "search Linear for…".
- **My issues in all teams** (`G then Y`): open issues assigned to you, in every team.
- **Clean up** (`Ctrl+K` → "Show every issue"): all of the team's issues, done ones of any age too, as one list with no project or filters. Select with `X` or `Ctrl+A`, then archive (`Ctrl+Shift+X`) or delete; `V` → Completed: Past 2 weeks goes back to the usual board. Archived issues leave the board and do not count toward the free plan's limit; Settings → Team archives all closed before a given day at once.

## Inbox

- **Inbox**: your Linear notifications (`i` or the inbox button). Open one to jump to the issue, mark read/unread, snooze (`s`), unsubscribe from the issue (`U`), archive, or mark all read. A row lists the other events it groups. Filter it by team, project and kind (assigned, mentions, comments, status…); "Mark all read" marks only what the filter shows. Opened from the board (button or `i`) it starts filtered to the board's project (with "All issues", to the board's team), and that button counts only that; clicking a notification from another team switches the board to that team; opened from the bar it starts on everything. New unread notifications also show as desktop notifications; clicking one opens it on the board (bell button in the inbox turns them off). The bar count and desktop notifications always cover the whole inbox. Like Linear, notifications about the same thing (an issue assigned and its priority set) are one row, and the counts are counted in rows, so they match Linear's own inbox. The inbox loads pages until it has every unread row.

## Time tracking

- **Time tracking** (Linear has none): start/stop a timer from the card (play button on hover), the editor, `T` on the selected card, or stop it from the bar, which shows the running issue and time. Add time by hand ("45m", "1h 30m", "1.5h", "1:30") with a date and note, edit or delete entries. `w` opens the report: day / week / month, by issue or project, CSV export for timesheets. Logged time is also posted to the issue as a comment (switch in the report). Entries are kept in `~/.local/share/omarchy-linear-board/time.json`, or in the shared folder (see [What lives outside Linear](README.md#what-lives-outside-linear)); entries logged on two computers before they synced are merged from Syncthing's conflict copy.
- **Timer**: runs shorter than 10 seconds are taken as a mis-click and dropped, with a notice. Stopping it from the bar while the board is closed always shows a desktop notification: what was logged, or that nothing was.
- **Away detection**: when you are idle for 5 minutes or the computer sleeps while a timer runs, a notification offers to remove that time.

## Cycles, projects and triage

- **Cycles** (`G then V` or `G then C`; `G then W` the upcoming one): the current cycle's issues with its progress; H / L for earlier or later cycles. Edit (`E`) renames a cycle, changes its description and dates, starts the upcoming one today, or archives it (its issues leave the cycle). Linear makes new cycles by itself, and its API cannot create one by hand, so Settings → Team → Cycles turns cycles on or off and sets their length, start day, cooldown and how many are made ahead (team admins).
- **Project overview** (`G then U`, or Settings → Projects → Overview): status, target date, progress, milestones, and project updates with health (on track / at risk / off track). Your own updates have Edit and Delete (Delete archives it, like Linear).
- **Triage** (`G then T` or `G then R`, or the Triage chip when the team has it on): accept (A) into the backlog or decline (D).

## Recurring issues

- **Recurring issues**: in the editor, Repeat… → every day, weekday, week or month. Each copy is a new issue (the earlier ones stay where they are, e.g. in Done) and its checklist starts unticked. The board creates each copy on its day while the shell runs (Linear's own recurring issues cannot be made through its API). Before creating it asks Linear whether an issue with that title was created that day already, and each copy's id is made from the rule and the day, so two computers with the same rules make it once even at the same moment. Renaming a repeating issue or moving it to another project (on the board, or in Linear: picked up within 10 minutes, when Settings → Recurring opens and before each copy) takes its rule along (copies use the new title and project); a duplicate in another project is not part of the series. A repeating issue shows ↻ on its card and a Repeat section (next date, Stop) in the editor's sidebar. Settings → Recurring lists them (click one to open its newest open issue) and removes them. Kept in `config.json`, and in the shared folder when one is set, so every computer has the same rules and marks the same copies as made.

## Archive and trash

- **Archive**: Ctrl+Shift+X or the editor / bulk bar button; Settings → Team archives every done or canceled issue closed more than N days ago (archived issues do not count toward the free plan's limit).
- **Archived and trash** (`G then X`, `Tab` switches): archived issues, which Linear keeps for good, and issues deleted in the last 30 days. `/` filters by ID (old ones too) or words of the title. Pick several with `X`, `Space` or Ctrl+click (`Ctrl+A` all shown), then restore (`R`) or delete: archived ones go to the trash, trashed ones are deleted for good (`Delete`, workspace admins only). `Enter` opens one in Linear. The footer shows how many issues count toward the Free plan's 250 (every team; archived and deleted ones do not). An archived issue also opens by its ID from the board's search field or `Ctrl+K`; the board's text search ("Search Linear") leaves archived ones out.

## Undo and offline

- **Undo** (`Ctrl+Z`): takes back the last change made on the board: a move, a bulk change, an editor save, a new issue (it goes to the trash), an archive or a delete (the issue comes back), a comment (added, edited or deleted; a deleted one is posted again as new, since Linear cannot restore it) or a relation (added or removed). The last 30 steps are kept. Each such change shows a toast; clicking it undoes that change.
- **Offline**: changes made without a connection wait in `~/.cache/omarchy-linear-board/outbox.json` and are sent in order when Linear answers again; the header shows "Offline · N waiting".
- **Lost answers and suspend**: a request Linear does not answer is given up after 30 seconds (8 seconds right after waking up) and the change waits in the outbox; a new issue or comment is never made twice when it is sent again, and an older change that arrives late never overwrites a newer one. After a hung connection (typically after a suspend) the board uses fresh connections for 15 minutes, so it does not stay on "Loading…".

## Keyboard

- **Keyboard like Linear**: H J K L or arrows move (Shift moves the issue), C new, E/Enter open, X select (then act on all), S status, P priority, A assignee, I assign to me, T labels (or Ctrl+L; add, or remove when all have it), Shift+P project, Shift+C cycle, Shift+E estimate, Shift+D due date (or Ctrl+D), R rename, Ctrl+M comment, Ctrl+Shift+O sub-issue, M then R/X/B relations, Shift+S subscribe, Ctrl+Shift+C current cycle, F filter, G then I/M/E/B/A/S/V/W/T/X… and O then T/P/U/C to go places, as in Linear. Where it differs: H J K L also move (so labels are T, not L), Space selects (Linear: peek), Shift+F clears the filters except the assignee (Linear: the last filter). Press `?` for the full list.
