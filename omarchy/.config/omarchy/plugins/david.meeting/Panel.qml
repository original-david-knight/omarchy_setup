import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "david.meeting"
  ipcTarget: "david.meeting"

  readonly property string helperDirectory: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property var calendarData: ({ status: "loading", events: [] })
  readonly property bool litraEnabled: setting("litra", false) === true
  property var lightData: ({ status: "loading" })
  property var recorderData: ({ state: "unknown" })
  property string recorderError: ""
  property string recorderWatchError: ""
  property string pendingRecorderAction: ""
  property string cursorRow: "recorder"
  // fake_me AI stand-in (~/workspace/fake_me), controlled through its `fakeme` CLI
  // Opens a link in the work Chrome profile; it refuses anything but work, Meet and Calendar URLs.
  readonly property string openerCommand: String(setting("opener", Quickshell.env("HOME") + "/bin/open-work-url"))
  readonly property string fakemeCommand: String(setting("fakeme", "/home/david/workspace/fake_me/scripts/fakeme"))
  property var avatarData: ({ state: "unknown" })
  property string avatarError: ""
  readonly property string avatarState: avatarData.state
  readonly property bool avatarOn: /^(starting|listening|thinking|speaking)$/.test(avatarState)
  readonly property bool avatarReady: /^(listening|thinking|speaking)$/.test(avatarState)
  readonly property bool avatarMuted: avatarData.auto === false
  readonly property var briefingInfo: avatarData.briefing || ({})
  readonly property string briefingLabel: briefingInfo.running ? "Briefing: refreshing (about 20 s)..."
    : briefingInfo.error ? "Briefing refresh failed: " + briefingInfo.error
    : briefingInfo.updated ? "Briefing updated " + (briefingInfo.updated.slice(0, 10) === localDate(nowMs)
        ? briefingInfo.updated.slice(11, 16) : Qt.formatDateTime(new Date(briefingInfo.updated), "MMM d HH:mm"))
    : "No briefing yet"
  readonly property bool avatarNeedsCamera: avatarData.camera === false && !avatarOn
  readonly property string avatarLabel: avatarNeedsCamera ? "Needs its camera (FakeMe-Cam) — one-time setup"
    : avatarState === "off" ? "Off"
    : avatarState === "starting" ? "Starting (about 15 s)..."
    : avatarState === "listening" ? (avatarMuted ? "Listening · muted, won't answer" : "Listening")
    : avatarState === "thinking" ? "Thinking..."
    : avatarState === "speaking" ? "Speaking" : "Unavailable"
  property real nowMs: Date.now()

  readonly property bool calendarCurrent: calendarData.status === "ready" && calendarData.date === localDate(nowMs)
  readonly property var nextMeeting: chooseMeeting(calendarCurrent ? calendarData.events : [], nowMs)
  readonly property bool meetingOngoing: nextMeeting !== null && Date.parse(nextMeeting.starts_at) <= nowMs
  readonly property bool lightReady: lightData.status === "ready"
  readonly property bool lightBusy: lightProcess.running
  readonly property string recorderState: recorderData.state
  readonly property bool recording: recorderState === "recording" || recorderState === "paused"
  readonly property bool canStart: (recorderState === "idle" || recorderState === "done") && pendingRecorderAction === ""
  readonly property bool canStop: recording && pendingRecorderAction === ""
  readonly property string recordingLabel: recorderState === "recording" ? "Recording " + duration(recorderData.elapsed)
    : recorderState === "paused" ? "Paused " + duration(recorderData.elapsed)
    : recorderState === "stopping" ? "Saving recording"
    : recorderState === "transcribing" ? "Transcribing " + Math.round((recorderData.progress || 0) * 100) + "%"
    : recorderState === "done" ? "Recording saved"
    : recorderState === "idle" ? "Ready to record"
    : recorderState === "off" ? "Recorder closed" : "Recorder unavailable"
  readonly property string calendarMessage: calendarData.status === "loading" ? "Loading work calendar..."
    : calendarData.status !== "ready" ? String(calendarData.message || "Calendar unavailable")
    : !calendarCurrent ? "Calendar needs a refresh"
    : nextMeeting ? String(nextMeeting.title || "Untitled meeting")
    : calendarData.warning ? "Next work meeting unavailable" : "No more work meetings in today's agenda"
  // The call when there is one, else the event; a feed without links still opens the meeting's day.
  readonly property string meetingLink: !nextMeeting ? "" : nextMeeting.meet_url || nextMeeting.html_link
    || "https://calendar.google.com/calendar/r/day/" + Qt.formatDate(new Date(nextMeeting.starts_at), "yyyy/M/d")
  readonly property string meetingAction: !nextMeeting ? "" : nextMeeting.meet_url ? "Join Google Meet"
    : nextMeeting.html_link ? "Open event" : "Open calendar"
  readonly property string meetingTime: !nextMeeting ? "" : meetingOngoing ? "In progress · ends " + localTime(nextMeeting.ends_at)
    : localTime(nextMeeting.starts_at) + " · in " + Math.max(1, Math.ceil((Date.parse(nextMeeting.starts_at) - nowMs) / 60000)) + " min"
  readonly property string barLabel: recording || recorderState === "stopping" || recorderState === "transcribing"
    ? recordingLabel : nextMeeting ? (meetingOngoing ? "Meeting now" : "Meeting " + localTime(nextMeeting.starts_at)) : "Meeting"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function localDate(ms) {
    return Qt.formatDate(new Date(ms), "yyyy-MM-dd")
  }
  function localTime(stamp) {
    return Qt.formatTime(new Date(stamp), "HH:mm")
  }
  function duration(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(total / 60)
    return (minutes < 10 ? "0" : "") + minutes + ":" + (total % 60 < 10 ? "0" : "") + (total % 60)
  }
  function chooseMeeting(events, now) {
    var rows = Array.isArray(events) ? events : []
    var next = null
    for (var i = 0; i < rows.length; i++) {
      var event = rows[i]
      if (Date.parse(event.ends_at) <= now) continue
      if (next === null || Date.parse(event.starts_at) < Date.parse(next.starts_at)) next = event
    }
    return next
  }
  function readResult(raw, source) {
    try {
      var value = JSON.parse(String(raw))
      if (!value || typeof value.status !== "string") throw new Error("Missing status")
      return value
    } catch (error) {
      return { status: "error", message: source + " did not return a readable status" }
    }
  }
  function refreshCalendar() {
    if (calendarProcess.running) return
    calendarTimeout.restart()
    calendarProcess.running = true
  }
  function readLight() {
    if (!litraEnabled || lightProcess.running || brightness.dragging || temperature.dragging) return
    lightProcess.command = [helperDirectory + "litra", "status"]
    lightTimeout.restart()
    lightProcess.running = true
  }
  function setLight(field, value) {
    if (!litraEnabled || !lightReady || lightProcess.running) return
    lightProcess.command = [helperDirectory + "litra", "set", field, String(value)]
    lightTimeout.restart()
    lightProcess.running = true
  }
  function toggleLight() { if (lightReady) setLight("power", lightData.power ? "off" : "on") }
  function refresh() { refreshCalendar(); readLight() }
  function consumeRecorder(line) {
    try {
      var state = JSON.parse(line)
      if (!state || !/^(off|idle|recording|paused|stopping|transcribing|done)$/.test(state.state)) throw new Error("Unknown recorder state")
      recorderData = state
      recorderWatchError = ""
      var confirmed = pendingRecorderAction === "start" && state.state === "recording"
        || pendingRecorderAction === "pause" && state.state === "paused"
        || pendingRecorderAction === "resume" && state.state === "recording"
        || pendingRecorderAction === "stop" && /^(stopping|transcribing|done|idle)$/.test(state.state)
      if (confirmed) { pendingRecorderAction = ""; recorderError = ""; actionTimeout.stop() }
    } catch (error) {
      recorderData = { state: "unknown" }
      recorderWatchError = "Recorder status could not be read"
    }
  }
  function openMeeting() {
    if (meetingLink) Quickshell.execDetached([openerCommand, meetingLink])
  }
  function openRecorder() {
    Quickshell.execDetached(["omarchy-meeting-recorder"])
  }
  function recorderAction(action) {
    if (pendingRecorderAction !== "" || recorderCommand.running) return
    if (action === "start" && !canStart) return
    if ((action === "stop" || action === "pause" || action === "resume") && !canStop) return
    recorderError = ""
    pendingRecorderAction = action
    recorderCommand.command = ["omarchy-meeting-recorder", action === "resume" ? "pause" : action]
    recorderCommand.running = true
    actionTimeout.restart()
  }
  function avatar(args) {
    if (avatarCommand.running) return
    avatarError = ""
    avatarCommand.command = [fakemeCommand].concat(args)
    avatarCommand.running = true
  }
  function sendLine(kind) {
    var line = avatarLine.text.trim()
    if (line === "" || !avatarReady) return
    avatar([kind, line])
    avatarLine.text = ""
  }
  function toggleAvatar() {
    if (avatarNeedsCamera) avatar(["setup-camera"])
    else if (avatarState !== "starting") avatar([avatarOn ? "stop" : "start"])
  }
  function activateRow() {
    if (cursorRow === "meeting") openMeeting()
    else if (cursorRow === "recorder") {
      if (pendingRecorderAction !== "") return
      if (canStart) recorderAction("start")
      else openRecorder()
    } else if (cursorRow === "avatar") toggleAvatar()
    else if (cursorRow === "light") toggleLight()
    else if (cursorRow === "refresh") refresh()
  }
  function moveCursor(dx, dy) {
    var rows = (nextMeeting ? ["meeting"] : []).concat(litraEnabled
      ? ["recorder", "avatar", "light", "brightness", "temperature", "refresh"] : ["recorder", "avatar", "refresh"])
    if (dy !== 0) cursorRow = rows[(rows.indexOf(cursorRow) + dy + rows.length) % rows.length]
    var targets = { meeting: meetingSection, recorder: recorderSection, avatar: avatarSection, light: lightSection, brightness: brightness, temperature: temperature, refresh: refreshButton }
    var target = targets[cursorRow]
    var top = target.mapToItem(content, 0, 0).y
    if (top < scroll.contentY) scroll.contentY = top
    else if (top + target.height > scroll.contentY + scroll.height) scroll.contentY = Math.max(0, top + target.height - scroll.height)
    if (dx !== 0 && lightReady) {
      if (cursorRow === "brightness") setLight("brightness", Math.max(20, Math.min(250, lightData.brightness + dx * 10)))
      else if (cursorRow === "temperature") setLight("temperature", Math.max(2700, Math.min(6500, lightData.temperature + dx * 100)))
    }
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { nowMs = Date.now(); refresh() }

  Timer { interval: 15000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.refreshCalendar() }
  Timer { interval: root.opened ? 3000 : 30000; running: root.litraEnabled; repeat: true; onTriggered: root.readLight() }
  Timer { interval: 5000; running: !recorderWatch.running; repeat: true; onTriggered: recorderWatch.running = true }
  Timer {
    id: calendarTimeout
    interval: 25000
    onTriggered: {
      calendarProcess.running = false
      root.calendarData = { status: "error", message: "Calendar could not be loaded" }
    }
  }
  Timer {
    id: lightTimeout
    interval: 8000
    onTriggered: {
      lightProcess.running = false
      root.lightData = { status: "error", message: "Light did not respond" }
    }
  }
  Timer {
    id: actionTimeout
    interval: 8000
    onTriggered: {
      root.pendingRecorderAction = ""
      root.recorderError = "Recorder did not confirm the action. Open it for details."
    }
  }
  Process {
    id: calendarProcess
    command: [root.helperDirectory + "calendar"]
    stdout: StdioCollector { id: calendarOutput }
    onExited: {
      calendarTimeout.stop()
      root.calendarData = root.readResult(calendarOutput.text, "Calendar")
    }
  }
  Process {
    id: lightProcess
    stdout: StdioCollector { id: lightOutput }
    onExited: {
      lightTimeout.stop()
      root.lightData = root.readResult(lightOutput.text, "Light")
    }
  }
  Process {
    id: recorderWatch
    command: ["omarchy-meeting-recorder", "watch"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.consumeRecorder(line) } }
    onExited: {
      root.recorderData = { state: "unknown" }
      root.recorderWatchError = "Meeting Recorder is unavailable"
    }
  }
  Process {
    id: avatarWatch
    command: [root.fakemeCommand, "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try { root.avatarData = JSON.parse(line) } catch (error) { root.avatarData = { state: "unknown" } }
      }
    }
    onExited: root.avatarData = { state: "unknown" }
  }
  Timer { interval: 5000; running: !avatarWatch.running; repeat: true; onTriggered: avatarWatch.running = true }
  Process {
    id: avatarCommand
    stderr: StdioCollector { id: avatarCommandError }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.avatarError = avatarCommandError.text.trim() || "fakeme did not accept the command"
    }
  }
  Process {
    id: recorderCommand
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.pendingRecorderAction = ""
        actionTimeout.stop()
        root.recorderError = "The recorder could not accept the action. Open it for details."
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.avatarOn ? "󰚩 " : "") + (root.recording ? "󰑋" : "󰃰") + ((root.bar && root.bar.vertical) ? "" : "  " + root.barLabel)
    active: root.recording
    tooltipText: root.calendarMessage + (root.nextMeeting ? "\n" + root.meetingTime : "")
      + "\n" + root.recordingLabel + "\nAI stand-in: " + root.avatarLabel + "\nClick to open meeting controls"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateRow()
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "o") root.openRecorder()
        else if (text === "j") root.openMeeting()
        else if (text === "p") root.recorderAction(root.recorderState === "paused" ? "resume" : "pause")
        else if (text === "s") root.recorderAction("stop")
        else if (text === "a") root.toggleAvatar()
        else if (text === "h" && root.avatarReady) root.avatar(["hello"])
        else if (text === "m" && root.avatarReady) root.avatar([root.avatarMuted ? "unmute" : "mute"])
        else if (text === "b") root.avatar(["briefing"])
        else if (text === "l") root.avatar(["log"])
        else if (text === "t" && root.avatarReady) avatarLine.forceActiveFocus()
      }
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(14)

          PanelHero { title: "Meeting"; meta: root.litraEnabled ? "Work calendar · light · recorder" : "Work calendar · recorder"; foreground: root.foreground }
          PanelSectionHeader { id: meetingSection; text: "NEXT WORK MEETING TODAY"; foreground: root.foreground }
          Text {
            width: parent.width
            text: root.calendarMessage
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            MouseArea {
              anchors.fill: parent
              enabled: root.nextMeeting !== null
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openMeeting()
            }
          }
          Text {
            width: parent.width
            visible: root.nextMeeting !== null
            text: root.meetingTime + (root.nextMeeting && root.nextMeeting.calendar_name ? "\n" + root.nextMeeting.calendar_name : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Button {
            objectName: "meetingOpen"
            visible: root.nextMeeting !== null
            text: root.meetingAction
            bordered: true
            hasCursor: root.cursorRow === "meeting"
            onClicked: root.openMeeting()
          }
          Text {
            width: parent.width
            text: root.calendarData.warning || ""
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader { id: recorderSection; text: "MEETING RECORDER"; foreground: root.foreground }
          Text {
            width: parent.width
            text: root.recordingLabel + (root.recorderData.title ? "\n" + root.recorderData.title : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.recording ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Flow {
            width: parent.width
            spacing: Style.space(8)
            Button {
              objectName: "recorderPrimary"
              text: root.canStart ? "Start recording" : "Open recorder"
              bordered: true
              hasCursor: root.cursorRow === "recorder"
              enabled: root.pendingRecorderAction === ""
              onClicked: root.canStart ? root.recorderAction("start") : root.openRecorder()
            }
            Button {
              objectName: "recorderPause"
              text: root.recorderState === "paused" ? "Resume" : "Pause"
              visible: root.recording
              enabled: root.canStop
              bordered: true
              onClicked: root.recorderAction(root.recorderState === "paused" ? "resume" : "pause")
            }
            Button {
              objectName: "recorderStop"
              text: "Stop"
              visible: root.recording
              enabled: root.canStop
              bordered: true
              onClicked: root.recorderAction("stop")
            }
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: root.recorderWatchError || root.recorderError
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader { id: avatarSection; text: "AI STAND-IN"; foreground: root.foreground }
          Text {
            width: parent.width
            text: root.avatarLabel
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.avatarState === "speaking" ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            visible: root.avatarReady && (root.avatarData.heard || root.avatarData.said)
            text: (root.avatarData.heard ? "Heard: " + root.avatarData.heard : "")
              + (root.avatarData.heard && root.avatarData.said ? "\n" : "")
              + (root.avatarData.said ? "Said: " + root.avatarData.said : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Flow {
            width: parent.width
            spacing: Style.space(8)
            Button {
              objectName: "avatarPower"
              text: root.avatarNeedsCamera ? "Create camera" : root.avatarOn ? "Stop stand-in" : "Start stand-in"
              bordered: true
              hasCursor: root.cursorRow === "avatar"
              selected: root.avatarOn
              enabled: !avatarCommand.running && root.avatarState !== "starting" && root.avatarState !== "unknown"
              onClicked: root.toggleAvatar()
            }
            Button {
              objectName: "avatarHello"
              text: "Say hello"
              visible: root.avatarReady
              enabled: !avatarCommand.running
              bordered: true
              onClicked: root.avatar(["hello"])
            }
            Button {
              objectName: "avatarMute"
              text: root.avatarMuted ? "Unmute" : "Mute"
              visible: root.avatarReady
              enabled: !avatarCommand.running
              bordered: true
              selected: root.avatarMuted
              onClicked: root.avatar([root.avatarMuted ? "unmute" : "mute"])
            }
            Button {
              objectName: "avatarHush"
              text: "Hush"
              visible: root.avatarState === "speaking"
              enabled: !avatarCommand.running
              bordered: true
              onClicked: root.avatar(["hush"])
            }
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: root.avatarError || (root.avatarState === "off" && !root.avatarNeedsCamera ? String(root.avatarData.message || "") : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.avatarReady
            TextField {
              id: avatarLine
              width: parent.width
              foreground: root.foreground
              placeholderText: "Type a line for it to say..."
              onAccepted: root.sendLine("say")
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }
            Flow {
              width: parent.width
              spacing: Style.space(8)
              Button {
                objectName: "avatarSay"
                text: "Say it"
                bordered: true
                enabled: avatarLine.text.trim() !== "" && !avatarCommand.running
                onClicked: root.sendLine("say")
              }
              Button {
                objectName: "avatarAsk"
                text: "Answer it"
                bordered: true
                enabled: avatarLine.text.trim() !== "" && !avatarCommand.running
                onClicked: root.sendLine("ask")
              }
            }
          }
          Text {
            width: parent.width
            text: root.briefingLabel
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.briefingInfo.error ? Color.urgent : Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Flow {
            width: parent.width
            spacing: Style.space(8)
            Button {
              objectName: "briefingRefresh"
              text: "Refresh briefing"
              bordered: true
              enabled: !root.briefingInfo.running && !avatarCommand.running
              onClicked: root.avatar(["briefing"])
            }
            Button {
              objectName: "briefingReview"
              text: "Review briefing"
              bordered: true
              enabled: !avatarCommand.running
              onClicked: root.avatar(["review"])
            }
            Button {
              objectName: "avatarLog"
              text: "Live log"
              bordered: true
              enabled: !avatarCommand.running
              onClicked: root.avatar(["log"])
            }
          }
          PanelSeparator { visible: root.litraEnabled; foreground: root.foreground }
          Row {
            id: lightSection
            visible: root.litraEnabled
            width: parent.width
            spacing: Style.space(12)
            Text {
              width: parent.width - powerButton.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: "Litra Glow"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Button {
              id: powerButton
              objectName: "lightPower"
              text: root.lightReady ? (root.lightData.power ? "Turn off" : "Turn on") : "Unavailable"
              enabled: root.lightReady && !root.lightBusy
              hasCursor: root.cursorRow === "light"
              bordered: true
              selected: root.lightReady && root.lightData.power
              onClicked: root.toggleLight()
            }
          }
          Text {
            width: parent.width
            visible: root.litraEnabled && !root.lightReady
            text: root.lightData.status === "loading" ? "Finding light..." : String(root.lightData.message || "Light unavailable")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Column {
            visible: root.litraEnabled
            width: parent.width
            spacing: Style.space(6)
            enabled: root.lightReady && !root.lightBusy
            opacity: root.lightReady ? 1 : 0.4
            Text {
              text: "Brightness" + (root.lightReady ? " · " + Math.round((brightness.dragging ? brightness.liveValue : root.lightData.brightness) / 250 * 100) + "%" : "")
              color: root.cursorRow === "brightness" ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            PanelSlider {
              id: brightness
              objectName: "lightBrightness"
              width: parent.width
              bar: root.bar
              minimum: 20; maximum: 250; step: 10; integer: true
              value: root.lightReady ? root.lightData.brightness : 20
              onReleased: function(value) { root.setLight("brightness", Math.round(value)) }
            }
            Text {
              text: "Color temperature" + (root.lightReady ? " · " + Math.round((temperature.dragging ? temperature.liveValue : root.lightData.temperature) / 100) * 100 + " K" : "")
              color: root.cursorRow === "temperature" ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            PanelSlider {
              id: temperature
              objectName: "lightTemperature"
              width: parent.width
              bar: root.bar
              minimum: 2700; maximum: 6500; step: 100; integer: true
              value: root.lightReady ? root.lightData.temperature : 2700
              onReleased: function(value) { root.setLight("temperature", Math.round(value / 100) * 100) }
            }
            Row {
              width: parent.width
              Text {
                width: parent.width / 2
                text: "2700 K warm"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width / 2
                horizontalAlignment: Text.AlignRight
                text: "6500 K cool"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
          Button {
            id: refreshButton
            text: "Refresh"
            hasCursor: root.cursorRow === "refresh"
            onClicked: root.refresh()
          }
          Text {
            width: parent.width
            text: "Arrows adjust · Enter selects\nP pause/resume · S stop · O open recorder\nA start/stop stand-in · H say hello · M mute/unmute\nT type a line · B refresh briefing · L live log"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
