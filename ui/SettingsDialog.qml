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
import "../Recur.js" as Recur

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// settings
Rectangle {
  id: settings
  z: 62
  visible: root.dialog === "settings"
  anchors.centerIn: parent
  width: Math.min(parent.width - Style.space(40), Style.space(720))
  height: Math.min(parent.height - Style.space(40), Style.space(640))
  radius: root.radius
  color: root.bg
  border.width: 1
  border.color: Util.alpha(root.fg, 0.25)
  MouseArea { anchors.fill: parent }

  Item {
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding

    RowLayout {
      id: tabs
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.spacing.sm
      Repeater {
        model: [
          { id: "columns", label: "Columns" },
          { id: "labels", label: "Labels" },
          { id: "projects", label: "Projects" },
          { id: "team", label: "Team" },
          { id: "recurring", label: "Recurring" },
          { id: "keys", label: "Keys" },
          { id: "data", label: "Data" },
          { id: "account", label: "Account" }
        ]
        delegate: Chip {
          required property var modelData
          text: modelData.label
          fontSize: Style.font.body
          tint: root.accent
          selected: root.settingsTab === modelData.id
          onClicked: root.settingsTab = modelData.id
        }
      }
      Item { Layout.fillWidth: true }
      Label { text: root.team ? root.team.name : ""; opacity: 0.5 }
      Button { iconText: root.icon.help; tooltipText: "Shortcuts here (?)"; onClicked: keyboard.openHelp("settings") }
      Button { tooltipText: "Close (Esc)"; iconText: root.icon.close; onClicked: pickers.closeDialog() }
    }

    Flickable {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: tabs.bottom
      anchors.bottom: parent.bottom
      anchors.topMargin: Style.spacing.xxl
      contentHeight: settingsBody.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: settingsBody
        width: parent.width
        spacing: Style.spacing.md

        // --- columns tab ---
        Label {
          visible: root.settingsTab === "columns"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Columns are your team's workflow states in Linear. Renaming, recoloring, adding and archiving changes them in Linear for the whole team; hiding only affects this board. Click a dot to change its color."
        }
        Repeater {
          model: root.settingsTab === "columns" ? root.states.length : 0
          delegate: RowLayout {
            required property int index
            readonly property var st: root.states[index]
            readonly property bool hidden: Issues.isHidden(st, root.hiddenStates)
            width: settingsBody.width
            spacing: Style.spacing.md

            Rectangle {
              Layout.preferredWidth: Style.space(18)
              Layout.preferredHeight: Style.space(18)
              radius: width / 2
              color: st.color
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: workspace.updateState(st.id, { color: Issues.nextColor(st.color) }) }
            }
            TextBox {
              Layout.fillWidth: true
              text: st.name
              opacity: hidden ? 0.5 : 1
              onEditingFinished: if (text.trim() && text.trim() !== st.name) workspace.updateState(st.id, { name: text.trim() })
              Keys.onReturnPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
            }
            Label { text: Linear.typeLabel(st.type); opacity: 0.5; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(80) }
            Label { readonly property int n: Issues.issuesIn(root.issues, st.id).length; text: n + (n === 1 ? " issue" : " issues"); opacity: 0.5; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(60) }
            Button { iconText: hidden ? root.icon.eyeOff : root.icon.eye; tooltipText: hidden ? "Show on board" : "Hide from board"; onClicked: workspace.toggleStateHidden(st.id) }
            Button { iconText: root.icon.left; tooltipText: "Move left"; onClicked: workspace.moveState(st.id, -1) }
            Button { iconText: root.icon.right; tooltipText: "Move right"; onClicked: workspace.moveState(st.id, 1) }
            Button { iconText: root.icon.trash; tooltipText: "Archive"; foreground: root.urgent; onClicked: workspace.archiveState(st) }
          }
        }
        Item { visible: root.settingsTab === "columns"; width: 1; height: Style.spacing.lg }
        SectionTitle { visible: root.settingsTab === "columns"; text: "Add column" }
        Flow {
          visible: root.settingsTab === "columns"
          width: parent.width
          spacing: Style.spacing.sm
          Repeater {
            model: Linear.STATE_TYPES
            delegate: Chip {
              required property var modelData
              text: modelData.label
              tint: root.accent
              selected: newStateField.type === modelData.type
              onClicked: newStateField.type = modelData.type
            }
          }
        }
        RowLayout {
          visible: root.settingsTab === "columns"
          width: parent.width
          TextBox {
            id: newStateField
            property string type: "started"
            Layout.fillWidth: true
            placeholderText: "Column name, e.g. In Review"
            Keys.onReturnPressed: function(event) { workspace.addState(text, type); text = ""; event.accepted = true }
          }
          Button { tooltipText: "Add the column (Enter in the field)"; text: "Add"; iconText: root.icon.plus; bordered: true; onClicked: { workspace.addState(newStateField.text, newStateField.type); newStateField.text = "" } }
        }

        // --- labels tab ---
        Label {
          visible: root.settingsTab === "labels"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Labels of this team plus workspace labels. Changes go straight to Linear. Click a dot to change its color."
        }
        Repeater {
          model: root.settingsTab === "labels" ? root.labels.length : 0
          delegate: RowLayout {
            required property int index
            readonly property var l: root.labels[index]
            width: settingsBody.width
            spacing: Style.spacing.md
            Rectangle {
              Layout.preferredWidth: Style.space(18)
              Layout.preferredHeight: Style.space(18)
              radius: width / 2
              color: l.color
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: workspace.updateLabel(l.id, { color: Issues.nextColor(l.color) }) }
            }
            TextBox {
              Layout.fillWidth: true
              text: l.name
              onEditingFinished: if (text.trim() && text.trim() !== l.name) workspace.updateLabel(l.id, { name: text.trim() })
              Keys.onReturnPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
            }
            Button { iconText: root.icon.trash; tooltipText: "Delete label"; foreground: root.urgent; onClicked: workspace.deleteLabel(l) }
          }
        }
        RowLayout {
          visible: root.settingsTab === "labels"
          width: parent.width
          TextBox {
            id: newLabelSettingsField
            Layout.fillWidth: true
            placeholderText: "New label name"
            Keys.onReturnPressed: function(event) { workspace.addLabel(text); text = ""; event.accepted = true }
          }
          Button { tooltipText: "Add the label (Enter in the field)"; text: "Add label"; iconText: root.icon.plus; bordered: true; onClicked: { workspace.addLabel(newLabelSettingsField.text); newLabelSettingsField.text = "" } }
        }

        // --- keys tab: the global Hyprland keys (Service.qml binds them) ---
        Label {
          visible: root.settingsTab === "keys"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Keys that work everywhere, also while the board is closed. The plugin binds them in Hyprland itself and never takes a key something else uses. Pick a free one, or type your own (e.g. super + alt + l) and press Enter. Kept in " + hotkeys.configPath.replace(root.home, "~") + "."
        }
        Repeater {
          model: root.settingsTab === "keys" ? hotkeys.settings : []
          delegate: Column {
            id: keyRow
            required property var modelData
            width: settingsBody.width
            spacing: Style.spacing.sm
            readonly property string current: hotkeys.config[modelData.id] || ""
            Item { width: 1; height: Style.spacing.md }
            Row {
              spacing: Style.spacing.md
              SectionTitle { text: keyRow.modelData.label; anchors.verticalCenter: parent.verticalCenter }
              Label {
                text: keyRow.current || "no key"
                color: keyRow.current ? root.accent : root.fg
                font.bold: true
                opacity: keyRow.current ? 1 : 0.5
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            TextBox {
              id: keyInput
              width: Math.min(parent.width, Style.space(320))
              placeholderText: "Type a key, e.g. super + alt + l"
              Keys.onReturnPressed: function(event) { if (text.trim()) { hotkeys.setHotkey(keyRow.modelData.id, text); text = "" } event.accepted = true }
            }
            Flow {
              width: parent.width
              spacing: Style.spacing.sm
              Repeater {
                model: hotkeys.choices(keyRow.modelData.id, keyInput.text)
                delegate: Chip {
                  required property var modelData
                  text: modelData.hotkey + (modelData.holder ? "  · used by " + modelData.holder : "")
                  tint: root.accent
                  selected: modelData.hotkey === keyRow.current
                  opacity: modelData.holder ? 0.45 : 1
                  tip: modelData.holder ? "Taken: " + modelData.holder : "Free"
                  onClicked: if (!modelData.holder) { hotkeys.setHotkey(keyRow.modelData.id, modelData.hotkey); keyInput.text = "" }
                }
              }
              Chip {
                tip: "No global key for this"
                text: "No key"
                tint: root.accent
                selected: keyRow.current === ""
                onClicked: hotkeys.setHotkey(keyRow.modelData.id, "")
              }
            }
          }
        }

        // --- recurring tab ---
        Label {
          visible: root.settingsTab === "recurring"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Issues the board creates again on a schedule (all teams). Add one from an issue: open it → Repeat… The copy is made on its day while the shell runs (any time that day); if an issue with the same title was already created that day, for example by another computer, it is skipped. If the computer was off for several days, only the latest copy is made."
        }
        Label {
          visible: root.settingsTab === "recurring" && !(root.config.recurring || []).length
          text: "No recurring issues yet."
          opacity: 0.5
        }
        Repeater {
          model: root.settingsTab === "recurring" ? (root.config.recurring || []) : []
          // Click a row to open its issue.
          delegate: Item {
            required property var modelData
            width: settingsBody.width
            height: recurRow.implicitHeight + Style.spacing.sm * 2
          Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: recurMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent"
          }
          MouseArea {
            id: recurMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: issueOps.openRecurring(modelData)
          }
          RowLayout {
            id: recurRow
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.spacing.md
            Label { text: root.icon.repeat; color: root.accent }
            Label { text: modelData.title; Layout.fillWidth: true; font.bold: true }
            Label { text: (modelData.teamName || "") + (modelData.projectId && root.projectById(modelData.projectId) ? " · " + root.projectById(modelData.projectId).name : ""); opacity: 0.5; font.pixelSize: Style.font.caption }
            Label { text: Recur.recurLabel(modelData.every); font.pixelSize: Style.font.caption }
            Label {
              text: "next " + Recur.recurNext(modelData, modelData.last && modelData.last >= root.today ? modelData.last : Dates.isoDate(Dates.addDays(new Date(), -1)))
              opacity: 0.6
              font.pixelSize: Style.font.caption
            }
            Button { iconText: root.icon.trash; foreground: root.urgent; tooltipText: "Stop repeating (issues already made stay)"; onClicked: issueOps.deleteRecurring(modelData.id) }
          }
          }
        }

        // --- projects tab ---
        Label {
          visible: root.settingsTab === "projects"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Active Linear projects of this team. Pick one to show only its issues on the board. The short code on the left (e.g. WEB) is shown next to issue ids on this board only; Linear's ids keep the team prefix."
        }
        Repeater {
          model: root.settingsTab === "projects" ? root.projects.length : 0
          delegate: RowLayout {
            required property int index
            readonly property var p: root.projects[index]
            width: settingsBody.width
            spacing: Style.spacing.md
            Dot { dotColor: p.color; Layout.preferredWidth: Style.space(12); Layout.preferredHeight: Style.space(12) }
            TextBox {
              // Short code shown next to issue ids on the board.
              Layout.preferredWidth: Style.space(110)
              text: root.codeFor(p.id)
              placeholderText: "Code"
              onEditingFinished: root.setProjectCode(p.id, text)
              Keys.onReturnPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
            }
            TextBox {
              Layout.fillWidth: true
              text: p.name
              onEditingFinished: workspace.renameProject(p.id, text)
              Keys.onReturnPressed: function(event) { keyScope.forceActiveFocus(); event.accepted = true }
            }
            Button { text: "Overview"; tooltipText: "Status, target date, milestones and updates (G then U)"; onClicked: projectOps.openProject(p.id) }
            Chip {
              tip: "Show this project on the board (O then P)"
              text: root.config.projectId === p.id ? "On board" : "Show on board"
              tint: root.accent
              selected: root.config.projectId === p.id
              onClicked: workspace.setProject(root.config.projectId === p.id ? "" : p.id)
            }
          }
        }
        RowLayout {
          visible: root.settingsTab === "projects"
          width: parent.width
          TextBox {
            id: newProjectField
            Layout.fillWidth: true
            placeholderText: "New project name"
            Keys.onReturnPressed: function(event) { workspace.addProject(text); text = ""; event.accepted = true }
          }
          Button { tooltipText: "Create the project in Linear (Enter in the field)"; text: "Create project"; iconText: root.icon.plus; bordered: true; onClicked: { workspace.addProject(newProjectField.text); newProjectField.text = "" } }
        }

        // --- team tab ---
        Label {
          visible: root.settingsTab === "team"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "The team is the level above projects: it owns the columns, labels and projects on this board. Renaming changes it in Linear for everyone (may need team admin rights). The workspace above teams can only be renamed in Linear's own settings."
        }
        SectionTitle { visible: root.settingsTab === "team"; text: "Team name" }
        RowLayout {
          visible: root.settingsTab === "team"
          width: parent.width
          TextBox {
            id: teamNameField
            Layout.fillWidth: true
            text: root.team ? root.team.name : ""
            Keys.onReturnPressed: function(event) { workspace.renameTeam(text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          Button { tooltipText: "Rename the team in Linear (Enter in the field)"; text: "Rename"; bordered: true; onClicked: workspace.renameTeam(teamNameField.text) }
        }
        SectionTitle { visible: root.settingsTab === "team"; text: "Issue prefix" }
        RowLayout {
          visible: root.settingsTab === "team"
          width: parent.width
          TextBox {
            id: teamKeyField
            Layout.preferredWidth: Style.space(160)
            text: root.team ? root.team.key : ""
            Keys.onReturnPressed: function(event) { root.changeTeamKey(text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          Button { tooltipText: "Change the issue prefix (Enter in the field)"; text: "Change"; bordered: true; onClicked: root.changeTeamKey(teamKeyField.text) }
          Label {
            Layout.fillWidth: true
            text: root.team ? "Issues are " + root.team.key + "-1, " + root.team.key + "-2… Changing it renumbers them; old links keep working." : ""
            opacity: 0.5
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }
        }

        SectionTitle { visible: root.settingsTab === "team"; text: "Cycles" }
        Label {
          visible: root.settingsTab === "team"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: !lists.cycleSettings ? "Loading…" : (lists.cycleSettings.cyclesEnabled
            ? "Linear makes the team's cycles by itself from these settings and keeps " + lists.cycleSettings.upcomingCycleCount + " ahead. Rename one, change its dates, start it early or archive it in the cycle list (G then V → Edit)."
            : "Cycles are off for this team. Turned on, Linear makes them by itself from these settings.")
        }
        Flow {
          visible: root.settingsTab === "team" && !!lists.cycleSettings
          width: parent.width
          spacing: Style.spacing.sm
          Chip {
            tip: "Turn the team's cycles on or off"
            text: lists.cycleSettings && lists.cycleSettings.cyclesEnabled ? "Cycles on" : "Cycles off"
            glyph: root.icon.cycle
            tint: root.accent
            selected: !!lists.cycleSettings && lists.cycleSettings.cyclesEnabled
            onClicked: {
              var on = !lists.cycleSettings.cyclesEnabled
              if (on) lists.saveCycleSettings({ cyclesEnabled: true })
              else pickers.ask("Turn cycles off for " + root.team.name + "? Linear stops making new ones.", "Turn off", function() { lists.saveCycleSettings({ cyclesEnabled: false }) })
            }
          }
        }
        Repeater {
          model: root.settingsTab === "team" && lists.cycleSettings && lists.cycleSettings.cyclesEnabled ? [
            { key: "cycleDuration", label: "Length", values: [1, 2, 3, 4, 5, 6, 7, 8] },
            { key: "cycleStartDay", label: "Starts on", values: [1, 2, 3, 4, 5, 6, 0] },
            { key: "cycleCooldownTime", label: "Cooldown", values: [0, 1, 2] },
            { key: "upcomingCycleCount", label: "Ahead", values: [1, 2, 3, 4, 6, 8] }
          ] : []
          delegate: RowLayout {
            id: cycleSetRow
            required property var modelData
            width: settingsBody.width
            spacing: Style.spacing.sm
            Label { text: cycleSetRow.modelData.label; font.pixelSize: Style.font.bodySmall; Layout.preferredWidth: Style.space(90) }
            Flow {
              Layout.fillWidth: true
              spacing: Style.spacing.xs
              Repeater {
                model: cycleSetRow.modelData.values
                delegate: Chip {
                  required property var modelData
                  text: {
                    var v = modelData, k = cycleSetRow.modelData.key
                    if (k === "cycleStartDay") return Dates.WEEKDAYS[v].substring(0, 3)
                    if (k === "upcomingCycleCount") return v + (v === 1 ? " cycle" : " cycles")
                    if (k === "cycleCooldownTime" && !v) return "none"
                    return v + (v === 1 ? " week" : " weeks")
                  }
                  tint: root.accent
                  selected: !!lists.cycleSettings && Number(lists.cycleSettings[cycleSetRow.modelData.key]) === modelData
                  onClicked: {
                    var patch = {}
                    patch[cycleSetRow.modelData.key] = modelData
                    lists.saveCycleSettings(patch)
                  }
                }
              }
            }
          }
        }

        SectionTitle { visible: root.settingsTab === "team"; text: "Clean up" }
        RowLayout {
          visible: root.settingsTab === "team" && lists.usageText !== ""
          width: parent.width
          Label {
            Layout.fillWidth: true
            text: lists.usageText
            color: lists.usageCount >= Linear.FREE_PLAN_ISSUES * 0.9 ? root.urgent : root.fg
            font.bold: true
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }
          Button { text: "Archived…"; tooltipText: "Archived and deleted issues: find, restore, delete (G then X)"; onClicked: lists.openArchived() }
        }
        Label {
          visible: root.settingsTab === "team"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Archived issues leave boards and do not count toward the free plan's issue limit; Linear can restore them. " +
            "Linear also archives closed issues by itself after " + (root.team && root.team.autoArchivePeriod ? root.team.autoArchivePeriod : 6) + " months."
        }
        RowLayout {
          visible: root.settingsTab === "team"
          width: parent.width
          Label { text: "Archive done and canceled issues closed more than"; font.pixelSize: Style.font.bodySmall }
          TextBox {
            id: archiveDaysField
            Layout.preferredWidth: Style.space(70)
            verticalPadding: 0
            Layout.preferredHeight: root.inlineHeight
            verticalAlignment: TextEdit.AlignVCenter
            text: "30"
          }
          Label { text: "days ago"; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
          Button { tooltipText: "Archive the done and canceled issues closed before then"; text: "Archive…"; iconText: root.icon.archive; bordered: true; onClicked: bulk.archiveClosedOlderThan(archiveDaysField.text) }
        }
        SectionTitle { visible: root.settingsTab === "team"; text: "Issue templates" }
        Label {
          visible: root.settingsTab === "team" && editorOps.edTemplatesAll.length === 0
          text: "None yet. In the issue editor, “Save as template” makes one."
          opacity: 0.5
          font.pixelSize: Style.font.bodySmall
        }
        Repeater {
          model: root.settingsTab === "team" ? editorOps.edTemplatesAll : []
          delegate: RowLayout {
            required property var modelData
            width: settingsBody.width
            Label { text: modelData.name; Layout.fillWidth: true }
            Label { text: modelData.teamId ? "" : "all teams"; opacity: 0.5; font.pixelSize: Style.font.caption }
            Button { iconText: root.icon.trash; tooltipText: "Delete in Linear"; foreground: root.urgent; onClicked: editorOps.deleteTemplate(modelData) }
          }
        }

        // --- data tab: what is kept outside Linear, the shared folder, export and import ---
        Label {
          visible: root.settingsTab === "data"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: "Linear does not have these, so the board keeps them itself: tracked time (and the running timer), recurring issues, project codes, hidden columns, sort, grouping, layout, and whether time goes to Linear as comments and new notifications to the desktop."
        }
        SectionTitle { visible: root.settingsTab === "data"; text: "Shared folder" }
        RowLayout {
          visible: root.settingsTab === "data"
          width: parent.width
          spacing: Style.spacing.sm
          TextBox {
            id: sharedFolderField
            Layout.fillWidth: true
            placeholderText: "Folder, e.g. ~/Sync/linear (empty: this computer only)"
            text: timeTracker.timeLocation
            Keys.onReturnPressed: function(event) { timeTracker.setTimeLocation(text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          Button { tooltipText: "Use this folder (Enter in the field)"; text: "Apply"; onClicked: { timeTracker.setTimeLocation(sharedFolderField.text); keyScope.forceActiveFocus() } }
        }
        Label {
          visible: root.settingsTab === "data"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.5
          font.pixelSize: Style.font.caption
          text: shared.folder
            ? "Everything above is in " + shared.folder.replace(root.home, "~") + " (" + timeTracker.timePath.replace(/^.*\//, "") + " and linear-board.json). Point another computer at the same synced folder (e.g. Syncthing): what is already there is used, never overwritten. A copy of the settings stays on this computer."
            : "Kept on this computer only: " + timeTracker.timePath.replace(root.home, "~") + " and " + root.configDir.replace(root.home, "~") + "/config.json. Choose a synced folder (e.g. Syncthing) to share it all between computers."
        }
        Label {
          visible: root.settingsTab === "data" && (timeTracker.timeError !== "" || shared.error !== "")
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          color: root.urgent
          font.pixelSize: Style.font.bodySmall
          text: [timeTracker.timeError, shared.error].filter(function(x) { return x }).join("\n")
        }
        Label {
          visible: root.settingsTab === "data"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.5
          font.pixelSize: Style.font.caption
          text: "Not shared, on purpose: the API key, the global keys (Keys tab; another computer may have them taken) and the team, project and filter the board is on."
        }
        SectionTitle { visible: root.settingsTab === "data"; text: "Export and import" }
        Button {
          tooltipText: "Save all of it to Downloads (no API key)"
          visible: root.settingsTab === "data"
          text: "Export everything (JSON)"
          iconText: root.icon.download
          onClicked: shared.exportAll()
        }
        RowLayout {
          visible: root.settingsTab === "data"
          width: parent.width
          spacing: Style.spacing.sm
          TextBox {
            id: importAllField
            Layout.fillWidth: true
            placeholderText: "Path to an export, e.g. ~/Downloads/linear-board-export-2026-10-27.json"
            Keys.onReturnPressed: function(event) { shared.importFrom(text); keyScope.forceActiveFocus(); event.accepted = true }
          }
          Button { tooltipText: "Add what is missing from an export (Enter in the field)"; text: "Import"; iconText: root.icon.upload; onClicked: { shared.importFrom(importAllField.text); keyScope.forceActiveFocus() } }
        }
        Label {
          visible: root.settingsTab === "data"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.5
          font.pixelSize: Style.font.caption
          text: "The export goes to " + timeTracker.downloadsDir().replace(root.home, "~") + " and holds no API key. Import only adds what is missing here (time entries, recurring issues, project codes, hidden columns); nothing here is replaced. Older time-only exports import too."
        }

        // --- account tab ---
        Label {
          visible: root.settingsTab === "account"
          text: root.viewer ? "Connected as " + (root.viewer.displayName || root.viewer.name) : "Connected"
        }
        Label {
          visible: root.settingsTab === "account"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          text: root.envKey ? "The key comes from the LINEAR_API_KEY environment variable." : "The API key is stored in " + root.configDir.replace(root.home, "~") + "/api-key, readable only by you."
        }
        Button {
          tooltipText: "Disconnect from Linear and delete the stored key"
          visible: root.settingsTab === "account" && !root.envKey
          text: "Disconnect and forget the key"
          foreground: root.urgent
          bordered: true
          onClicked: pickers.ask("Disconnect from Linear and delete the stored API key?", "Disconnect", root.disconnect)
        }
      }
    }
  }
}
