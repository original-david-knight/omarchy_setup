import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A focused view of Everything App's task board. The desktop bearer remains
// in the agent's mode-0600 config; fetch is the only process that reads it.
Panel {
  id: root
  moduleName: "david.tasks"
  ipcTarget: "david.tasks"

  property var taskData: ({ open: 0, meta: "", tasks: [] })
  property string errorText: ""
  property string fetchStderr: ""
  property bool loading: false
  property bool hasLoaded: false

  readonly property var tasks: taskData && Array.isArray(taskData.tasks) ? taskData.tasks : []
  readonly property int openCount: Number(taskData && taskData.open !== undefined ? taskData.open : 0)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (fetchProcess.running) return
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

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
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
        else if (text === "o" || text === "O") {
          if (root.bar) root.bar.run("~/.local/bin/everything-agent open /")
          root.close()
        }
      }

      Flickable {
        id: scroll
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

          Row {
            width: parent.width

            Text {
              id: title
              text: "Tasks"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width - x
              anchors.baseline: title.baseline
              text: root.taskData.meta || (root.openCount + " open")
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
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            id: taskSection
            width: parent.width
            spacing: Style.space(4)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Text {
              visible: root.hasLoaded && root.tasks.length === 0 && !root.loading
              width: parent.width
              text: "Nothing on your list."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.tasks

              Item {
                required property var modelData
                width: taskSection.width
                implicitHeight: taskCopy.implicitHeight + Style.space(10)

                Row {
                  id: taskCopy
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Text {
                    width: Style.space(18)
                    text: modelData.done ? "✓" : "□"
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
                      color: modelData.done ? root.dim : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.strikeout: Boolean(modelData.done)
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      visible: String(modelData.source || "") !== ""
                      width: parent.width
                      text: modelData.source
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "R refresh  ·  O full dashboard  ·  Esc close"
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
