import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// SteelSeries Arctis Nova Pro Omni. The `headset` helper owns the base
// station's vendor HID interface: it streams state as JSON lines and takes
// commands on stdin, so a wheel notch or an ANC tap never spawns a process.
// The microphone switch is the headset's PipeWire source, which every app
// hears; the mute button on the earcup is reported separately.
Panel {
  id: root
  moduleName: "david.headset"
  ipcTarget: ""
  manageIpc: false

  property var deviceState: ({ connected: false })
  property string errorText: ""
  property real wheelAccumulator: 0
  property bool cursorActive: false
  property string cursorRow: "anc"
  property int liveVolume: -1
  property var liveBands: ({})
  readonly property var bandFrequencies: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

  readonly property string helper: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.headset/headset"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool compactBar: (bar && bar.vertical) || (root.QsWindow.window !== null
    && root.QsWindow.window.screen !== null && root.QsWindow.window.screen.width < 1920)

  readonly property bool connected: !!deviceState.connected
  readonly property bool online: connected && deviceState.online !== false
  readonly property string anc: String(deviceState.anc || "off")
  readonly property bool ancOn: anc === "on"
  readonly property int ancLevel: Number(deviceState.anc_level || 3)
  readonly property int transparency: Number(deviceState.transparency || 5)
  readonly property int battery: deviceState.battery === undefined || deviceState.battery === null ? -1 : Number(deviceState.battery)
  readonly property int spareBattery: deviceState.spare_battery === undefined || deviceState.spare_battery === null ? -1 : Number(deviceState.spare_battery)
  readonly property string charging: String(deviceState.charging || "unknown")
  readonly property bool hasVolume: deviceState.volume !== undefined && deviceState.volume !== null
  readonly property int volume: hasVolume ? Number(deviceState.volume) : 0
  readonly property bool micHardMuted: !!deviceState.mic_muted
  readonly property int sidetone: Number(deviceState.sidetone || 0)
  readonly property var eqBands: Array.isArray(deviceState.eq_bands) ? deviceState.eq_bands : []
  readonly property string stateError: String(deviceState.error || "")

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var micSource: {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && String(n.name || "").indexOf("alsa_input.usb-SteelSeries_Arctis_Nova_Pro_Omni") === 0) return n
    }
    return null
  }
  readonly property bool micSoftMuted: micSource && micSource.audio ? micSource.audio.muted : false
  readonly property bool micLive: online && !micHardMuted && micSource !== null && !micSoftMuted
  readonly property string micDescription: micSource === null ? "Microphone not found in PipeWire"
    : micSoftMuted ? "Muted for every app" : "Live for every app"

  readonly property string ancLabel: !online ? "Offline" : anc === "on" ? "ANC " + levelName(ancLevel)
    : anc === "transparent" ? "Transparency " + transparency + "/10" : "Noise control off"
  readonly property string batteryLabel: battery < 0 ? "" : battery + "%" + (charging === "charging" ? " charging" : "")
  readonly property string heroMeta: !connected ? "Not connected"
    : !online ? "Headset powered off" + (spareBattery >= 0 ? " · spare " + spareBattery + "%" : "")
    : "Battery " + batteryLabel + (spareBattery >= 0 ? " · spare " + spareBattery + "%" : "")
  readonly property var rows: online ? ["anc", "level", "volume", "mic", "sidetone", "eq"] : []

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function levelName(level) {
    return level <= 1 ? "low" : level === 2 ? "medium" : "high"
  }

  function batteryGlyph() {
    if (!online) return "󰂑"
    if (charging === "charging") return "󰂄"
    if (battery >= 90) return "󰁹"
    if (battery >= 70) return "󰂁"
    if (battery >= 50) return "󰁿"
    if (battery >= 30) return "󰁽"
    if (battery >= 10) return "󰁻"
    return "󰂃"
  }

  function consume(line) {
    var text = String(line || "").trim()
    if (!text) return
    try {
      var next = JSON.parse(text)
      deviceState = next
      if (liveVolume >= 0 && !volumeSlider.dragging) liveVolume = -1
      liveBands = ({})
    } catch (error) {
      errorText = "The headset helper sent something unreadable"
    }
  }

  function command(words) {
    if (!watchProcess.running) { errorText = "The headset helper is not running"; return }
    watchProcess.write(words.join(" ") + "\n")
  }

  function setAnc(mode) { command(["set", "anc", mode]) }
  function toggleAnc() { setAnc(ancOn ? "off" : "on") }
  function cycleAnc(direction) {
    var modes = ["off", "transparent", "on"]
    setAnc(modes[(modes.indexOf(anc) + direction + 3) % 3])
  }
  function setAncLevel(level) { command(["set", "anc-level", String(level)]) }
  function setTransparency(level) { command(["set", "transparency", String(level)]) }
  function setVolume(percent) {
    var value = Math.max(0, Math.min(100, Math.round(percent)))
    liveVolume = value
    command(["set", "volume", String(value)])
  }
  function nudgeVolume(steps) {
    if (!online) return
    if (!hasVolume) { errorText = "Turn the knob on the DAC once so the widget learns its volume"; return }
    setVolume((liveVolume >= 0 ? liveVolume : volume) + steps * 4)
  }
  function setSidetone(level) { command(["set", "sidetone", String(level)]) }
  function bandValue(index) {
    if (liveBands[index] !== undefined) return liveBands[index]
    var stored = eqBands.length > index ? eqBands[index] : null
    return stored === null || stored === undefined ? 20 : Number(stored)
  }
  function bandKnown(index) {
    return liveBands[index] !== undefined || (eqBands.length > index && eqBands[index] !== null && eqBands[index] !== undefined)
  }
  function gainText(value) {
    var db = (value - 20) / 2
    return db === 0 ? "0" : (db > 0 ? "+" : "") + (Number.isInteger(db) ? db : db.toFixed(1))
  }
  function previewBand(index, value) {
    var next = Object.assign({}, liveBands)
    next[index] = Math.max(0, Math.min(40, Math.round(value)))
    liveBands = next
  }
  function setBand(index, value) {
    var clamped = Math.max(0, Math.min(40, Math.round(value)))
    previewBand(index, clamped)
    command(["set", "eq-band", (index + 1) + ":" + clamped])
  }
  function flattenEq() {
    liveBands = ({})
    command(["set", "eq-flat", "1"])
  }
  function toggleMic() {
    if (!micSource || !micSource.audio) { errorText = "The headset microphone is not available in PipeWire"; return }
    micSource.audio.muted = !micSource.audio.muted
  }

  function moveCursor(delta) {
    if (!rows.length) return
    var at = rows.indexOf(cursorRow)
    cursorRow = rows[Math.max(0, Math.min(rows.length - 1, (at < 0 ? 0 : at) + delta))]
  }
  function adjustCursor(direction) {
    if (cursorRow === "anc") cycleAnc(direction)
    else if (cursorRow === "level") {
      if (anc === "on") setAncLevel(Math.max(1, Math.min(3, ancLevel + direction)))
      else if (anc === "transparent") setTransparency(Math.max(1, Math.min(10, transparency + direction)))
    }
    else if (cursorRow === "volume") nudgeVolume(direction)
    else if (cursorRow === "mic") toggleMic()
    else if (cursorRow === "sidetone") setSidetone(Math.max(0, Math.min(10, sidetone + direction)))
    else if (cursorRow === "eq") flattenEq()
  }
  function activateCursor() {
    if (cursorRow === "anc") toggleAnc()
    else if (cursorRow === "mic") toggleMic()
    else adjustCursor(1)
  }
  function hoverRow(row) {
    cursorActive = true
    cursorRow = row
  }

  onOpenedChanged: if (opened) {
    errorText = ""
    cursorActive = false
    cursorRow = "anc"
    command(["refresh"])
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  PwObjectTracker { objects: root.micSource ? [root.micSource] : [] }

  Process {
    id: watchProcess
    command: [root.helper, "watch"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.consume(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).trim()) root.errorText = String(line).trim() }
    }
    onExited: function(code) {
      root.deviceState = { connected: false }
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: watchProcess.running = true
  }

  IpcHandler {
    target: "david.headset"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function toggleAnc(): void { root.toggleAnc() }
    function anc(mode: string): void { root.setAnc(mode) }
    function toggleMic(): void { root.toggleMic() }
    function volumeUp(): void { root.nudgeVolume(1) }
    function volumeDown(): void { root.nudgeVolume(-1) }
    function status(): string { return JSON.stringify(root.deviceState) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋎"
    labelVisible: false
    dimmed: !root.online
    fixedWidth: root.compactBar || !root.online ? Style.space(34) : Style.space(root.hasVolume ? 82 : 58)
    tooltipText: "Arctis Nova Pro Omni · " + root.heroMeta + "\n" + root.ancLabel
      + (root.online ? (root.micLive ? " · mic live" : root.micHardMuted ? " · mic muted on the headset" : " · mic muted") : "")
      + "\nLeft: panel · Middle: ANC on/off · Right: mic · Scroll: headset volume"
    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.toggleAnc()
      else if (code === Qt.RightButton) root.toggleMic()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.nudgeVolume(wheel.steps)
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰋎"
        textFormat: Text.PlainText
        color: root.online && root.ancOn ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }
      Text {
        visible: !root.compactBar && root.online
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasVolume ? (root.liveVolume >= 0 ? root.liveVolume : root.volume) + "%" : "—"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        visible: !root.compactBar && root.online && !root.micLive
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍭"
        textFormat: Text.PlainText
        color: root.bar ? root.bar.urgent : Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onTextKey: function(text) {
        if (text === "a" || text === "A") root.toggleAnc()
        else if (text === "m" || text === "M") root.toggleMic()
        else if (text === "t" || text === "T") root.setAnc(root.anc === "transparent" ? "off" : "transparent")
        else if (text === "r" || text === "R") root.command(["refresh"])
        else if (text === "+" || text === "=") root.nudgeVolume(1)
        else if (text === "-") root.nudgeVolume(-1)
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: scroll.width
          spacing: Style.space(14)

          // ---------- Hero: headset · battery · ANC switch ----------
          PanelHero {
            width: parent.width
            title: "Arctis Nova Pro Omni"
            meta: root.heroMeta
            detail: root.online ? root.batteryGlyph() : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.online ? 1 : 0.45
            iconComponent: Component {
              Text {
                text: "󰋎"
                textFormat: Text.PlainText
                color: root.online && root.ancOn ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: root.ancOn
                enabled: root.online
                opacity: root.online ? 1 : 0.4
                hasCursor: root.cursorActive && root.cursorRow === "anc"
                foreground: root.foreground
                onHovered: function(on) { if (on) root.hoverRow("anc") }
                onToggled: root.toggleAnc()
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.ancOn ? "Switch noise cancelling off" : "Switch noise cancelling on"
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          Text {
            visible: !root.connected
            width: parent.width
            text: root.stateError || "Plug in the base station and set its mode switch to USB-1."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---------- Noise control ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)
            opacity: root.online ? 1 : 0.4

            Item {
              width: parent.width
              implicitHeight: Math.max(noiseHeader.implicitHeight, noiseState.implicitHeight)
              PanelSectionHeader {
                id: noiseHeader
                text: "NOISE CONTROL"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: noiseState
                text: root.ancLabel.toUpperCase()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              width: parent.width
              height: ancGroup.implicitHeight + Style.space(8)
              hasCursor: root.cursorActive && root.cursorRow === "anc"
              foreground: root.foreground
              HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("anc") }
              ButtonGroup {
                id: ancGroup
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                enabled: root.online
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                value: root.anc
                options: [
                  { value: "off", label: "Off", tooltip: "Passive isolation only" },
                  { value: "transparent", label: "Transparent", tooltip: "Let the room in" },
                  { value: "on", label: "ANC", tooltip: "Active noise cancelling" }
                ]
                onChanged: function(value) { root.setAnc(value) }
              }
            }

            CursorSurface {
              visible: root.anc === "on"
              width: parent.width
              height: levelRow.implicitHeight + Style.space(8)
              hasCursor: root.cursorActive && root.cursorRow === "level"
              foreground: root.foreground
              HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("level") }
              Row {
                id: levelRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Strength"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                ButtonGroup {
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: root.online
                  focusable: false
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  value: String(root.ancLevel)
                  options: [
                    { value: "1", label: "Low" },
                    { value: "2", label: "Medium" },
                    { value: "3", label: "High" }
                  ]
                  onChanged: function(value) { root.setAncLevel(Number(value)) }
                }
              }
            }

            Column {
              visible: root.anc === "transparent"
              width: parent.width
              spacing: Style.space(4)
              Item {
                width: parent.width
                implicitHeight: transparencyLabel.implicitHeight
                Text {
                  id: transparencyLabel
                  text: "Transparency"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                }
                Text {
                  text: (transparencySlider.dragging ? transparencySlider.liveValue : root.transparency) + " / 10"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                }
              }
              CursorSurface {
                width: parent.width
                height: transparencySlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.cursorRow === "level"
                foreground: root.foreground
                outline: true
                HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("level") }
                PanelSlider {
                  id: transparencySlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  minimum: 1
                  maximum: 10
                  step: 1
                  integer: true
                  tickCount: 10
                  enabled: root.online
                  value: root.transparency
                  onReleased: function(v) { root.setTransparency(Math.round(v)) }
                }
              }
            }
          }

          // ---------- Headset volume ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)
            opacity: root.online ? 1 : 0.4

            Item {
              width: parent.width
              implicitHeight: Math.max(volumeHeader.implicitHeight, volumePercent.implicitHeight)
              PanelSectionHeader {
                id: volumeHeader
                text: "HEADSET VOLUME"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: volumePercent
                text: root.hasVolume
                  ? Math.round(volumeSlider.dragging ? volumeSlider.liveValue : (root.liveVolume >= 0 ? root.liveVolume : root.volume)) + "%"
                  : "—"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              width: parent.width
              height: volumeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.cursorRow === "volume"
              foreground: root.foreground
              outline: true
              HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("volume") }
              PanelSlider {
                id: volumeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: 100
                step: 4
                integer: true
                enabled: root.online
                opacity: root.hasVolume ? 1 : 0.45
                value: root.hasVolume ? (root.liveVolume >= 0 ? root.liveVolume : root.volume) : 50
                onReleased: function(v) { root.setVolume(v) }
              }
            }

            Text {
              width: parent.width
              text: root.hasVolume
                ? "The knob on the base station and this slider move together."
                : "Turn the knob on the base station once so the slider can find it."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              leftPadding: Style.space(4)
            }
          }

          // ---------- Microphone ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)
            opacity: root.online ? 1 : 0.4

            PanelSectionHeader {
              text: "MICROPHONE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Microphone"
              description: root.micDescription
              checked: root.micSource !== null && !root.micSoftMuted
              hasCursor: root.cursorActive && root.cursorRow === "mic"
              foreground: root.foreground
              fontFamily: root.fontFamily
              titleSize: Style.font.body
              onHovered: function(on) { if (on) root.hoverRow("mic") }
              onClicked: root.toggleMic()
            }

            Row {
              visible: root.online && root.micHardMuted
              width: parent.width
              spacing: Style.space(8)
              leftPadding: Style.space(4)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍭"
                textFormat: Text.PlainText
                color: root.bar ? root.bar.urgent : Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                width: parent.width - Style.space(12) - Style.font.icon - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "Also muted on the headset itself. Only the mute button on the earcup changes that."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Item {
              width: parent.width
              implicitHeight: sidetoneLabel.implicitHeight
              Text {
                id: sidetoneLabel
                text: "Hear your own voice"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
              }
              Text {
                text: (sidetoneSlider.dragging ? sidetoneSlider.liveValue : root.sidetone) === 0
                  ? "OFF" : (sidetoneSlider.dragging ? sidetoneSlider.liveValue : root.sidetone) + " / 10"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
              }
            }

            CursorSurface {
              width: parent.width
              height: sidetoneSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.cursorRow === "sidetone"
              foreground: root.foreground
              outline: true
              HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("sidetone") }
              PanelSlider {
                id: sidetoneSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: 10
                step: 1
                integer: true
                tickCount: 11
                enabled: root.online
                value: root.sidetone
                onReleased: function(v) { root.setSidetone(Math.round(v)) }
              }
            }

            Text {
              width: parent.width
              text: "Sidetone feeds a little of your mic back into the headphones so you can hear yourself while you talk."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              leftPadding: Style.space(4)
            }
          }

          // ---------- Equalizer ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)
            opacity: root.online ? 1 : 0.4

            Item {
              width: parent.width
              implicitHeight: Math.max(eqHeader.implicitHeight, flatButton.implicitHeight)
              PanelSectionHeader {
                id: eqHeader
                text: "EQUALIZER"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Button {
                id: flatButton
                text: "Flat"
                tooltipText: "Set every band back to 0 dB"
                bordered: true
                enabled: root.online
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.space(3)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.flattenEq()
              }
            }

            CursorSurface {
              width: parent.width
              height: Style.space(150)
              hasCursor: root.cursorActive && root.cursorRow === "eq"
              foreground: root.foreground
              HoverHandler { onHoveredChanged: if (hovered) root.hoverRow("eq") }

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(4)

                Repeater {
                  model: 10
                  Item {
                    id: band
                    required property int index
                    readonly property int value: root.bandValue(index)
                    readonly property bool known: root.bandKnown(index)
                    width: (parent.width - parent.spacing * 9) / 10
                    height: parent.height

                    Text {
                      id: gainLabel
                      anchors.top: parent.top
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.gainText(band.value)
                      textFormat: Text.PlainText
                      color: band.known ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: band.value !== 20
                    }

                    Item {
                      id: rail
                      anchors.top: gainLabel.bottom
                      anchors.bottom: freqLabel.top
                      anchors.topMargin: Style.space(4)
                      anchors.bottomMargin: Style.space(4)
                      width: parent.width
                      readonly property real knobSize: Math.max(10, Math.round(Style.spacing.controlHeight * 0.34))
                      readonly property real travel: Math.max(1, height - knobSize)

                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(3, Style.space(3))
                        height: parent.height
                        radius: width / 2
                        color: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "#333"
                      }
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.7
                        height: 1
                        y: parent.height / 2
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                      }
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(3, Style.space(3))
                        radius: width / 2
                        height: Math.abs(band.value - 20) / 40 * parent.height
                        y: band.value >= 20 ? parent.height / 2 - height : parent.height / 2
                        color: band.known ? Color.accent : root.foreground
                        opacity: band.known ? 1 : 0.6
                      }
                      BorderSurface {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: rail.knobSize
                        height: rail.knobSize
                        radius: rail.knobSize / 2
                        color: root.foreground
                        borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
                        y: (40 - band.value) / 40 * rail.travel
                        scale: bandMouse.containsMouse || bandMouse.pressed ? 1.15 : 1
                        Behavior on y { enabled: !bandMouse.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                      }
                      MouseArea {
                        id: bandMouse
                        anchors.fill: parent
                        anchors.leftMargin: -Style.space(2)
                        anchors.rightMargin: -Style.space(2)
                        hoverEnabled: true
                        enabled: root.online
                        cursorShape: Qt.PointingHandCursor
                        function valueAt(y) {
                          return Math.max(0, Math.min(40, Math.round(40 - (y - rail.knobSize / 2) / rail.travel * 40)))
                        }
                        onPressed: function(mouse) { root.previewBand(band.index, valueAt(mouse.y)) }
                        onPositionChanged: function(mouse) { if (pressed) root.previewBand(band.index, valueAt(mouse.y)) }
                        onReleased: function(mouse) { root.setBand(band.index, valueAt(mouse.y)) }
                        onWheel: function(wheel) { root.setBand(band.index, band.value + (wheel.angleDelta.y > 0 ? 1 : -1)) }
                      }
                    }

                    Text {
                      id: freqLabel
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.bandFrequencies[index]
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: "Edits select Custom on the base station and apply when you release a band. Half-decibel steps up to ±10 dB; bands not yet known start at 0 dB."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              leftPadding: Style.space(4)
            }
          }

          Text {
            visible: root.errorText !== "" || (root.connected && root.stateError !== "")
            width: parent.width
            text: root.errorText || root.stateError
            textFormat: Text.PlainText
            color: root.bar ? root.bar.urgent : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "a ANC · t transparency · m mic · + − volume · j k rows · h l adjust · Esc close"
            textFormat: Text.PlainText
            color: Qt.darker(root.foreground, 1.9)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
