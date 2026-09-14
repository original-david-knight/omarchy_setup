import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../david.tasks" as Tasks

Panel {
  id: root
  moduleName: "david.jira-work"
  ipcTarget: "david.jira-work"

  property var jiraData: ({ issues: [] })
  property string assignmentMessage: ""
  property string errorText: ""
  property string fetchStderr: ""
  property string taskError: ""
  property string taskStderr: ""
  property string busyIssueKey: ""
  property bool refreshPending: false
  property bool hasLoaded: false
  property bool loading: false

  readonly property var issues: jiraData && Array.isArray(jiraData.issues) ? jiraData.issues : []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string opener: Quickshell.env("HOME") + "/bin/open-work-url"

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (fetchProcess.running || taskProcess.running || assignment.busy) {
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
      jiraData = JSON.parse(String(raw || ""))
      errorText = String(jiraData.last_error || "")
      hasLoaded = true
    } catch (error) {
      errorText = "Jira tickets could not be read"
    }
    loading = false
  }

  function openUrl(url) {
    if (!url || openProcess.running) return
    openProcess.command = [opener, String(url)]
    openProcess.running = true
  }

  function taskAction(issue) {
    if (!issue.key || taskProcess.running || fetchProcess.running || assignment.active) return
    if (issue.task && !issue.task.id) return
    taskError = ""
    taskStderr = ""
    busyIssueKey = String(issue.key)
    var command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.jira-work/task", busyIssueKey]
    if (issue.task) command.push("delete", String(issue.task.id))
    taskProcess.command = command
    taskProcess.running = true
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { (assignment.active ? assignment : keyCatcher).forceActiveFocus() })
  }

  Process {
    id: fetchProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.jira-work/fetch"]
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
      if (exitCode !== 0) root.errorText = root.fetchStderr || "Jira is unavailable"
      if (root.refreshPending) root.refresh()
    }
  }

  Process { id: openProcess; command: [] }

  Process {
    id: taskProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.taskStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.busyIssueKey = ""
      if (exitCode !== 0)
        root.taskError = root.taskStderr || "Linked task could not be changed"
      root.refresh()
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
    text: "JI"
    fontFamily: "URW Gothic"
    tooltipText: "Jira · " + root.issues.length + " assigned\nLeft: tickets · Right: Jira"
    active: root.errorText !== ""
    fontSize: Style.font.body
    horizontalMargin: 7

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton)
        root.openUrl("jira")
      else if (buttonCode === Qt.MiddleButton)
        root.refresh()
      else
        root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: assignment.active ? assignment : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(assignment.active ? assignment.implicitHeight : contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      blocked: assignment.active
      anchors.fill: parent
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
        else if (text === "o" || text === "O")
          root.openUrl("jira")
      }

      Tasks.AssignAgent {
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
            Text {
              id: title
              text: "Assigned Jira tickets"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width - x
              anchors.baseline: title.baseline
              text: root.jiraData.last_sync ? "Synced " + root.jiraData.last_sync : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
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
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.taskError !== ""
            width: parent.width
            text: root.taskError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.hasLoaded && root.issues.length === 0 && !root.loading
            text: root.jiraData.connected ? "No unresolved tickets are assigned to you." : "Jira is disconnected in Everything App."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.issues
            Item {
              id: issueRow
              required property var modelData
              width: contentColumn.width
              implicitHeight: Math.max(issueCopy.implicitHeight + Style.space(12), issueActions.implicitHeight)
              Rectangle {
                anchors.fill: issueMouse
                radius: Style.cornerRadius
                color: issueMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
              }
              Column {
                id: issueCopy
                anchors.left: parent.left
                anchors.right: issueActions.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: modelData.key + "  ·  " + modelData.title
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  text: modelData.line
                  textFormat: Text.PlainText
                  color: modelData.category === "indeterminate" ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: issueMouse
                anchors.left: parent.left
                anchors.right: issueActions.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(modelData.url)
              }

              Column {
                id: issueActions
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
                  enabled: Boolean(issueRow.modelData.key) && !fetchProcess.running && !taskProcess.running && !(issueRow.modelData.task && issueRow.modelData.task.status === "in_progress") && !assignment.active
                  Accessible.role: Accessible.Button
                  Accessible.name: "Assign " + issueRow.modelData.title + " to an agent"
                  onClicked: assignment.start("jira", issueRow.modelData.key, issueRow.modelData.title)
                }
                PanelActionButton {
                  id: taskButton
                  implicitWidth: Style.space(76)
                  size: Style.space(28)
                  tooltipText: issueRow.modelData.task
                    ? (issueRow.modelData.task.done ? "Completed task exists" : "Task exists") + " · Uncheck to delete task"
                    : "No task · Check to create task"
                  Accessible.role: Accessible.CheckBox
                  Accessible.name: "Linked task for " + issueRow.modelData.key
                  Accessible.checkable: true
                  Accessible.checked: Boolean(issueRow.modelData.task)
                  foreground: issueRow.modelData.task ? Color.accent : root.dim
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  focusable: true
                  enabled: Boolean(issueRow.modelData.key) && !taskProcess.running && !fetchProcess.running && !assignment.active
                  onClicked: root.taskAction(issueRow.modelData)

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(6)
                    opacity: taskButton.enabled ? 1 : 0.5

                    Rectangle {
                      width: Style.space(13)
                      height: width
                      anchors.verticalCenter: parent.verticalCenter
                      radius: Style.space(2)
                      color: "transparent"
                      border.width: 1
                      border.color: taskButton.foreground

                      Text {
                        anchors.centerIn: parent
                        text: root.busyIssueKey === String(issueRow.modelData.key) ? "…" : issueRow.modelData.task ? "✓" : ""
                        color: taskButton.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      text: "Task"
                      color: taskButton.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Checked: task exists  ·  Check to create  ·  Uncheck to delete\nClick a ticket for Jira  ·  R refresh  ·  Esc close"
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
