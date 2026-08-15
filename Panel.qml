import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Strings.js" as Strings

// Todoist popup: overdue/today/upcoming task list, sourced from the
// official `td` CLI (https://github.com/Doist/todoist-cli) rather than
// hitting the REST API directly. `td` owns authentication (OS credential
// store) and returns agent-friendly JSON via --json/--full, so this panel
// never sees or stores an API token itself. Every surface, border, and font
// still comes from the active Omarchy theme; the priority/project colors
// are Todoist's own vocabulary.
Panel {
  id: root
  moduleName: "mateusfl.todoist"
  ipcTarget: "mateusfl.todoist"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- Language. Persisted the same way mateus.clock persists
  //      weekStartDay: written back into this widget's inline shell.json
  //      entry, so it survives restarts without a separate settings store.
  readonly property string language: setting("language", Strings.DEFAULT_LANGUAGE)

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setLanguage(lang) {
    if (lang === root.language) return
    persistSettings({ language: lang })
  }

  property bool settingsOpen: false
  function toggleSettings() { settingsOpen = !settingsOpen }

  // Tab metadata (id/command) comes from Model.js; label/emptyText are
  // resolved here per the active language via the "tab<Id>"/"empty<Id>"
  // Strings.js keys (id capitalized), so Model.js stays language-free.
  readonly property var tabs: Model.tabDefinitions().map(function(tab) {
    var key = tab.id.charAt(0).toUpperCase() + tab.id.slice(1)
    return {
      id: tab.id,
      command: tab.command,
      label: Strings.t(root.language, "tab" + key),
      emptyText: Strings.t(root.language, "empty" + key)
    }
  })

  function tabById(id) {
    for (var i = 0; i < root.tabs.length; i++) if (root.tabs[i].id === id) return root.tabs[i]
    return root.tabs[0]
  }

  readonly property var dueLabels: ({
    overdue: Strings.t(root.language, "dueOverdue"),
    today: Strings.t(root.language, "dueToday"),
    tomorrow: Strings.t(root.language, "dueTomorrow")
  })

  function open() {
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.checkAuth()
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingToken) root.cancelEditingToken()
    root.settingsOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- `td` availability + auth. No token ever touches this file: `td`
  //      resolves its own credential (system keyring by default, or
  //      TODOIST_API_TOKEN) and just tells us yes/no.
  property bool cliMissing: false
  property bool hasToken: false
  property string authEmail: ""
  property bool checkingAuth: false

  function checkAuth() {
    checkingAuth = true
    authProc.command = ["td", "auth", "status", "--json"]
    authProc.running = true
  }

  // `td` writes JSON to stdout on success but to stderr for structured
  // errors (e.g. NO_TOKEN) when there's no TTY attached, so both streams
  // are read here. onExited (not each stream's onStreamFinished) is the
  // sync point: it only fires once both channels are fully drained.
  Process {
    id: authProc
    command: ["td", "auth", "status", "--json"]
    stdout: StdioCollector { id: authOut; waitForEnd: true }
    stderr: StdioCollector { id: authErr; waitForEnd: true }
    onExited: function() {
      root.checkingAuth = false
      var raw = String(authOut.text || "").trim() || String(authErr.text || "").trim()
      if (raw === "") {
        root.cliMissing = true
        root.hasToken = false
        return
      }
      root.cliMissing = false
      var parsed = Model.parseJson(raw)
      root.hasToken = !!parsed && !Model.isAuthErrorResponse(parsed)
      root.authEmail = (parsed && (parsed.email || (parsed.user && parsed.user.email))) || ""
      if (root.hasToken) root.refresh()
    }
  }

  property bool editingToken: false
  property bool savingToken: false
  property bool loggingIn: false

  function startEditingToken() {
    editingToken = true
    Qt.callLater(function() {
      tokenField.text = ""
      tokenField.forceActiveFocus()
    })
  }

  function cancelEditingToken() {
    editingToken = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitToken() {
    var value = tokenField.text.trim()
    if (value === "") { cancelEditingToken(); return }
    savingToken = true
    saveTokenProc.command = ["td", "auth", "token", value]
    saveTokenProc.running = true
  }

  Process {
    id: saveTokenProc
    onExited: function(exitCode) {
      root.savingToken = false
      if (exitCode === 0) {
        root.cancelEditingToken()
        root.checkAuth()
      }
    }
  }

  function loginWithBrowser() {
    loggingIn = true
    loginProc.command = ["td", "auth", "login"]
    loginProc.running = true
  }

  Process {
    id: loginProc
    onExited: function() {
      root.loggingIn = false
      root.checkAuth()
    }
  }

  function logout() {
    logoutProc.command = ["td", "auth", "logout"]
    logoutProc.running = true
  }

  Process {
    id: logoutProc
    onExited: root.checkAuth()
  }

  // ---- Task data. The active tab picks which `td` subcommand fills the
  //      list (see root.tabs); a separate lightweight fetch of "today"
  //      always backs the bar badge so it doesn't change just from
  //      browsing to another tab.
  property string activeTab: "inbox"
  property var rawTasks: []
  property var rawProjects: []
  property bool loading: false

  property var badgeTasks: []
  readonly property var badgeGroups: Model.buildGroups(badgeTasks, [], todayKey, tomorrowKey, dueLabels)
  readonly property int overdueCount: badgeGroups.overdue.length
  readonly property int dueCount: badgeGroups.overdue.length + badgeGroups.today.length

  readonly property date now: clock.date
  readonly property string todayKey: Model.dateKeyFromDate(now)
  readonly property string tomorrowKey: Model.dateKeyFromDate(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1))
  readonly property var groups: Model.buildGroups(rawTasks, rawProjects, todayKey, tomorrowKey, dueLabels)
  readonly property bool hasAnyTask: groups.overdue.length > 0 || groups.today.length > 0 || groups.upcoming.length > 0
  readonly property string emptyText: root.tabById(activeTab).emptyText

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  function setTab(tabId) {
    if (root.activeTab === tabId) return
    root.activeTab = tabId
    root.rawTasks = []
    root.refresh()
  }

  function refresh() {
    if (!root.hasToken) return
    loading = true
    var tabCommand = root.tabById(root.activeTab).command
    fetchTasksProc.command = ["td"].concat(tabCommand, ["--json", "--full", "--show-urls", "--all"])
    fetchTasksProc.running = true

    fetchProjectsProc.command = ["td", "project", "list", "--json", "--full", "--all"]
    fetchProjectsProc.running = true

    fetchBadgeProc.command = ["td", "today", "--json", "--all"]
    fetchBadgeProc.running = true
  }

  Process {
    id: fetchTasksProc
    stdout: StdioCollector { id: tasksOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksErr; waitForEnd: true }
    onExited: function() {
      root.loading = false
      var raw = String(tasksOut.text || "").trim()
      if (raw !== "") { root.rawTasks = Model.parseListResponse(raw); return }
      // Empty stdout with something on stderr means `td` reported an error
      // (e.g. the stored credential was revoked) rather than an empty list.
      var errRaw = String(tasksErr.text || "").trim()
      if (errRaw === "") return
      var parsed = Model.parseJson(errRaw)
      if (Model.isAuthErrorResponse(parsed)) root.hasToken = false
    }
  }

  Process {
    id: fetchProjectsProc
    stdout: StdioCollector { id: projectsOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      var raw = String(projectsOut.text || "").trim()
      if (raw === "") return
      root.rawProjects = Model.parseListResponse(raw)
    }
  }

  Process {
    id: fetchBadgeProc
    stdout: StdioCollector { id: badgeOut; waitForEnd: true }
    onExited: function() {
      var raw = String(badgeOut.text || "").trim()
      if (raw === "") return
      root.badgeTasks = Model.parseListResponse(raw)
    }
  }

  Timer {
    id: refreshTimer
    interval: 5 * 60 * 1000
    running: root.hasToken
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  // ---- Completing a task. Optimistic: the row disappears immediately, the
  //      `td task complete` calls are queued so rapid clicks don't race.
  property var closeQueue: []

  function requestClose(taskId) {
    var next = []
    for (var i = 0; i < rawTasks.length; i++) {
      if (String(rawTasks[i].id) !== String(taskId)) next.push(rawTasks[i])
    }
    rawTasks = next
    closeQueue.push(String(taskId))
    if (!closeProc.running) processNextClose()
  }

  function processNextClose() {
    if (closeQueue.length === 0) return
    var id = closeQueue.shift()
    closeProc.command = ["td", "task", "complete", "id:" + id]
    closeProc.running = true
  }

  Process {
    id: closeProc
    onExited: Qt.callLater(root.processNextClose)
  }

  function openTask(url) {
    if (url) Qt.openUrlExternally(url)
  }

  // ---- Quick add. `td task quickadd` speaks Todoist's own natural-language
  //      syntax (due dates, "p1".."p4", "#project", "@label"), so the input
  //      is a shortcut into the same parser Todoist's own quick-add uses —
  //      no separate due/priority/project fields to build here.
  property bool addingTask: false

  function submitQuickAdd() {
    var text = quickAddField.text.trim()
    if (text === "" || root.addingTask) return
    root.addingTask = true
    quickAddProc.command = ["td", "task", "quickadd", text, "--json"]
    quickAddProc.running = true
  }

  Process {
    id: quickAddProc
    stdout: StdioCollector { id: quickAddOut; waitForEnd: true }
    stderr: StdioCollector { id: quickAddErr; waitForEnd: true }
    onExited: function() {
      root.addingTask = false
      var raw = String(quickAddOut.text || "").trim()
      if (raw === "") {
        var errRaw = String(quickAddErr.text || "").trim()
        var parsed = Model.parseJson(errRaw)
        if (Model.isAuthErrorResponse(parsed)) root.hasToken = false
        return
      }
      quickAddField.text = ""
      root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Without this, PanelKeyCatcher's BeforeItem priority intercepts every
      // keystroke first: space would never reach the field (swallowed by
      // activateRequested) and typing a word starting with "r" would fire
      // a refresh mid-sentence.
      blocked: root.editingToken || quickAddField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(10)

        // ---- Header: title + refresh + auth toggle.
        Item {
          width: parent.width
          height: Math.max(headerRow.height, actionsRow.implicitHeight)

          Item {
            id: headerRow
            anchors.left: parent.left
            anchors.right: actionsRow.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            height: titleIcon.implicitHeight

            Item {
              id: titleIcon
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.heading
              height: Style.font.heading
              implicitHeight: height

              Image {
                id: titleMarkImage
                anchors.fill: parent
                source: Qt.resolvedUrl("assets/todoist-mark.svg")
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                visible: false
              }
              MultiEffect {
                anchors.fill: titleMarkImage
                source: titleMarkImage
                colorization: 1.0
                colorizationColor: root.contentForeground
              }
            }
            Text {
              anchors.left: titleIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.hasToken && root.authEmail ? "Todoist — " + root.authEmail : "Todoist"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
            }
          }

          Row {
            id: actionsRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              id: refreshButton
              visible: root.hasToken
              // Spinning the whole button also spins its hover fill/border,
              // which sweeps the square hover highlight around in a circle.
              // Icons are drawn separately below (loader-circle while
              // loading, refresh-cw otherwise) so only the glyph rotates,
              // leaving the button chrome still.
              iconText: ""
              tooltipText: Strings.t(root.language, "tooltipRefresh")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.refresh()

              Image {
                id: refreshCwSource
                anchors.fill: parent
                anchors.margins: Style.space(4)
                visible: false
                source: Qt.resolvedUrl("assets/refresh-cw.svg")
                sourceSize.width: width * 2
                sourceSize.height: height * 2
              }
              MultiEffect {
                anchors.fill: refreshCwSource
                source: refreshCwSource
                visible: !root.loading
                colorization: 1.0
                colorizationColor: refreshButton.foreground
              }

              Image {
                id: loaderCircleSource
                anchors.fill: parent
                anchors.margins: Style.space(4)
                visible: false
                source: Qt.resolvedUrl("assets/loader-circle.svg")
                sourceSize.width: width * 2
                sourceSize.height: height * 2
              }
              MultiEffect {
                id: loaderCircleEffect
                anchors.fill: loaderCircleSource
                source: loaderCircleSource
                visible: root.loading
                colorization: 1.0
                colorizationColor: refreshButton.foreground

                RotationAnimator on rotation {
                  running: root.loading
                  from: 0; to: 360
                  duration: 800
                  loops: Animation.Infinite
                }
              }
            }
            PanelActionButton {
              id: settingsButton
              tooltipText: Strings.t(root.language, "tooltipSettings")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.toggleSettings()

              Image {
                id: settingsSource
                anchors.fill: parent
                anchors.margins: Style.space(4)
                visible: false
                source: Qt.resolvedUrl("assets/settings.svg")
                sourceSize.width: width * 2
                sourceSize.height: height * 2
              }
              MultiEffect {
                anchors.fill: settingsSource
                source: settingsSource
                colorization: 1.0
                colorizationColor: settingsButton.foreground
              }
            }
            PanelActionButton {
              id: logoutButton
              iconText: root.hasToken ? "" : "󰒓"
              tooltipText: root.hasToken ? Strings.t(root.language, "tooltipLogout") : Strings.t(root.language, "tooltipAuthSetup")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.hasToken ? root.logout() : root.startEditingToken()

              Image {
                id: logOutSource
                anchors.fill: parent
                anchors.margins: Style.space(4)
                visible: false
                source: Qt.resolvedUrl("assets/log-out.svg")
                sourceSize.width: width * 2
                sourceSize.height: height * 2
              }
              MultiEffect {
                anchors.fill: logOutSource
                source: logOutSource
                visible: root.hasToken
                colorization: 1.0
                colorizationColor: logoutButton.foreground
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.contentForeground
          opacity: 0.12
        }

        // ---- Sliding pane: the gear button swaps the task view below the
        //      divider for the settings view by translating both panes
        //      horizontally in lockstep, rather than swapping visibility
        //      outright. Height follows whichever pane is showing so the
        //      panel itself resizes smoothly along with the slide.
        Item {
          id: slidePane
          width: parent.width
          height: root.settingsOpen ? settingsContent.implicitHeight : mainContent.implicitHeight
          clip: true

          Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
          }

        Column {
          id: mainContent
          width: slidePane.width
          x: root.settingsOpen ? -width : 0
          spacing: Style.space(10)

          Behavior on x {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
          }

        // ---- Tabs: which `td` list backs the view below.
        Row {
          visible: root.hasToken && !root.editingToken
          spacing: Style.space(6)

          Repeater {
            model: root.tabs

            Button {
              required property var modelData
              text: modelData.label
              selected: root.activeTab === modelData.id
              bordered: true
              fontSize: Style.font.bodySmall
              foreground: root.contentForeground
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.setTab(modelData.id)
            }
          }
        }

        // ---- Quick add. Same natural-language syntax as Todoist's own
        //      quick-add box: "Reunião amanhã p1 #Trabalho".
        Row {
          visible: root.hasToken && !root.editingToken
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.space(6)

          TextField {
            id: quickAddField
            width: parent.width - addTaskBtn.width - Style.space(6)
            height: parent.height
            enabled: !root.addingTask
            placeholderText: Strings.t(root.language, "quickAddPlaceholder")
            foreground: root.contentForeground

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitQuickAdd()
                event.accepted = true
              }
            }
          }

          Button {
            id: addTaskBtn
            // Square and matched to the field's height rather than the
            // Button's own content-driven implicit size, which came out
            // slightly shorter than the TextField and made the row uneven.
            height: parent.height
            width: height
            text: root.addingTask ? "…" : "+"
            enabled: !root.addingTask && quickAddField.text.trim().length > 0
            foreground: root.contentForeground
            bordered: true
            onClicked: root.submitQuickAdd()
          }
        }

        // ---- `td` missing entirely.
        Column {
          visible: root.cliMissing
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: Strings.t(root.language, "cliMissing")
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- Auth setup: browser login (preferred) or paste a token.
        Column {
          visible: !root.cliMissing && (root.editingToken || !root.hasToken) && !root.checkingAuth
          width: parent.width
          spacing: Style.space(10)

          Button {
            width: parent.width
            text: root.loggingIn ? Strings.t(root.language, "loginButtonBusy") : Strings.t(root.language, "loginButtonIdle")
            enabled: !root.loggingIn
            bordered: true
            foreground: root.contentForeground
            onClicked: root.loginWithBrowser()
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: Strings.t(root.language, "tokenHint")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: tokenField
              width: parent.width - saveTokenBtn.width - Style.space(6)
              enabled: !root.savingToken
              password: true
              placeholderText: Strings.t(root.language, "tokenPlaceholder")
              foreground: root.contentForeground

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelEditingToken(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitToken(); event.accepted = true }
              }
            }

            Button {
              id: saveTokenBtn
              text: root.savingToken ? Strings.t(root.language, "savingEllipsis") : Strings.t(root.language, "saveButtonIdle")
              enabled: !root.savingToken
              foreground: root.contentForeground
              bordered: true
              onClicked: root.commitToken()
            }
          }
        }

        // ---- Task list.
        Flickable {
          id: listScroll
          visible: root.hasToken && !root.editingToken
          width: parent.width
          height: Math.min(listColumn.implicitHeight, Style.space(420))
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: listColumn
            width: listScroll.width
            spacing: Style.space(10)

            Text {
              visible: !root.hasAnyTask && !root.loading
              text: root.emptyText
              wrapMode: Text.WordWrap
              width: parent.width
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }

            Repeater {
              model: [
                { key: "overdue", label: Strings.t(root.language, "sectionOverdue"), items: root.groups.overdue },
                { key: "today", label: Strings.t(root.language, "sectionToday"), items: root.groups.today },
                { key: "upcoming", label: Strings.t(root.language, "sectionUpcoming"), items: root.groups.upcoming }
              ]

              Column {
                required property var modelData
                visible: modelData.items.length > 0
                width: listColumn.width
                spacing: Style.space(4)

                PanelSectionHeader {
                  text: modelData.label + " (" + modelData.items.length + ")"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Repeater {
                  model: modelData.items

                  Item {
                    id: taskRow
                    required property var modelData
                    width: listColumn.width
                    height: taskContent.implicitHeight + Style.space(10)

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: rowMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                    }

                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(26)
                      hoverEnabled: true
                      cursorShape: taskRow.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.openTask(taskRow.modelData.url)
                    }

                    Row {
                      id: taskContent
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(8)

                      // Checkbox — completes the task via `td task complete`.
                      Rectangle {
                        id: checkbox
                        width: Style.space(16)
                        height: Style.space(16)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Math.min(4, Style.cornerRadius + 2)
                        color: "transparent"
                        border.width: Style.spacing.hairline + 1
                        border.color: taskRow.modelData.priorityColor
                          ? taskRow.modelData.priorityColor
                          : Style.normalBorderFor(root.contentForeground, Color.accent)

                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -4
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.requestClose(taskRow.modelData.id)
                        }
                      }

                      Column {
                        width: parent.width - checkbox.width - parent.spacing - dueLabel.width - parent.spacing
                        spacing: Style.space(2)

                        Text {
                          width: parent.width
                          text: taskRow.modelData.content
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                        }

                        Row {
                          visible: taskRow.modelData.projectName !== ""
                          spacing: Style.space(5)

                          Rectangle {
                            width: Style.space(7)
                            height: Style.space(7)
                            radius: Style.space(4)
                            anchors.verticalCenter: parent.verticalCenter
                            color: taskRow.modelData.projectColor || Qt.darker(root.contentForeground, 1.6)
                          }

                          Text {
                            text: taskRow.modelData.projectName
                            color: Qt.darker(root.contentForeground, 1.4)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }
                      }

                      Text {
                        id: dueLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: taskRow.modelData.dueLabel
                        color: taskRow.modelData.bucket === "overdue"
                          ? (root.bar ? root.bar.urgent : Color.urgent)
                          : Qt.darker(root.contentForeground, 1.3)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: taskRow.modelData.bucket === "overdue"
                      }
                    }
                  }
                }
              }
            }
          }
        }
        } // mainContent

        Column {
          id: settingsContent
          width: slidePane.width
          x: root.settingsOpen ? 0 : width
          spacing: Style.space(14)

          Behavior on x {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
          }

          Text {
            text: Strings.t(root.language, "settingsTitle")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Dropdown {
            width: parent.width
            label: Strings.t(root.language, "languageLabel")
            value: root.language
            options: Strings.LANGUAGES
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onChanged: function(value) { root.setLanguage(value) }
          }
        }
        } // slidePane
      }
    }
  }
}
