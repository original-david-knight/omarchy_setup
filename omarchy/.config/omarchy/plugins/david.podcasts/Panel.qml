import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
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
  property var controlQueue: []
  property int lastPlaybackSource: -1

  property int sourceTab: 0
  property string noiseError: ""
  property var sounds: []
  property var noiseState: ({})
  property var noiseQueue: []
  property string lastNoise: "coast"
  property real spotifyPosition: 0
  property var playlists: []
  property string playlistError: ""
  property string selectedPlaylistUri: ""
  property string pendingPlaylistUri: ""
  property real playlistsUpdatedAt: 0
  readonly property bool playlistsLoading: playlistFetch.running
  readonly property bool playlistStarting: playlistPlay.running
  readonly property string libraryHelper: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/spotify-library"
  readonly property var spotify: {
    var players = Mpris.players.values
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (String(p.desktopEntry).toLowerCase() === "spotify" || String(p.identity).toLowerCase() === "spotify"
          || String(p.dbusName).indexOf("org.mpris.MediaPlayer2.spotify") === 0) return p
    }
    return null
  }
  readonly property bool spotifyPlaying: spotify !== null && spotify.isPlaying
  readonly property bool noisePlaying: sounds.some(function(s) { return soundState(s.id).playing })
  readonly property bool noiseStarting: sounds.some(function(s) { var state = soundState(s.id); return state.loading && state.requested })
  readonly property bool anythingPlaying: playing || switchingEpisode || spotifyPlaying || noisePlaying || noiseStarting
  readonly property color sourceColor: sourceTab === 0 ? "#9bdfb1" : sourceTab === 1 ? "#c8b8ed" : "#9dcfd5"
  readonly property var displayEntry: currentEntry || (entries.length ? entries[0] : null)
  readonly property string nowTitle: spotifyPlaying ? (spotify.trackTitle || "Spotify")
    : playing && currentEntry ? currentEntry.title : noisePlaying ? "Ambient mix" : "Listening"
  readonly property string nowArt: spotifyPlaying ? spotify.trackArtUrl
    : playing && currentEntry ? String(currentEntry.artwork_url || "")
    : noisePlaying ? activeNoiseArt() : ""
  readonly property string noiseHelper: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/mynoise"
  readonly property bool compactBar: (bar && bar.vertical) || (root.QsWindow.window !== null
    && root.QsWindow.window.screen !== null && root.QsWindow.window.screen.width < 1920)

  function soundState(id) {
    return noiseState[id] || { playing: false, loading: false, volume: 0.35, error: "" }
  }
  function activeNoiseArt() {
    for (var i = 0; i < sounds.length; i++)
      if (soundState(sounds[i].id).playing) return sounds[i].artwork
    return ""
  }
  function noiseCommand(args) {
    noiseError = ""
    if (args[0] === "play" || args[0] === "toggle") { lastNoise = args[1]; lastPlaybackSource = 2 }
    noiseQueue = noiseQueue.concat([args])
    pumpNoise()
  }
  function pumpNoise() {
    if (noiseControl.running || !noiseQueue.length) return
    noiseControl.command = [noiseHelper].concat(noiseQueue[0])
    noiseQueue = noiseQueue.slice(1)
    noiseControl.running = true
  }
  function consumeNoise(raw) {
    try { noiseState = JSON.parse(raw).sounds || ({}) }
    catch (error) { noiseError = "The soundscape player could not be read" }
  }
  function openSpotify(background) {
    if (!background) root.close()
    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/spotify-window",
      background ? "start" : "show"])
  }
  function refreshPlaylists(force) {
    if (playlistFetch.running || (!force && Date.now() - playlistsUpdatedAt < 300000)) return
    playlistError = ""
    playlistFetch.running = true
  }
  function playPlaylist(playlist) {
    if (playlistPlay.running) return
    playlistError = ""
    lastPlaybackSource = 0
    pendingPlaylistUri = playlist.uri
    if (playing || switchingEpisode) { runControl(["pause"]); saveProgress(false) }
    playlistPlay.command = [libraryHelper, "play", playlist.uri]
    playlistPlay.running = true
  }
  function toggleSpotify() {
    lastPlaybackSource = 0
    if (!spotify) { openSpotify(true); return }
    if (spotify.canTogglePlaying) {
      if (!spotify.isPlaying && (playing || switchingEpisode)) { runControl(["pause"]); saveProgress(false) }
      spotify.togglePlaying()
    }
  }
  function toggleSelected() {
    if (sourceTab === 0) toggleSpotify()
    else if (sourceTab === 1) togglePlayback()
    else if (noisePlaying || noiseStarting) noiseCommand(["pause-all"])
    else noiseCommand(["toggle", lastNoise])
  }
  function toggleActive() {
    if (spotifyPlaying) toggleSpotify()
    else if (playing) togglePlayback()
    else if (noisePlaying || noiseStarting) { lastPlaybackSource = 2; noiseCommand(["pause-all"]) }
    else if (lastPlaybackSource === 0) toggleSpotify()
    else if (lastPlaybackSource === 1) togglePlayback()
    else if (lastPlaybackSource === 2) noiseCommand(["toggle", lastNoise])
    else toggleSelected()
  }
  function pauseAll() {
    if (spotify && spotify.canPause) spotify.pause()
    if (playing || switchingEpisode) { runControl(["pause"]); saveProgress(false) }
    noiseCommand(["pause-all"])
  }

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
    if (controlProcess.running) {
      if (args[0] !== "pause") return false
      controlQueue = [["pause"]]
      return true
    }
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
    if (controlProcess.running) return
    if (index < 0 || index >= entries.length) return
    lastPlaybackSource = 1
    var entry = entries[index]
    if (!entry.enclosure_url) {
      errorText = "This episode has no playable audio URL"
      return
    }
    if (currentIndex === index && !idle) {
      if (!playing && spotify && spotify.canPause) spotify.pause()
      runControl(["toggle"])
      return
    }
    if (spotify && spotify.canPause) spotify.pause()
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
    lastPlaybackSource = 1
    if (!playing && spotify && spotify.canPause) spotify.pause()
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
    if (sourceTab === 0) refreshPlaylists(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSourceTabChanged: if (opened && sourceTab === 0) refreshPlaylists(false)

  Process {
    id: playlistFetch
    command: [root.libraryHelper, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!text.trim()) return
        try {
          root.playlists = JSON.parse(text).playlists || []
          root.playlistsUpdatedAt = Date.now()
        } catch (error) { root.playlistError = "Your playlists could not be read" }
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.playlistError = text.trim() }
    onExited: function(code) {
      if (code !== 0 && !root.playlistError) root.playlistError = "Your playlist library is unavailable. Try refreshing."
    }
  }
  Process {
    id: playlistPlay
    stdout: StdioCollector {
      onStreamFinished: {
        if (!text.trim()) return
        try { root.selectedPlaylistUri = JSON.parse(text).uri || "" }
        catch (error) { root.playlistError = "Spotify did not confirm the playlist selection" }
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.playlistError = text.trim() }
    onExited: function(code) {
      root.pendingPlaylistUri = ""
      if (code !== 0 && !root.playlistError) root.playlistError = "Spotify could not start this playlist. Try again."
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/david.podcasts/soundscapes.json"
    onLoaded: {
      try { root.sounds = JSON.parse(text()) }
      catch (error) { root.noiseError = "Soundscape list could not be read" }
    }
  }
  IpcHandler {
    target: "david.listening"
    function show(source: string): void {
      var index = ["spotify", "podcasts", "mynoise"].indexOf(source)
      if (index >= 0) root.sourceTab = index
      root.open()
    }
    function playPause(): void { root.toggleActive() }
    function pauseAll(): void { root.pauseAll() }
    function status(): string {
      return JSON.stringify({source: ["spotify", "podcasts", "mynoise"][root.sourceTab],
        spotify: root.spotify ? {title: root.spotify.trackTitle, artist: root.spotify.trackArtist,
          artwork: root.spotify.trackArtUrl, playing: root.spotifyPlaying} : null,
        playlists: {count: root.playlists.length, selected: root.selectedPlaylistUri, error: root.playlistError},
        podcasts: {count: root.entries.length, playing: root.playing}, sounds: root.noiseState})
    }
  }
  Process {
    id: noiseControl
    stdout: StdioCollector { onStreamFinished: root.consumeNoise(text) }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.noiseError = text.trim() }
    onExited: Qt.callLater(function() { root.pumpNoise() })
  }
  Process {
    id: noiseStatus
    command: [root.noiseHelper, "status"]
    stdout: StdioCollector { onStreamFinished: root.consumeNoise(text) }
  }
  Timer {
    interval: root.opened ? 1000 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!noiseStatus.running && !noiseControl.running) noiseStatus.running = true
      if (root.spotify && root.opened) root.spotifyPosition = root.spotify.position
    }
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
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.switchingEpisode = false
        root.paused = true
        root.idle = true
      }
      Qt.callLater(function() {
        if (!root.controlQueue.length) return
        var args = root.controlQueue[0]
        root.controlQueue = root.controlQueue.slice(1)
        root.runControl(args)
      })
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
    text: "♫"
    labelVisible: false
    fixedWidth: root.compactBar ? Style.space(34) : Style.space(root.anythingPlaying ? 158 : 115)
    tooltipText: root.nowTitle + "\nSpotify · Podcasts · myNoise\nMiddle-click: play/pause · Right-click: pause all"
    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.toggleActive()
      else if (code === Qt.RightButton) root.pauseAll()
      else root.toggle()
    }
    Row {
      anchors.centerIn: parent
      spacing: Style.space(7)
      Artwork {
        width: Style.space(21); height: width; radius: Style.space(5)
        source: root.nowArt
        tint: root.anythingPlaying ? "#9bdfb1" : root.foreground
      }
      Text {
        visible: !root.compactBar
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(root.anythingPlaying ? 107 : 65)
        text: root.nowTitle
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Rectangle {
        visible: root.anythingPlaying && !root.compactBar
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(4); height: width; radius: width / 2
        color: "#9bdfb1"
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
    contentHeight: panel.fittedContentHeight(listening.implicitHeight, Style.space(root.sourceTab === 0 ? 840 : 740))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.sourceTab = (root.sourceTab + direction + 3) % 3 }
      onActivateRequested: root.toggleSelected()
      onMoveRequested: function(dx, dy) {
        if (dx) root.sourceTab = (root.sourceTab + dx + 3) % 3
        else listening.scrollBy(dy * Style.space(68))
      }
      onTextKey: function(text) {
        if (text === "r" || text === "R") {
          if (root.sourceTab === 0) root.refreshPlaylists(true)
          else root.refresh()
        }
        else if (text === "e" || text === "E") root.openEverything("/podcasts/queue")
        else if (text === "1" || text === "2" || text === "3") root.sourceTab = Number(text) - 1
      }
      ListeningView {
        id: listening
        anchors.fill: parent
        controller: root
      }
    }
  }
}
