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
  property bool refreshPending: false
  property string busyKey: ""
  property string reviewError: ""
  property string reviewStderr: ""

  readonly property var mine: githubData && Array.isArray(githubData.mine) ? githubData.mine : []
  readonly property var review: githubData && Array.isArray(githubData.review) ? githubData.review : []
  readonly property bool reviewing: review.some(function(pr) { return pr.review && pr.review.reviewing })
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // Everything about pull requests waiting on the owner is gold.
  readonly property color gold: "#e3c46a"
  readonly property color goldDim: Qt.darker(gold, 1.35)
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string opener: Quickshell.env("HOME") + "/bin/open-work-url"

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (fetchProcess.running || reviewProcess.running) {
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

  function requestReview(pr) {
    if (!pr.key || fetchProcess.running || reviewProcess.running || (pr.review && pr.review.reviewing)) return
    busyKey = String(pr.key)
    reviewError = ""
    reviewStderr = ""
    reviewProcess.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.github-work/review", busyKey]
    reviewProcess.running = true
  }

  function openTicket(id) {
    if (!id || openProcess.running) return
    openProcess.command = [Quickshell.env("HOME") + "/.local/bin/everything-agent", "open", "/projects/items/" + encodeURIComponent(id)]
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
      if (root.refreshPending) root.refresh()
    }
  }

  Process { id: openProcess; command: [] }

  Process {
    id: reviewProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reviewStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.busyKey = ""
      if (exitCode !== 0) root.reviewError = root.reviewStderr || "Review could not be requested"
      root.refresh()
    }
  }

  Timer {
    interval: root.reviewing ? 5000 : root.opened ? 15000 : 300000
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
    foreground: root.review.length > 0 ? root.gold : root.foreground
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

          Text {
            visible: root.reviewError !== ""
            width: parent.width
            text: root.reviewError
            textFormat: Text.PlainText
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
            PanelSeparator { width: parent.width; foreground: root.gold }
            PanelSectionHeader {
              text: "AWAITING MY REVIEW  ·  " + root.review.length
              foreground: root.gold
              fontFamily: root.fontFamily
            }
            Text {
              visible: root.review.length === 0 && !root.loading
              text: "No pull requests awaiting review."
              color: root.goldDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.review
              Item {
                id: reviewRow
                required property var modelData
                readonly property bool busy: root.busyKey === modelData.key || Boolean(modelData.review && modelData.review.reviewing)
                width: reviewSection.width
                implicitHeight: Math.max(reviewCopy.implicitHeight, reviewActions.implicitHeight) + Style.space(10)
                Rectangle {
                  anchors.fill: reviewMouse
                  radius: Style.cornerRadius
                  color: reviewMouse.containsMouse ? Style.hoverFillFor(root.gold, Color.accent) : "transparent"
                }
                Column {
                  id: reviewCopy
                  anchors.left: parent.left
                  anchors.right: reviewActions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: modelData.key + "  ·  " + modelData.title
                    textFormat: Text.PlainText
                    color: root.gold
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    text: (modelData.review && modelData.review.status === "pending_approval" ? "Review ready  ·  " : "") + modelData.line
                    textFormat: Text.PlainText
                    color: root.goldDim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
                MouseArea {
                  id: reviewMouse
                  anchors.left: parent.left
                  anchors.right: reviewActions.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(modelData.url)
                }
                Column {
                  id: reviewActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(90)
                  spacing: Style.space(2)
                  Text {
                    visible: reviewRow.busy
                    width: parent.width
                    height: Style.space(28)
                    text: "Reviewing"
                    color: root.goldDim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "Reviewing " + reviewRow.modelData.key
                  }
                  PanelActionButton {
                    visible: !reviewRow.busy
                    width: parent.width
                    size: Style.space(28)
                    iconText: reviewRow.modelData.review ? "Re-review" : "Review"
                    tooltipText: "Ask the agent to review this PR and prepare private draft comments"
                    foreground: root.gold
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    focusable: true
                    enabled: Boolean(reviewRow.modelData.key) && !fetchProcess.running && !reviewProcess.running
                    Accessible.role: Accessible.Button
                    Accessible.name: iconText + " " + reviewRow.modelData.key
                    onClicked: root.requestReview(reviewRow.modelData)
                  }
                  PanelActionButton {
                    visible: Boolean(reviewRow.modelData.review && reviewRow.modelData.review.id)
                    width: parent.width
                    size: Style.space(26)
                    iconText: "Ticket"
                    tooltipText: "Open the linked review ticket in Everything App"
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    focusable: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Review ticket for " + reviewRow.modelData.key
                    onClicked: root.openTicket(reviewRow.modelData.review.id)
                  }
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
