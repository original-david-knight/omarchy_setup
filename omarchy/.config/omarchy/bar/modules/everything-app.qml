import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

WidgetButton {
  id: root

  property string agentPath: Quickshell.env("HOME") + "/.local/bin/everything-agent"
  property string summaryPath: Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/everything-summary"
  property string workBrowserPath: Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/everything-open-work"
  property bool popupOpen: false
  property string dataError: ""
  property var summary: ({
    error: "",
    generated_at: "",
    calendar: { connected: false, date: "", events: [] },
    steps: { connected: false, value: null, goal: null },
    jira: [],
    mine: [],
    review: [],
    jira_connected: false,
    github_connected: false
  })

  readonly property color panelForeground: bar ? bar.foreground : Color.foreground
  readonly property color panelDim: Qt.darker(panelForeground, 1.45)
  readonly property var nextEvent: {
    var events = summary.calendar && Array.isArray(summary.calendar.events)
      ? summary.calendar.events
      : []
    var at = Date.now()
    for (var i = 0; i < events.length; i++) {
      if (Date.parse(events[i].starts_at) > at) return events[i]
    }
    return null
  }
  readonly property string eventTime: {
    if (!nextEvent) return summary.calendar.connected ? "Calendar clear" : "Calendar unavailable"
    return nextEvent.time || Qt.formatTime(new Date(nextEvent.starts_at), "HH:mm")
  }
  readonly property string eventTitle: nextEvent
    ? nextEvent.title
    : (summary.calendar.connected ? "Nothing else today" : "Connect a calendar")
  readonly property string stepsValue: summary.steps && summary.steps.value !== null
    ? formatNumber(summary.steps.value)
    : "—"
  readonly property string stepsDetail: {
    if (!summary.steps || !summary.steps.connected) return "Health is not connected"
    if (summary.steps.value === null) return "Waiting for today's sync"
    if (!summary.steps.goal) return "steps so far"
    return Math.round(100 * Number(summary.steps.value) / Number(summary.steps.goal))
      + "% of " + formatNumber(summary.steps.goal)
  }
  readonly property string updatedLabel: summary.generated_at
    ? "Updated " + Qt.formatTime(new Date(summary.generated_at), "HH:mm")
    : "Loading"
  readonly property bool refreshing: refreshProcess.running

  text: "e"
  tooltipText: "Everything · click for your dashboard"
  fontFamily: "C059"
  fontSize: 21
  horizontalMargin: 9
  dimmed: dataError !== ""
  active: popupOpen
  useActiveColor: false

  function close() {
    popupOpen = false
  }

  function formatNumber(value) {
    return Number(value).toLocaleString(Qt.locale(), "f", 0)
  }

  function refresh() {
    if (!summaryProcess.running) summaryProcess.running = true
  }

  function refreshFromSource() {
    if (!refreshProcess.running) refreshProcess.running = true
  }

  function updateSummary(raw) {
    try {
      var next = JSON.parse(String(raw || "{}"))
      summary = next
      dataError = next.error || ""
    } catch (error) {
      dataError = "Could not read Everything data"
    }
  }

  function openEverything() {
    close()
    if (!launcher.running) {
      launcher.command = [agentPath, "open", "/"]
      launcher.running = true
    }
  }

  function openWorkUrl(url) {
    if (!url) return
    close()
    if (!launcher.running) {
      launcher.command = [workBrowserPath, url]
      launcher.running = true
    }
  }

  onPressed: function(button) {
    if (button === Qt.LeftButton) popupOpen = !popupOpen
    else if (button === Qt.RightButton) openEverything()
  }

  onPopupOpenChanged: if (popupOpen) refresh()

  Process {
    id: summaryProcess
    command: [root.summaryPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSummary(text)
    }
  }

  Process {
    id: refreshProcess
    command: [root.summaryPath, "--refresh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSummary(text)
    }
  }

  Process {
    id: launcher
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  component MetricCard: BorderSurface {
    id: metric

    property string kicker: ""
    property string value: ""
    property string detail: ""
    property string icon: ""
    property color foreground: Color.foreground
    property color dim: Qt.darker(foreground, 1.45)

    implicitHeight: Style.space(86)
    color: Style.normalFillFor(foreground, Color.accent)
    borderSpec: Border.controlSpec("normal", foreground, Color.accent)
    radius: Style.cornerRadius

    Column {
      id: metricContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(10)
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: Math.max(metricKicker.implicitHeight, metricIcon.implicitHeight)

        Text {
          id: metricKicker
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: metric.kicker
          color: metric.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
        }

        Text {
          id: metricIcon
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: metric.icon
          color: metric.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.iconLarge
        }
      }

      Text {
        width: parent.width
        text: metric.value
        color: metric.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        maximumLineCount: 2
        elide: Text.ElideRight
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        text: metric.detail
        color: metric.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  component SectionHeader: Item {
    id: section

    property string label: ""
    property int count: -1
    property color foreground: Color.foreground

    implicitHeight: headerLabel.implicitHeight

    Text {
      id: headerLabel
      anchors.left: parent.left
      text: section.label
      color: Qt.darker(section.foreground, 1.45)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.1
    }

    Text {
      anchors.right: parent.right
      text: section.count >= 0 ? String(section.count) : ""
      color: Qt.darker(section.foreground, 1.45)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component SummaryRow: BorderSurface {
    id: summaryRow

    property string primary: ""
    property string secondary: ""
    property color foreground: Color.foreground
    signal activated()

    implicitHeight: Style.space(48)
    color: rowMouse.containsMouse
      ? Style.hoverFillFor(foreground, Color.accent)
      : "transparent"
    borderSpec: rowMouse.containsMouse
      ? Border.controlSpec("hover-cursor", foreground, Color.accent)
      : Border.none()
    radius: Style.cornerRadius

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: Style.space(9)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: summaryRow.primary
        color: summaryRow.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: summaryRow.secondary
        color: Qt.darker(summaryRow.foreground, 1.45)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: summaryRow.activated()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(dashboardColumn.implicitHeight, Style.space(740))

    Flickable {
      id: dashboardFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: dashboardColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      QQC.ScrollBar.vertical: QQC.ScrollBar {
        policy: dashboardFlick.contentHeight > dashboardFlick.height
          ? QQC.ScrollBar.AsNeeded
          : QQC.ScrollBar.AlwaysOff
      }

      Column {
        id: dashboardColumn
        width: dashboardFlick.width
        spacing: Style.space(11)

        PanelHero {
          width: parent.width
          title: "Everything"
          meta: root.dataError ? "Some data unavailable" : "Your work at a glance"
          detail: root.updatedLabel
          foreground: root.panelForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          iconOpacity: root.dataError ? 0.45 : 1.0
          iconComponent: Component {
            Item {
              implicitWidth: Style.space(40)
              implicitHeight: Style.space(40)

              BorderSurface {
                anchors.fill: parent
                color: Style.normalFillFor(root.panelForeground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.panelForeground, Color.accent)
                radius: Style.cornerRadius

                Text {
                  anchors.centerIn: parent
                  text: "e"
                  color: root.panelForeground
                  font.family: "C059"
                  font.pixelSize: Style.font.display
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.dataError !== ""
          text: root.dataError
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          MetricCard {
            width: (parent.width - parent.spacing) / 2
            kicker: "NEXT EVENT"
            value: root.eventTitle
            detail: root.eventTime
            icon: "󰃭"
            foreground: root.panelForeground
          }

          MetricCard {
            width: (parent.width - parent.spacing) / 2
            kicker: "STEPS TODAY"
            value: root.stepsValue
            detail: root.stepsDetail
            icon: "󰤃"
            foreground: root.panelForeground
          }
        }

        PanelSeparator {
          foreground: root.panelForeground
        }

        SectionHeader {
          width: parent.width
          label: "RECENT JIRA"
          count: root.summary.jira ? root.summary.jira.length : 0
          foreground: root.panelForeground
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.summary.jira || []

            SummaryRow {
              required property var modelData
              width: parent.width
              primary: modelData.key + " · " + modelData.summary
              secondary: modelData.line
              foreground: root.panelForeground
              onActivated: root.openWorkUrl(modelData.url)
            }
          }

          Text {
            visible: !root.summary.jira || root.summary.jira.length === 0
            text: root.summary.jira_connected ? "Nothing assigned." : "Jira is not connected."
            color: root.panelDim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        PanelSeparator {
          foreground: root.panelForeground
        }

        SectionHeader {
          width: parent.width
          label: "YOUR LATEST WORK PRS"
          count: root.summary.mine ? root.summary.mine.length : 0
          foreground: root.panelForeground
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.summary.mine || []

            SummaryRow {
              required property var modelData
              width: parent.width
              primary: modelData.key + " · " + modelData.title
              secondary: modelData.line
              foreground: root.panelForeground
              onActivated: root.openWorkUrl(modelData.url)
            }
          }

          Text {
            visible: !root.summary.mine || root.summary.mine.length === 0
            text: root.summary.github_connected ? "No open pull requests." : "GitHub is not connected."
            color: root.panelDim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        PanelSeparator {
          foreground: root.panelForeground
        }

        SectionHeader {
          width: parent.width
          label: "WAITING FOR YOUR REVIEW"
          count: root.summary.review ? root.summary.review.length : 0
          foreground: root.panelForeground
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.summary.review || []

            SummaryRow {
              required property var modelData
              width: parent.width
              primary: modelData.key + " · " + modelData.title
              secondary: modelData.line
              foreground: root.panelForeground
              onActivated: root.openWorkUrl(modelData.url)
            }
          }

          Text {
            visible: !root.summary.review || root.summary.review.length === 0
            text: root.summary.github_connected ? "You're all caught up." : "GitHub is not connected."
            color: root.panelDim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        PanelSeparator {
          foreground: root.panelForeground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: Style.space(145)
            text: root.refreshing ? "Refreshing…" : "Refresh"
            iconText: "󰑐"
            leftAlign: true
            enabled: !root.refreshing
            foreground: root.panelForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.refreshFromSource()
          }

          Button {
            width: parent.width - Style.space(145) - parent.spacing
            text: "Open full Everything site"
            iconText: "󰖟"
            leftAlign: true
            foreground: root.panelForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.openEverything()
          }
        }
      }
    }
  }
}
