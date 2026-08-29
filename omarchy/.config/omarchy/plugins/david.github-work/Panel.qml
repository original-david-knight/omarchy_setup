import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "david.github-work"
  ipcTarget: "david.github-work"

  property var githubData: ({ mine: [], review: [] })
  property string errorText: ""
  property string fetchStderr: ""
  property bool loading: false

  readonly property var mine: githubData && Array.isArray(githubData.mine) ? githubData.mine : []
  readonly property var review: githubData && Array.isArray(githubData.review) ? githubData.review : []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string opener: Quickshell.env("HOME") + "/bin/open-work-url"

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
      githubData = JSON.parse(String(raw || ""))
      errorText = String(githubData.last_error || "")
    } catch (error) {
      errorText = "Pull requests could not be read"
    }
    loading = false
  }

  function openUrl(url) {
    if (!url || openProcess.running) return
    openProcess.command = [opener, String(url)]
    openProcess.running = true
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: fetchProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.github-work/fetch"]
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
      if (exitCode !== 0) root.errorText = root.fetchStderr || "GitHub is unavailable"
    }
  }

  Process { id: openProcess; command: [] }

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
    text: "PR"
    fontFamily: "Z003"
    tooltipText: "GitHub · " + root.mine.length + " open · " + root.review.length + " to review\nLeft: queues · Right: GitHub"
    active: root.errorText !== ""
    // Pull requests waiting on the owner turn the label gold; an error still wins.
    foreground: root.review.length > 0 ? "#e3c46a" : root.foreground
    fontSize: Style.font.body
    horizontalMargin: 7

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton)
        root.openUrl("github")
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
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
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
        else if (text === "o" || text === "O") root.openUrl("github")
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
              text: "Work pull requests"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width - x
              anchors.baseline: title.baseline
              text: root.githubData.last_sync ? "Synced " + root.githubData.last_sync : ""
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
            id: mineSection
            width: parent.width
            spacing: Style.space(5)
            PanelSeparator { width: parent.width; foreground: root.foreground }
            PanelSectionHeader {
              text: "MY OPEN PRS  ·  " + root.mine.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Text {
              visible: root.mine.length === 0 && !root.loading
              text: "No open pull requests."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.mine
              Item {
                required property var modelData
                width: mineSection.width
                implicitHeight: rowCopy.implicitHeight + Style.space(10)
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                }
                Column {
                  id: rowCopy
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: (modelData.draft ? "DRAFT  ·  " : "") + modelData.key + "  ·  " + modelData.title
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    text: modelData.line
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(modelData.url)
                }
              }
            }
          }

          Column {
            id: reviewSection
            width: parent.width
            spacing: Style.space(5)
            PanelSeparator { width: parent.width; foreground: root.foreground }
            PanelSectionHeader {
              text: "AWAITING MY REVIEW  ·  " + root.review.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Text {
              visible: root.review.length === 0 && !root.loading
              text: "No pull requests awaiting review."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.review
              Item {
                required property var modelData
                width: reviewSection.width
                implicitHeight: reviewCopy.implicitHeight + Style.space(10)
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: reviewMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                }
                Column {
                  id: reviewCopy
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: modelData.key + "  ·  " + modelData.title
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    text: modelData.line
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
                MouseArea {
                  id: reviewMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(modelData.url)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Click a PR to open it in work Chrome  ·  R refresh  ·  Esc close"
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
