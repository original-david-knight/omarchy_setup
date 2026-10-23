import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "david.security"
  ipcTarget: "david.security"

  property var status: null
  property real now: Date.now()
  property color warning: "#e0af68"

  readonly property string statusPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/security-watch/status.json"
  readonly property real staleAfter: 36 * 3600 * 1000
  readonly property var result: status ? status.result : null
  readonly property var run: status ? status.run : null
  readonly property string watchState: stateOf(status, now)
  readonly property var look: looks[watchState]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var findings: result ? sortedFindings(result.findings) : []
  readonly property var todo: findings.filter(function(finding) { return Boolean(finding.youShould) })
  readonly property var actions: result ? result.actions : []

  // tone picks the bar treatment: alert is a solid red badge, warn is amber
  // text, dim is the faded glyph, normal is the plain bar foreground.
  readonly property var looks: ({
    never:   { glyph: "\u{f0499}", tone: "dim",    label: "No security review has run yet" },
    running: { glyph: "\u{f11a2}", tone: "normal", label: "Security review in progress" },
    clear:   { glyph: "\u{f0565}", tone: "normal", label: "Nothing affects this machine" },
    notice:  { glyph: "\u{f0780}", tone: "normal", label: "Known issues, nothing needed from you" },
    alert:   { glyph: "\u{f0ecc}", tone: "alert",  label: "Needs your attention" },
    failed:  { glyph: "\u{f099e}", tone: "warn",   label: "The last security review failed" },
    stale:   { glyph: "\u{f0499}", tone: "warn",   label: "The last successful review is over 36 hours old" }
  })
  readonly property var severityOrder: ["critical", "high", "medium", "low"]
  readonly property var statusOrder: ["exploitable", "affected", "mitigated", "fixed", "not-affected"]

  // An alert outranks a newer running or failed run: until a successful review
  // says otherwise, the user still has something to do.
  function stateOf(status, now) {
    var result = status ? status.result : null
    if (result && result.level === "alert") return "alert"
    if (status && status.run.state === "running") return "running"
    if (status && status.run.state === "failed") return "failed"
    if (!result) return "never"
    if (now - Date.parse(result.checkedAt) > staleAfter) return "stale"
    return result.level
  }

  function sortedFindings(list) {
    return list.slice().sort(function(a, b) {
      return (severityOrder.indexOf(a.severity) - severityOrder.indexOf(b.severity))
        || (statusOrder.indexOf(a.status) - statusOrder.indexOf(b.status))
    })
  }

  function ago(iso) {
    var minutes = Math.max(0, Math.round((now - Date.parse(iso)) / 60000))
    if (minutes < 60) return minutes + " min ago"
    if (minutes < 48 * 60) return Math.round(minutes / 60) + " h ago"
    return Math.round(minutes / 1440) + " days ago"
  }

  function when(iso) {
    return Qt.formatDateTime(new Date(iso), "ddd d MMM HH:mm")
  }

  function toneColor(tone) {
    return tone === "alert" ? Color.background : tone === "warn" ? warning : root.barForeground
  }

  function severityColor(severity) {
    return severity === "critical" ? Color.urgent : severity === "high" ? warning : dim
  }

  function load(raw) {
    try {
      var parsed = JSON.parse(raw)
      status = parsed && parsed.schema === 1 ? parsed : null
    } catch (error) {
      status = null
    }
  }

  function runNow() {
    Quickshell.execDetached(["systemctl", "--user", "start", "--no-block", "security-watch.service"])
  }

  function openReport() {
    if (!result) return
    Quickshell.execDetached(["omarchy", "launch", "editor", result.report])
    root.close()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.now = Date.now()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.load(text())
    onLoadFailed: root.status = null
  }

  FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var match = text().match(/^\s*yellow\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
        || text().match(/^\s*color3\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
      if (match) root.warning = match[1]
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    // The watch misses status.json when its directory did not exist yet at
    // shell start (before the first run), so re-read on the staleness tick.
    onTriggered: {
      root.now = Date.now()
      statusFile.reload()
    }
  }

  Rectangle {
    visible: root.look.tone === "alert"
    anchors.fill: parent
    anchors.topMargin: Style.space(4)
    anchors.bottomMargin: Style.space(4)
    radius: Style.cornerRadius
    color: Color.urgent
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.look.glyph
    fontSize: Style.bar.iconFont
    foreground: root.toneColor(root.look.tone)
    dimmed: root.look.tone === "dim"
    tooltipText: "Security · " + root.look.label
      + (root.result ? "\n" + root.result.summary + "\nChecked " + root.ago(root.result.checkedAt) + " · " + root.findings.length + " findings" : "")
      + (root.todo.length ? "\n" + root.todo.length + " for you to do" : "")
      + "\nLeft: details"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          scroll.contentY = Math.max(0, Math.min(scroll.contentY + dy * Style.space(56),
                                                Math.max(0, scroll.contentHeight - scroll.height)))
      }
      onTextKey: function(text) {
        if (text === "o" || text === "O") root.openReport()
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
              text: "Security watch"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width - x
              anchors.baseline: title.baseline
              text: root.result ? "Checked " + root.ago(root.result.checkedAt) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }

          Text {
            width: parent.width
            text: root.look.label
              + (root.run && root.run.state === "failed" ? ": " + root.run.error : "")
              + (root.run && root.run.state === "running" ? " (started " + root.ago(root.run.startedAt) + ")" : "")
            textFormat: Text.PlainText
            color: root.look.tone === "alert" ? Color.urgent : root.look.tone === "warn" ? root.warning : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: root.look.tone === "alert"
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.result !== null
            width: parent.width
            text: root.result ? root.result.summary : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.result !== null
            width: parent.width
            text: !root.result ? "" : root.result.since
              ? "Window " + root.when(root.result.since) + " to " + root.when(root.result.checkedAt)
              : "First review, " + root.when(root.result.checkedAt) + ": every unfixed advisory plus the prior 30 days"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            visible: root.todo.length > 0
            text: "You should"
            foreground: Color.urgent
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.todo
            Rectangle {
              required property var modelData
              width: contentColumn.width
              implicitHeight: todoCopy.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.14)
              border.width: 2
              border.color: Color.urgent
              Column {
                id: todoCopy
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(4)
                Text {
                  width: parent.width
                  text: modelData.youShould
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  text: modelData.id + "  ·  " + modelData.title
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          PanelSectionHeader {
            visible: root.actions.length > 0
            text: "Changed on this machine"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.actions
            Column {
              required property var modelData
              width: contentColumn.width
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: modelData.summary
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              TextEdit {
                width: parent.width
                text: "Ran     " + modelData.command + "\nRevert  " + modelData.revert
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: TextEdit.WrapAnywhere
              }
            }
          }

          PanelSectionHeader {
            visible: root.findings.length > 0
            text: "Findings (" + root.findings.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.findings
            Item {
              required property var modelData
              width: contentColumn.width
              implicitHeight: findingCopy.implicitHeight + Style.space(8)
              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: findingMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
              }
              Column {
                id: findingCopy
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(4)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: modelData.severity.toUpperCase() + "  ·  " + modelData.status + "  ·  " + modelData.component
                  textFormat: Text.PlainText
                  color: root.severityColor(modelData.severity)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modelData.id + "  ·  " + modelData.title
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  text: modelData.detail
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
              MouseArea {
                id: findingMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: modelData.references.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(modelData.references[0])
              }
            }
          }

          Row {
            spacing: Style.space(8)
            anchors.horizontalCenter: parent.horizontalCenter
            PanelActionButton {
              width: Style.space(140)
              size: Style.space(30)
              iconText: root.watchState === "running" ? "Checking…" : "Run check now"
              tooltipText: "Start security-watch.service in the background"
              foreground: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              bordered: true
              focusable: true
              enabled: !(root.run && root.run.state === "running")
              onClicked: root.runNow()
            }
            PanelActionButton {
              width: Style.space(140)
              size: Style.space(30)
              iconText: "Open report"
              tooltipText: root.result ? root.result.report : "No report yet"
              foreground: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              bordered: true
              focusable: true
              enabled: root.result !== null
              onClicked: root.openReport()
            }
          }

          Text {
            width: parent.width
            text: "Click a finding for its advisory  ·  O open report  ·  Esc close"
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
