import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Shared by all three task sources. Opening/cancelling only reads the API.
FocusScope {
  id: root
  property bool active: false
  property bool busy: false
  property bool loading: false
  property string source: ""
  property string taskKey: ""
  property string title: ""
  property var task: null
  property var projects: []
  property var agents: []
  // Dropdown owns its value when the user selects an option. Alias it so
  // later tasks reset both the displayed choice and the submitted value.
  property alias project: projectChoice.value
  property alias agent: agentChoice.value
  property string errorText: ""
  property string output: ""
  property string stderrText: ""
  property bool reloadPending: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property string helper: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.tasks/delegate"
  readonly property bool validProject: projects.some(function(p) { return p.value === root.project })
  readonly property bool validAgent: agents.some(function(a) { return a.value === root.agent })
  signal assigned(string assignee)
  signal cancelled()

  visible: active
  implicitHeight: form.implicitHeight
  Keys.onEscapePressed: function(event) {
    if (!projectChoice.popupOpen && !agentChoice.popupOpen) cancel()
    event.accepted = true
  }

  function start(source, key, title) {
    if (active || busy) return
    root.source = source
    root.taskKey = String(key)
    root.title = String(title)
    active = true
    reload()
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function reload() {
    if (busy) return
    task = null
    projects = []
    agents = []
    project = ""
    agent = ""
    output = ""
    stderrText = ""
    errorText = ""
    if (loading) {
      reloadPending = true
      return
    }
    loading = true
    previewProcess.command = [helper, "preview", source, taskKey]
    previewProcess.running = true
  }

  function cancel() {
    if (busy) return
    // A read may finish after cancel; its output cannot assign anything.
    active = false
    projectChoice.close()
    agentChoice.close()
    cancelled()
  }

  function submit() {
    if (busy || loading || !task || !validProject || !validAgent || errorText !== "") return
    busy = true
    output = ""
    stderrText = ""
    assignmentProcess.command = [helper, "assign", source, taskKey, project, agent, String(task.revision)]
    assignmentProcess.running = true
  }

  Process {
    id: previewProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.output = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.stderrText = String(text || "").trim() }
    onExited: function(code) {
      root.loading = false
      if (root.reloadPending) {
        root.reloadPending = false
        if (root.active) root.reload()
        return
      }
      if (!root.active) return
      if (code !== 0) {
        root.errorText = root.stderrText || "Assignment options could not be loaded"
        return
      }
      try {
        var data = JSON.parse(root.output)
        root.task = data.task
        root.projects = data.projects
        root.agents = data.agents
        root.project = data.task.project_id
        root.agent = data.agents.some(function(a) { return a.value === data.task.assignee }) ? data.task.assignee : ""
      } catch (error) { root.errorText = "Assignment options could not be read" }
    }
  }

  Process {
    id: assignmentProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.output = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.stderrText = String(text || "").trim() }
    onExited: function(code) {
      root.busy = false
      if (code !== 0) {
        root.errorText = root.stderrText || "Assignment could not be confirmed. Reload options before trying again."
        return
      }
      root.active = false
      root.assigned(root.agent)
    }
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: form
      width: parent.width
      spacing: Style.space(12)
      Text {
        text: "Assign to agent"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        text: root.task ? root.task.title : root.title
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
      Text {
        visible: root.loading
        text: "Loading assignment options…"
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Dropdown {
        id: projectChoice
        width: parent.width
        visible: root.task !== null
        enabled: !root.busy
        label: "Project"
        options: [{value: "", label: "Choose a project"}].concat(
          root.project && !root.validProject ? [{value: root.project, label: "Current project unavailable · choose another"}] : [], root.projects)
      }
      Dropdown {
        id: agentChoice
        width: parent.width
        visible: root.task !== null
        enabled: !root.busy
        label: "Agent"
        options: [{value: "", label: "Choose an agent"}].concat(root.agents)
      }
      Text {
        visible: root.task !== null
        width: parent.width
        text: !root.projects.length ? "Add a repository to an active project to assign work."
          : !root.agents.length ? "No agents are available for assignment."
          : root.source === "github" ? "The agent will review the PR and return the review to you."
          : root.source === "jira" ? "The agent will implement this task in the selected project."
          : "The agent will work on this task in the selected project."
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
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
      Row {
        width: parent.width
        spacing: Style.space(8)
        PanelActionButton {
          implicitWidth: Style.space(90)
          size: Style.space(32)
          iconText: root.busy ? "Assigning…" : "Assign"
          foreground: Color.accent
          fontSize: Style.font.bodySmall
          focusable: true
          enabled: root.task !== null && root.validProject && root.validAgent && !root.busy && root.errorText === ""
          onClicked: root.submit()
        }
        PanelActionButton {
          implicitWidth: Style.space(80)
          size: Style.space(32)
          iconText: "Cancel"
          foreground: root.foreground
          fontSize: Style.font.bodySmall
          focusable: true
          enabled: !root.busy
          onClicked: root.cancel()
        }
        PanelActionButton {
          visible: root.errorText !== ""
          implicitWidth: Style.space(120)
          size: Style.space(32)
          iconText: "Reload options"
          foreground: root.foreground
          fontSize: Style.font.caption
          focusable: true
          enabled: !root.busy && !root.loading
          onClicked: root.reload()
        }
      }
    }
  }
}
