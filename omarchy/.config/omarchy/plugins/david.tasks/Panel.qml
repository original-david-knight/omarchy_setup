import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A focused view of Everything App's task board. The desktop bearer remains
// in the agent's mode-0600 config; helper processes handle authenticated calls.
Panel {
  id: root
  moduleName: "david.tasks"
  ipcTarget: "david.tasks"

  property var taskData: ({ open: 0, meta: "", tasks: [] })
  property string assignmentMessage: ""
  property string errorText: ""
  property string fetchStderr: ""
  property string createError: ""
  property string createStderr: ""
  property string completeError: ""
  property string completeStderr: ""
  property string completingTaskId: ""
  property bool refreshPending: false
  property bool loading: false
  property bool hasLoaded: false
  property bool addingTask: false
  property string selectedView: "action"

  readonly property var allTasks: taskData && Array.isArray(taskData.tasks) ? taskData.tasks : []
  readonly property var tasks: allTasks.filter(function(task) { return task.view === root.selectedView })
  readonly property int openCount: Number(taskData && taskData.open !== undefined ? taskData.open : 0)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (fetchProcess.running || completeProcess.running || assignment.busy) {
      refreshPending = true
      return
    }
    refreshPending = false
    loading = true
    errorText = ""
    fetchStderr = ""
    fetchProcess.running = true
  }

  function consume(raw) {
    try {
      taskData = JSON.parse(String(raw || ""))
      errorText = ""
      hasLoaded = true
    } catch (error) {
      errorText = "Everything tasks could not be read"
    }
    loading = false
  }

  function startAddingTask() {
    addingTask = true
    createError = ""
    Qt.callLater(function() {
      taskInput.text = ""
      taskInput.forceActiveFocus()
    })
  }

  function stopAddingTask() {
    if (createProcess.running) return
    addingTask = false
    createError = ""
    Qt.callLater(function() { (assignment.active ? assignment : keyCatcher).forceActiveFocus() })
  }

  function submitTask() {
    var title = taskInput.text.trim()
    if (title === "" || createProcess.running) return
    createError = ""
    createStderr = ""
    createProcess.command = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/david.tasks/create",
      title
    ]
    createProcess.running = true
  }

  function openTask(task) {
    if (!task.id || openProcess.running) return
    var path = task.can_complete
      ? "/tasks?task=" + encodeURIComponent(String(task.id))
      : "/projects/items/" + encodeURIComponent(String(task.item_key || task.id))
    openProcess.command = [
      Quickshell.env("HOME") + "/.local/bin/everything-agent",
      "open", path
    ]
    openProcess.running = true
    root.close()
  }

  function completeTask(task) {
    if (!task.id || task.can_complete !== true || Number(task.revision) < 1
        || completeProcess.running || fetchProcess.running || assignment.active) return
    completeError = ""
    completeStderr = ""
    completingTaskId = String(task.id)
    completeProcess.command = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/david.tasks/complete",
      completingTaskId, task.done ? "false" : "true", String(task.revision)
    ]
    completeProcess.running = true
  }

  function taskDetails(task) {
    var parts = []
    if (task.project_name) parts.push(task.project_name)
    if (task.can_complete !== true && task.next_action) parts.push(task.next_action)
    if (task.can_complete !== true && task.assignee) parts.push(task.assignee)
    if (task.source) parts.push(task.source)
    return parts.join(" · ")
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { (assignment.active ? assignment : keyCatcher).forceActiveFocus() })
  }

  Process {
    id: fetchProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.tasks/fetch"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.consume(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fetchStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0)
        root.errorText = root.fetchStderr || "Everything App is unavailable"
      if (root.refreshPending) root.refresh()
    }
  }

  Process { id: openProcess; command: [] }

  Process {
    id: completeProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.completeStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.completingTaskId = ""
      if (exitCode !== 0)
        root.completeError = root.completeStderr || "Task could not be updated"
      root.refresh()
    }
  }

  Process {
    id: createProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.createStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        taskInput.text = ""
        root.addingTask = false
        root.selectedView = "action"
        root.refresh()
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      } else {
        root.createError = root.createStderr || "Task could not be added"
        Qt.callLater(function() { taskInput.forceActiveFocus() })
      }
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "T"
    tooltipText: "Tasks · " + root.openCount + " open\nLeft: task list · Right: Everything"
    active: root.errorText !== ""
    fontSize: Style.font.body
    horizontalMargin: 7

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.bar) root.bar.run("~/.local/bin/everything-agent open /")
      } else if (buttonCode === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: assignment.active ? assignment : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(assignment.active ? assignment.implicitHeight : contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: taskInput.activeFocus || assignment.active
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.refresh()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          scroll.contentY = Math.max(0, Math.min(scroll.contentY + dy * Style.space(56),
                                                Math.max(0, scroll.contentHeight - scroll.height)))
      }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "+" || text === "a" || text === "A") root.startAddingTask()
        else if (text === "o" || text === "O") {
          if (root.bar) root.bar.run("~/.local/bin/everything-agent open /")
          root.close()
        }
      }

      AssignAgent {
        id: assignment
        width: parent.width
        height: parent.height
        foreground: root.foreground
        fontFamily: root.fontFamily
        onActiveChanged: if (active) {
          root.assignmentMessage = ""
          scroll.contentY = 0
        }
        onAssigned: function(assignee) {
          root.assignmentMessage = "Assigned to " + assignee + "."
          root.refresh()
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
        onCancelled: Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }

      Flickable {
        id: scroll
        visible: !assignment.active
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(12)

          Text {
            visible: root.assignmentMessage !== ""
            width: parent.width
            text: root.assignmentMessage
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: title
              text: "Tasks"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width - title.width - addTaskButton.width - parent.spacing * 2
              anchors.baseline: title.baseline
              text: root.taskData.meta || (root.openCount + " open")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }

            PanelActionButton {
              id: addTaskButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "+"
              tooltipText: root.addingTask ? "Cancel adding a task" : "Add a task"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.title
              size: Style.space(24)
              focusable: true
              onClicked: {
                if (root.addingTask) root.stopAddingTask()
                else root.startAddingTask()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: [
                { key: "action", label: "Needs you" },
                { key: "waiting", label: "Waiting" },
                { key: "completed", label: "Completed" }
              ]
              PanelActionButton {
                required property var modelData
                implicitWidth: (contentColumn.width - Style.space(8)) / 3
                size: Style.space(28)
                iconText: modelData.label + " · " + root.allTasks.filter(function(task) { return task.view === modelData.key }).length
                tooltipText: modelData.label
                foreground: root.selectedView === modelData.key ? Color.accent : root.dim
                hasCursor: root.selectedView === modelData.key
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                focusable: true
                onClicked: {
                  root.selectedView = modelData.key
                  scroll.contentY = 0
                }
              }
            }
          }

          Text {
            visible: root.loading
            width: parent.width
            text: "Refreshing…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.completeError !== ""
            width: parent.width
            text: root.completeError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.addingTask
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: taskInput
                width: parent.width - submitTaskButton.width - parent.spacing
                enabled: !createProcess.running
                placeholderText: "Add a task"
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall

                onAccepted: root.submitTask()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.stopAddingTask()
                    event.accepted = true
                  }
                }
              }

              PanelActionButton {
                id: submitTaskButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: createProcess.running ? "…" : "✓"
                tooltipText: "Add task"
                foreground: root.foreground
                fontFamily: root.fontFamily
                size: taskInput.implicitHeight
                enabled: !createProcess.running && taskInput.text.trim() !== ""
                onClicked: root.submitTask()
              }
            }

            Text {
              visible: root.createError !== ""
              width: parent.width
              text: root.createError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            id: taskSection
            width: parent.width
            spacing: Style.space(4)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Text {
              visible: root.hasLoaded && root.tasks.length === 0 && !root.loading
              width: parent.width
              text: root.selectedView === "action" ? "Nothing needs your action."
                : root.selectedView === "waiting" ? "No work is waiting on an agent." : "No completed tasks."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.tasks

              Item {
                id: taskRow
                required property var modelData
                width: taskSection.width
                implicitHeight: Math.max(taskCopy.implicitHeight + Style.space(10), taskActions.implicitHeight)

                Rectangle {
                  anchors.fill: taskMouse
                  radius: Style.cornerRadius
                  color: taskMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                }

                Row {
                  id: taskCopy
                  anchors.left: parent.left
                  anchors.right: taskActions.left
                  anchors.rightMargin: Style.space(7)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Text {
                    width: Style.space(18)
                    text: modelData.can_complete ? (modelData.done ? "✓" : "□") : "→"
                    color: modelData.done ? root.dim : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    width: taskCopy.width - x
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: modelData.title
                      textFormat: Text.PlainText
                      color: modelData.done ? root.dim : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.strikeout: Boolean(modelData.done)
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      visible: root.taskDetails(modelData) !== ""
                      width: parent.width
                      text: root.taskDetails(modelData)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                MouseArea {
                  id: taskMouse
                  anchors.left: parent.left
                  anchors.right: taskActions.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  enabled: Boolean(taskRow.modelData.id)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openTask(taskRow.modelData)
                }

                Column {
                  id: taskActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(76)
                  spacing: Style.space(2)
                  PanelActionButton {
                    width: Style.space(76)
                    size: Style.space(28)
                    iconText: "Assign"
                    tooltipText: "Assign to agent"
                    foreground: Color.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    focusable: true
                    enabled: Boolean(taskRow.modelData.id) && !fetchProcess.running && !completeProcess.running && !createProcess.running && taskRow.modelData.status !== "in_progress" && !assignment.active
                    Accessible.role: Accessible.Button
                    Accessible.name: "Assign " + taskRow.modelData.title + " to an agent"
                    onClicked: assignment.start("task", taskRow.modelData.id, taskRow.modelData.title)
                  }
                  PanelActionButton {
                    id: finishTaskButton
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconText: root.completingTaskId === String(taskRow.modelData.id) ? "…"
                      : !taskRow.modelData.can_complete ? "→" : taskRow.modelData.done ? "↶" : "×"
                    tooltipText: !taskRow.modelData.can_complete ? (taskRow.modelData.next_action || "Open ticket")
                      : taskRow.modelData.done ? "Reopen task" : "Mark finished"
                    foreground: root.foreground
                    hoverColor: Color.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    size: Style.space(26)
                    enabled: Boolean(taskRow.modelData.id) && (!taskRow.modelData.can_complete
                      || (Number(taskRow.modelData.revision) > 0 && !completeProcess.running && !fetchProcess.running && !assignment.active))
                    onClicked: {
                      if (taskRow.modelData.can_complete) root.completeTask(taskRow.modelData)
                      else root.openTask(taskRow.modelData)
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Click to open  ·  × finish  ·  ↶ reopen  ·  → ticket details\n+ / A add  ·  R refresh  ·  O full dashboard  ·  Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
