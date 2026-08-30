import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "david.podcasts"
  ipcTarget: "david.podcasts"

  property var queueData: ({ entries: [] })
  property string errorText: ""
  property string fetchStderr: ""
  property bool loading: false
  property int currentIndex: -1
  property real position: 0
  property real duration: 0
  property real speed: 1
  property bool paused: true
  property bool idle: true
  property bool playerAvailable: false
  property bool hadActivePlayback: false
  property bool completing: false
  property bool scrubbing: false
  property bool switchingEpisode: false
  property real expectedPosition: 0
  property var localProgress: ({})
  property var saveQueue: []

  readonly property var entries: queueData && Array.isArray(queueData.entries) ? queueData.entries : []
  readonly property var currentEntry: currentIndex >= 0 && currentIndex < entries.length ? entries[currentIndex] : null
  readonly property bool playing: playerAvailable && !idle && !paused && !switchingEpisode
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helper: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/player"

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
      var activeId = currentEntry ? String(currentEntry.episode_id) : ""
      var nextQueue = JSON.parse(String(raw || ""))
      var nextEntries = nextQueue && Array.isArray(nextQueue.entries) ? nextQueue.entries : []
      var nextProgress = ({})
      for (var i = 0; i < nextEntries.length; i++) {
        var entry = nextEntries[i]
        var key = episodeKey(entry)
        if (!key) continue
        if (key === activeId && Object.prototype.hasOwnProperty.call(localProgress, key))
          nextProgress[key] = localProgress[key]
        else
          nextProgress[key] = Math.max(0, Number(entry.position_seconds || 0))
      }
      localProgress = nextProgress
      queueData = nextQueue
      if (activeId) currentIndex = findEpisode(activeId)
    } catch (error) {
      errorText = "Podcast queue could not be read"
    }
    loading = false
  }

  function findEpisode(episodeId) {
    for (var i = 0; i < entries.length; i++) {
      if (String(entries[i].episode_id) === String(episodeId)) return i
    }
    return -1
  }

  function runControl(args) {
    if (controlProcess.running) return false
    controlProcess.command = [helper].concat(args)
    controlProcess.running = true
    return true
  }

  function episodeKey(entry) {
    return entry ? String(entry.episode_id || "") : ""
  }

  function rememberProgress(entry, seconds) {
    var key = episodeKey(entry)
    if (key) localProgress[key] = Math.max(0, Number(seconds || 0))
  }

  function savedPositionFor(entry) {
    var key = episodeKey(entry)
    if (key && Object.prototype.hasOwnProperty.call(localProgress, key))
      return Math.max(0, Number(localProgress[key] || 0))
    return Math.max(0, Number(entry.position_seconds || 0))
  }

  function queueProgressSave(entry, savedPosition, savedDuration, completed) {
    if (!entry) return
    var at = completed && savedDuration > 0 ? savedDuration : savedPosition
    at = Math.max(0, Number(at || 0))
    savedDuration = Math.max(0, Number(savedDuration || 0))
    rememberProgress(entry, at)
    saveQueue = saveQueue.concat([[
      helper, "save", episodeKey(entry), String(at), String(savedDuration),
      completed ? "true" : "false"
    ]])
    pumpSaveQueue()
  }

  function pumpSaveQueue() {
    if (saveProcess.running || saveQueue.length === 0) return
    var nextSave = saveQueue[0]
    saveQueue = saveQueue.slice(1)
    saveProcess.command = nextSave
    saveProcess.running = true
  }

  function playEpisode(index, skipOutgoingSave) {
    if (index < 0 || index >= entries.length) return
    var entry = entries[index]
    if (!entry.enclosure_url) {
      errorText = "This episode has no playable audio URL"
      return
    }
    if (currentIndex === index && !idle) {
      runControl(["toggle"])
      return
    }
    var savedPosition = savedPositionFor(entry)
    var savedDuration = Number(entry.duration_seconds || 0)
    // Replaying an item that was previously completed should start from the
    // beginning instead of loading at EOF and immediately advancing again.
    if (entry.completed && savedDuration > 0 && savedPosition >= savedDuration - 1)
      savedPosition = 0
    currentIndex = index
    position = savedPosition
    expectedPosition = savedPosition
    duration = savedDuration
    rememberProgress(entry, savedPosition)
    switchingEpisode = true
    paused = false
    idle = false
    // mpv can remain idle briefly while it opens a remote enclosure. Only a
    // later non-idle status proves playback started; otherwise the status poll
    // mistakes that startup window for EOF and completes the episode.
    hadActivePlayback = false
    completing = false
    if (!runControl([
      skipOutgoingSave ? "load" : "switch",
      String(entry.episode_id),
      String(entry.enclosure_url),
      String(position),
      String(duration),
      String(entry.title || "Untitled episode"),
      String(entry.show_title || "Podcast")
    ])) switchingEpisode = false
  }

  function saveProgress(completed) {
    if (!currentEntry) return
    queueProgressSave(currentEntry, position, duration, completed)
  }

  function previewSeek(mouseX, trackWidth) {
    if (!currentEntry || duration <= 0 || trackWidth <= 0) return
    position = duration * Math.max(0, Math.min(1, mouseX / trackWidth))
  }

  function commitSeek() {
    if (!currentEntry || duration <= 0) return
    position = Math.max(0, Math.min(duration, position))
    if (!idle && !seekProcess.running) {
      seekProcess.command = [helper, "seek-to", String(position)]
      seekProcess.running = true
    }
    // Persist even while idle so selecting a position also repairs progress
    // that was incorrectly marked complete by an earlier playback failure.
    saveProgress(false)
  }

  function nextEpisode(completed) {
    if (currentIndex < 0) return
    saveProgress(completed)
    if (currentIndex + 1 < entries.length) {
      playEpisode(currentIndex + 1, true)
    } else {
      runControl(["stop"])
      switchingEpisode = false
      paused = true
      idle = true
      hadActivePlayback = false
    }
  }

  function togglePlayback() {
    if (!currentEntry) {
      if (entries.length) playEpisode(0)
      return
    }
    if (idle) playEpisode(currentIndex)
    else runControl(["toggle"])
  }

  function consumeStatus(raw) {
    try {
      var status = JSON.parse(String(raw || ""))
      var nextIdle = Boolean(status.idle)
      playerAvailable = Boolean(status.available)
      var statusEpisodeId = String(status.episode_id || "")

      if (currentIndex < 0 && statusEpisodeId)
        currentIndex = findEpisode(statusEpisodeId)

      // A poll started before an episode switch can finish after currentIndex
      // changes. Never apply that outgoing episode's state to the new entry.
      if (currentEntry && statusEpisodeId && episodeKey(currentEntry) !== statusEpisodeId) {
        // The instance that initiated a switch ignores its in-flight old poll;
        // peer monitor instances follow the shared player to the new episode.
        if (controlProcess.running) return
        var statusIndex = findEpisode(statusEpisodeId)
        if (statusIndex >= 0) currentIndex = statusIndex
      }

      var reportedPosition = Math.max(0, Number(status.position || 0))
      var reportedDuration = Math.max(0, Number(status.duration || (currentEntry ? currentEntry.duration_seconds : 0) || 0))

      if (switchingEpisode && currentEntry && statusEpisodeId
          && episodeKey(currentEntry) === statusEpisodeId) {
        expectedPosition = Math.max(0, Number(status.start_position === undefined
          ? savedPositionFor(currentEntry)
          : status.start_position))
        position = expectedPosition
        duration = reportedDuration
        speed = Number(status.speed || 1)
        paused = Boolean(status.paused)
        rememberProgress(currentEntry, expectedPosition)

        var sourceMatches = !status.source_url || String(status.path || "") === String(status.source_url)
        var reachedExpected = expectedPosition <= 1 || reportedPosition >= expectedPosition - 2
        if (!sourceMatches || nextIdle || !reachedExpected) return
        switchingEpisode = false
      }

      if (!scrubbing && (!nextIdle || reportedPosition > 0)) position = reportedPosition
      duration = reportedDuration
      speed = Number(status.speed || 1)
      paused = Boolean(status.paused)

      if (currentEntry && !scrubbing) rememberProgress(currentEntry, position)

      if (!nextIdle) hadActivePlayback = true
      if (nextIdle && !idle && hadActivePlayback && currentIndex >= 0 && !completing) {
        completing = true
        idle = true
        paused = true
        // idle-active also becomes true after stop, load failure, and some
        // media-source operations. Only advance when playback was actually
        // close enough to the end to count as completed.
        var reachedEnd = duration > 0 && position >= Math.max(0, duration - 30)
        if (reachedEnd) {
          nextEpisode(true)
        } else {
          saveProgress(false)
          hadActivePlayback = false
          completing = false
        }
        return
      }
      idle = nextIdle
      if (!idle) completing = false
    } catch (error) {
      playerAvailable = false
    }
  }

  function cycleSpeed() {
    var speeds = [0.75, 1, 1.25, 1.5, 1.75, 2]
    var at = speeds.indexOf(speed)
    var next = speeds[(at + 1) % speeds.length]
    speed = next
    runControl(["speed", String(next)])
  }

  function clock(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds || 0)))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    if (hours > 0)
      return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(secs).padStart(2, "0")
    return minutes + ":" + String(secs).padStart(2, "0")
  }

  function openEverything(path) {
    if (root.bar) root.bar.run("~/.local/bin/everything-agent open " + path)
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: fetchProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/fetch"]
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
      if (exitCode !== 0) root.errorText = root.fetchStderr || "Podcast queue is unavailable"
    }
  }

  Process {
    id: controlProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim()) root.errorText = String(text).trim()
    }
  }

  Process {
    id: saveProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim()) root.errorText = String(text).trim()
    }
    onExited: Qt.callLater(function() { root.pumpSaveQueue() })
  }

  Process {
    id: seekProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim()) root.errorText = String(text).trim()
    }
  }

  Process {
    id: statusProcess
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.consumeStatus(text)
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statusProcess.running) statusProcess.running = true
  }

  Timer {
    interval: 15000
    running: root.playing
    repeat: true
    onTriggered: root.saveProgress(false)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playing ? "▶" : "🎧"
    tooltipText: "Podcasts · " + root.entries.length + " queued" +
      (root.currentEntry ? "\n" + (root.playing ? "Playing: " : "Paused: ") + root.currentEntry.title : "")
    active: root.errorText !== ""
    fontSize: Style.font.bodySmall
    horizontalMargin: 7

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton)
        root.openEverything("/podcasts/queue")
      else if (buttonCode === Qt.MiddleButton && root.currentEntry)
        root.togglePlayback()
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
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        root.togglePlayback()
      }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          scroll.contentY = Math.max(0, Math.min(scroll.contentY + dy * Style.space(56),
                                                Math.max(0, scroll.contentHeight - scroll.height)))
      }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "e" || text === "E") root.openEverything("/podcasts/queue")
        else if (text === " ") {
          root.togglePlayback()
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
              text: "Podcast queue"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Row {
              width: parent.width - x
              anchors.baseline: title.baseline
              layoutDirection: Qt.RightToLeft
              spacing: Style.space(14)
              Text {
                text: "Manage shows ↗"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEverything("/podcasts/subscriptions")
                }
              }
              Text {
                text: "Edit queue ↗"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEverything("/podcasts/queue")
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

          Rectangle {
            visible: root.currentEntry !== null
            width: parent.width
            implicitHeight: playerColumn.implicitHeight + Style.space(22)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Color.accent)
            border.width: 1
            border.color: Color.popups.border

            Column {
              id: playerColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: root.currentEntry ? root.currentEntry.title : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.currentEntry ? root.currentEntry.show_title : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Item {
                id: seekTrack
                width: parent.width
                height: Style.space(14)

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(4)
                  radius: height / 2
                  color: Style.normalBorderFor(root.foreground, Color.accent)

                  Rectangle {
                    height: parent.height
                    radius: height / 2
                    color: Color.accent
                    width: parent.width * Math.min(1, root.duration > 0 ? root.position / root.duration : 0)
                  }
                }

                Rectangle {
                  width: Style.space(10)
                  height: width
                  radius: width / 2
                  color: Color.accent
                  x: Math.max(0, Math.min(parent.width - width,
                    parent.width * Math.min(1, root.duration > 0 ? root.position / root.duration : 0) - width / 2))
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: !root.switchingEpisode
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPressed: function(mouse) {
                    root.scrubbing = true
                    root.previewSeek(mouse.x, width)
                  }
                  onPositionChanged: function(mouse) {
                    if (pressed) root.previewSeek(mouse.x, width)
                  }
                  onReleased: function(mouse) {
                    root.previewSeek(mouse.x, width)
                    root.scrubbing = false
                    root.commitSeek()
                  }
                  onCanceled: root.scrubbing = false
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Repeater {
                  model: [
                    { label: "−15", action: "back" },
                    { label: root.playing ? "Pause" : "Play", action: "toggle" },
                    { label: "+15", action: "forward" },
                    { label: root.speed + "×", action: "speed" },
                    { label: "Next", action: "next" }
                  ]
                  Rectangle {
                    required property var modelData
                    implicitWidth: controlLabel.implicitWidth + Style.space(18)
                    implicitHeight: controlLabel.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: controlMouse.containsMouse
                      ? Style.hoverFillFor(root.foreground, Color.accent)
                      : Style.normalFillFor(root.foreground, Color.accent)
                    Text {
                      id: controlLabel
                      anchors.centerIn: parent
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: controlMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (modelData.action === "back") root.runControl(["seek", "-15"])
                        else if (modelData.action === "toggle") root.togglePlayback()
                        else if (modelData.action === "forward") root.runControl(["seek", "15"])
                        else if (modelData.action === "speed") root.cycleSpeed()
                        else if (modelData.action === "next") root.nextEpisode(false)
                      }
                    }
                  }
                }

                Text {
                  width: parent.width - x
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.clock(root.position) + " / " + root.clock(root.duration)
                    + (root.switchingEpisode ? "  ·  Loading…" : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            visible: root.entries.length === 0 && !root.loading
            text: "The podcast queue is empty."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.entries
            Item {
              required property var modelData
              required property int index
              width: contentColumn.width
              implicitHeight: episodeCopy.implicitHeight + Style.space(12)
              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: index === root.currentIndex
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : (episodeMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
              }
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                text: index === root.currentIndex && root.playing ? "▶" : String(index + 1)
                color: index === root.currentIndex ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
              }
              Column {
                id: episodeCopy
                anchors.left: parent.left
                anchors.leftMargin: Style.space(38)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modelData.show_title + "  ·  " + root.clock(modelData.duration_seconds)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: episodeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.playEpisode(index)
              }
            }
          }

          Text {
            width: parent.width
            text: "Click an episode to play  ·  Drag progress to seek  ·  Space play/pause  ·  E edit queue  ·  Esc close"
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
