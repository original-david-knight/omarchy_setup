import QtQuick
import Quickshell
import qs.Media

Item {
  id: test
  property var livePlayers: []
  property var calls: []
  property var music: null
  property var video: null
  property var podcast: null
  property var proxy: null
  property int step: 0

  Service { id: media; players: test.livePlayers }

  Component {
    id: playerComponent
    QtObject {
      property string dbusName: ""
      property string desktopEntry: ""
      property string identity: desktopEntry
      property string trackTitle: "Track"
      property string trackArtist: "Artist"
      property string trackAlbum: ""
      property string trackArtUrl: ""
      property bool isPlaying: false
      property bool canPlay: true
      property bool canPause: true
      property bool canTogglePlaying: true
      property bool canGoNext: true
      property bool canGoPrevious: true
      function record(action) { test.calls.push(desktopEntry + ":" + action) }
      function play() { record("play"); isPlaying = true }
      function pause() { record("pause"); isPlaying = false }
      function togglePlaying() { record("toggle"); isPlaying = !isPlaying }
      function next() { record("next") }
      function previous() { record("previous") }
    }
  }

  function expect(condition, message) {
    if (!condition) throw new Error(message)
  }
  function owner(player) {
    expect(media.activePlayer === player, "Wrong media-key owner at step " + step)
  }
  function action(name, expected) {
    calls = []
    var handled = media.runAction(name, false)
    expect(handled === (expected !== ""), "Unexpected handled result: " + name)
    expect(JSON.stringify(calls) === JSON.stringify(expected ? [expected] : []),
      "Unexpected calls: " + JSON.stringify(calls))
  }
  function makePlayer(name) {
    return playerComponent.createObject(test, {
      dbusName: "org.mpris.MediaPlayer2." + name, desktopEntry: name
    })
  }

  Component.onCompleted: {
    music = makePlayer("spotify")
    video = makePlayer("chromium")
    podcast = makePlayer("mpv")
    proxy = makePlayer("playerctld")
    livePlayers = [music, video, podcast, proxy]
  }

  // Yield between events to exercise actual QML bindings and Connections.
  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      try {
        switch (test.step++) {
        case 0:
          owner(null)
          action("playPause", "") // Loaded paused players must not autoplay.
          music.isPlaying = true
          break
        case 1:
          owner(music)
          video.isPlaying = true // YouTube starts while music is still playing.
          break
        case 2:
          owner(video)
          action("playPause", "chromium:pause")
          break
        case 3:
          owner(video) // Spotify is still playing, but YouTube keeps ownership.
          action("playPause", "chromium:play")
          break
        case 4:
          video.isPlaying = false // Pause with the website's own button.
          music.isPlaying = false
          break
        case 5:
          owner(video)
          action("playPause", "chromium:play")
          break
        case 6:
          video.canGoNext = false
          video.canGoPrevious = false
          action("next", "")
          action("previous", "")
          music.trackTitle = "A metadata refresh"
          proxy.isPlaying = true
          livePlayers = [podcast, proxy, video, music]
          break
        case 7:
          owner(video) // Metadata, proxies and discovery order cannot steal keys.
          podcast.isPlaying = true
          break
        case 8:
          owner(podcast)
          action("next", "mpv:next")
          action("previous", "mpv:previous")
          action("playPause", "mpv:pause")
          break
        case 9:
          owner(podcast)
          action("playPause", "mpv:play")
          break
        case 10:
          music.isPlaying = true // Resuming an older player takes over.
          break
        case 11:
          owner(music)
          video.isPlaying = false
          break
        case 12:
          video.isPlaying = true
          break
        case 13:
          owner(video)
          livePlayers = [music, podcast, proxy] // Close YouTube while others play.
          break
        case 14:
          owner(null)
          action("playPause", "")
          action("next", "")
          music.isPlaying = false
          break
        case 15:
          music.isPlaying = true
          break
        case 16:
          owner(music)
          expect(media.selectPlayer(podcast.dbusName), "Explicit selection failed")
          break
        case 17:
          owner(podcast)
          expect(!media.runAction("playPause", false, "missing-player"), "Missing target fell back")
          console.log("MEDIA KEY TEST PASSED")
          Qt.quit()
        }
      } catch (error) {
        console.error("MEDIA KEY TEST FAILED: " + error)
        Qt.quit()
      }
    }
  }
}
