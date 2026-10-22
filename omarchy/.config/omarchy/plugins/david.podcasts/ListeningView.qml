import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: view
  required property var controller
  readonly property var c: controller
  readonly property color ink: Color.foreground
  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.58)
  readonly property color tint: c.sourceColor
  readonly property color eqTint: "#e6c384"
  readonly property var bandLabels: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
  readonly property bool music: c.sourceTab === 0
  readonly property bool podcasts: c.sourceTab === 1
  readonly property bool isPlaying: music ? c.spotifyPlaying : c.playing
  readonly property var episode: c.displayEntry
  readonly property real trackDuration: music ? (c.spotify && c.spotify.lengthSupported ? c.spotify.length : 0) : c.duration
  readonly property real trackPosition: music ? c.spotifyPosition : c.position
  readonly property string trackTitle: music ? (c.spotify && c.spotify.trackTitle ? c.spotify.trackTitle : "A little music, a better day.")
    : episode ? episode.title : "Your next good listen."
  readonly property string trackArtist: music ? (c.spotify ? c.spotify.trackArtist || "Choose something in Spotify" : "Start Spotify in the background")
    : episode ? episode.show_title : "Add a show or episode to your queue"
  implicitHeight: column.implicitHeight

  function scrollBy(amount) {
    scroll.contentY = Math.max(0, Math.min(scroll.contentY + amount, scroll.contentHeight - scroll.height))
  }
  onMusicChanged: scroll.contentY = 0
  onPodcastsChanged: scroll.contentY = 0

  function gainText(db) {
    return db === 0 ? "0" : (db > 0 ? "+" : "−") + Math.abs(db)
  }

  component Copy: Text {
    color: view.ink
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      width: scroll.width
      spacing: Style.space(16)

      Row {
        width: parent.width
        spacing: Style.space(6)
        Column {
          width: parent.width - eqToggle.width - pauseAll.width - parent.spacing * 2
          spacing: Style.space(3)
          Copy { text: "Listening"; font.pixelSize: Style.font.title * 1.15; font.bold: true }
          Copy { text: "Your own little listening room"; color: view.muted; font.pixelSize: Style.font.caption }
        }
        ListeningButton {
          id: eqToggle
          anchors.verticalCenter: parent.verticalCenter
          text: c.eqOpen ? "EQ  ▴" : "EQ  ▾"
          tooltip: c.eqShaping ? "Equalizer is shaping Spotify, podcasts and myNoise" : "Equalizer for Spotify, podcasts and myNoise"
          tint: view.eqTint
          prominent: c.eqShaping
          onClicked: c.eqOpen = !c.eqOpen
        }
        ListeningButton {
          id: pauseAll
          anchors.verticalCenter: parent.verticalCenter
          text: "Ⅱ  All"
          tooltip: "Pause every listening source"
          tint: view.ink
          enabled: c.anythingPlaying
          onClicked: c.pauseAll()
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(44)
        radius: Style.space(12)
        color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.04)
        Row {
          id: sourceTabs
          anchors.fill: parent
          anchors.margins: Style.space(4)
          spacing: Style.space(4)
          Repeater {
            model: ["Spotify", "Podcasts", "myNoise"]
            AbstractButton {
              id: tab
              required property string modelData
              required property int index
              width: (sourceTabs.width - sourceTabs.spacing * 2) / 3
              height: sourceTabs.height
              hoverEnabled: true
              Accessible.name: modelData
              onClicked: c.sourceTab = index
              background: Rectangle {
                radius: Style.space(9)
                color: c.sourceTab === tab.index ? Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.16)
                  : tab.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                border.width: c.sourceTab === tab.index ? 1 : 0
                border.color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.25)
              }
              contentItem: Row {
                spacing: Style.space(6)
                leftPadding: (tab.width - tabText.implicitWidth - (activity.visible ? Style.space(11) : 0)) / 2
                Copy {
                  id: tabText
                  anchors.verticalCenter: parent.verticalCenter
                  text: tab.modelData
                  color: c.sourceTab === tab.index ? view.tint : view.muted
                  font.bold: c.sourceTab === tab.index
                }
                Rectangle {
                  id: activity
                  anchors.verticalCenter: parent.verticalCenter
                  visible: tab.index === 0 ? c.spotifyPlaying : tab.index === 1 ? c.playing : c.noisePlaying
                  width: Style.space(5); height: width; radius: width / 2
                  color: "#9bdfb1"
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: c.eqOpen
        width: parent.width
        height: eqContent.implicitHeight + Style.space(24)
        radius: Style.space(14)
        color: Qt.rgba(view.eqTint.r, view.eqTint.g, view.eqTint.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(view.eqTint.r, view.eqTint.g, view.eqTint.b, 0.18)

        Column {
          id: eqContent
          anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
          anchors.margins: Style.space(12)
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(6)
            Column {
              width: parent.width - eqPower.width - eqFlat.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Copy { text: "EQUALIZER"; color: view.eqTint; font.pixelSize: Style.font.caption * 0.85; font.letterSpacing: 1.1; font.bold: true }
              Copy { width: parent.width; text: "Spotify, podcasts and myNoise only"; color: view.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            ListeningButton {
              id: eqPower
              anchors.verticalCenter: parent.verticalCenter
              text: c.eq.enabled ? "On" : "Off"
              tooltip: c.eq.enabled ? "Turn the equalizer off · Your curve is kept" : "Turn the equalizer on"
              tint: view.eqTint
              prominent: c.eq.enabled
              enabled: c.eq.available
              Accessible.checkable: true
              Accessible.checked: c.eq.enabled
              onClicked: c.eqCommand(["enable", c.eq.enabled ? "off" : "on"])
            }
            ListeningButton {
              id: eqFlat
              anchors.verticalCenter: parent.verticalCenter
              text: "Flat"
              tooltip: "Set every band back to 0 dB"
              tint: view.eqTint
              enabled: c.eq.available
              onClicked: c.eqCommand(["preset", "flat"])
            }
          }

          Row {
            id: presetRow
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: [["bass", "Bass"], ["warm", "Warm"], ["voice", "Voice"], ["bright", "Bright"]]
              ListeningButton {
                required property var modelData
                width: (presetRow.width - presetRow.spacing * 3) / 4
                text: modelData[1]
                tooltip: modelData[0] === "voice" ? "Clearer speech for podcasts" : modelData[1] + " preset"
                tint: view.eqTint
                prominent: c.eq.enabled && c.eq.preset === modelData[0]
                enabled: c.eq.available
                onClicked: c.eqCommand(["preset", modelData[0]])
              }
            }
          }

          Row {
            width: parent.width
            height: Style.space(150)
            spacing: Style.space(4)
            opacity: !c.eq.available ? 0.35 : c.eq.enabled ? 1 : 0.55

            Repeater {
              model: 10
              Item {
                id: band
                required property int index
                readonly property real db: c.eqBand(index)
                width: (parent.width - parent.spacing * 9) / 10
                height: parent.height

                Copy {
                  id: gainLabel
                  anchors.top: parent.top
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: view.gainText(band.db)
                  color: band.db === 0 ? view.muted : view.ink
                  font.pixelSize: Style.font.caption
                  font.bold: band.db !== 0
                }

                Item {
                  id: rail
                  anchors.top: gainLabel.bottom
                  anchors.bottom: freqLabel.top
                  anchors.topMargin: Style.space(4)
                  anchors.bottomMargin: Style.space(4)
                  width: parent.width
                  readonly property real knobSize: Style.space(12)
                  readonly property real travel: Math.max(1, height - knobSize)

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(3); height: parent.height; radius: width / 2
                    color: Qt.rgba(view.eqTint.r, view.eqTint.g, view.eqTint.b, 0.14)
                  }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.7; height: 1
                    y: parent.height / 2
                    color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.25)
                  }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(3); radius: width / 2
                    height: Math.abs(band.db) / 24 * parent.height
                    y: band.db >= 0 ? parent.height / 2 - height : parent.height / 2
                    color: view.eqTint
                  }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: rail.knobSize; height: width; radius: width / 2
                    y: (12 - band.db) / 24 * rail.travel
                    color: view.eqTint
                    border.width: Math.max(1, Style.space(2))
                    border.color: Color.background
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
                    enabled: c.eq.available
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    function dbAt(y) {
                      return Math.max(-12, Math.min(12, Math.round((12 - (y - rail.knobSize / 2) / rail.travel * 24) * 2) / 2))
                    }
                    onPressed: function(mouse) { c.previewEqBand(band.index, dbAt(mouse.y)) }
                    onPositionChanged: function(mouse) { if (pressed) c.previewEqBand(band.index, dbAt(mouse.y)) }
                    onReleased: c.setEqBand(band.index, band.db)
                    onDoubleClicked: c.previewEqBand(band.index, 0)
                    onWheel: function(wheel) { c.setEqBand(band.index, band.db + (wheel.angleDelta.y > 0 ? 0.5 : -0.5)) }
                  }
                }

                Copy {
                  id: freqLabel
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: view.bandLabels[band.index]
                  color: view.muted
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Copy {
            width: parent.width
            text: !c.eq.available ? "The Listening EQ sink is not running. Run ./stow_all.sh, or: systemctl --user start filter-chain.service"
              : !c.eq.enabled ? "The equalizer is off. Your curve is kept for when you turn it back on."
              : c.eq.preamp < 0 ? "Drag, scroll or double-click a band. Output is lowered " + Math.abs(c.eq.preamp) + " dB to leave room for boosts."
              : "Drag, scroll or double-click a band. Changes apply as you release."
            color: view.muted
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Copy { visible: c.eqError !== ""; width: parent.width; text: c.eqError; color: Color.urgent; wrapMode: Text.WordWrap; font.pixelSize: Style.font.caption }
        }
      }

      Rectangle {
        visible: c.sourceTab !== 2
        width: parent.width
        height: heroColumn.implicitHeight + Style.space(32)
        radius: Style.space(16)
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.12) }
          GradientStop { position: 1; color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.025) }
        }
        border.width: 1
        border.color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.16)

        Column {
          id: heroColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          spacing: Style.space(14)

          Row {
            width: parent.width
            spacing: Style.space(17)
            Artwork {
              id: heroArt
              width: Style.space(122)
              height: width
              source: view.music ? (c.spotify ? c.spotify.trackArtUrl : "") : (view.episode ? view.episode.artwork_url || "" : "")
              glyph: view.music ? "♫" : "♬"
              tint: view.tint
              radius: Style.space(12)
            }
            Column {
              width: parent.width - heroArt.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(7)
              Copy {
                text: view.isPlaying ? "NOW PLAYING" : (view.music && !c.spotify ? "MAKE YOURSELF AT HOME" : "READY WHEN YOU ARE")
                color: view.tint
                font.pixelSize: Style.font.caption * 0.85
                font.letterSpacing: 1.1
                font.bold: true
              }
              Copy {
                width: parent.width
                text: view.trackTitle
                font.pixelSize: Style.font.body * 1.12
                font.bold: true
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
              Copy {
                width: parent.width
                text: view.trackArtist
                color: view.muted
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Style.font.caption
              }
            }
          }

          Column {
            visible: view.trackDuration > 0 && (view.music ? c.spotify !== null : c.currentEntry !== null)
            width: parent.width
            spacing: Style.space(1)
            PanelSlider {
              width: parent.width
              bar: c.bar
              minimum: 0
              maximum: Math.max(1, view.trackDuration)
              value: view.trackPosition
              step: 1
              enabled: view.music ? (c.spotify !== null && c.spotify.canSeek && c.spotify.positionSupported) : !c.switchingEpisode
              trackColor: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.13)
              fillColor: view.tint
              knobColor: view.tint
              onDraggingChanged: if (view.podcasts) c.scrubbing = dragging
              onMoved: function(value) { if (view.podcasts) c.position = value }
              onReleased: function(value) {
                if (view.music && c.spotify) { c.spotify.position = value; c.spotifyPosition = value }
                else { c.position = value; c.scrubbing = false; c.commitSeek() }
              }
            }
            Row {
              width: parent.width
              Copy { width: parent.width / 2; text: c.clock(view.trackPosition); color: view.muted; font.pixelSize: Style.font.caption }
              Copy { width: parent.width / 2; text: c.switchingEpisode && view.podcasts ? "Loading…" : "−" + c.clock(view.trackDuration - view.trackPosition); color: view.muted; horizontalAlignment: Text.AlignRight; font.pixelSize: Style.font.caption }
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(12)
            ListeningButton {
              text: view.music ? "󰒮" : "−15"
              tint: view.tint
              tooltip: view.music ? "Previous track" : "Back 15 seconds"
              enabled: view.music ? (c.spotify !== null && c.spotify.canGoPrevious) : c.currentEntry !== null && !c.idle && !c.switchingEpisode
              onClicked: view.music ? c.spotify.previous() : c.runControl(["seek", "-15"])
            }
            ListeningButton {
              text: view.music && !c.spotify ? "Start Spotify" : view.isPlaying ? "Ⅱ  Pause" : "▶  Play"
              tint: view.tint
              prominent: true
              implicitWidth: Style.space(view.music && !c.spotify ? 152 : 110)
              enabled: view.music ? (!c.spotify || c.spotify.canTogglePlaying) : c.entries.length > 0 && !c.switchingEpisode
              onClicked: c.toggleSelected()
            }
            ListeningButton {
              text: view.music ? "󰒭" : "+15"
              tint: view.tint
              tooltip: view.music ? "Next track" : "Forward 15 seconds"
              enabled: view.music ? (c.spotify !== null && c.spotify.canGoNext) : c.currentEntry !== null && !c.idle && !c.switchingEpisode
              onClicked: view.music ? c.spotify.next() : c.runControl(["seek", "15"])
            }
            ListeningButton {
              visible: view.music
              readonly property bool shuffled: c.spotify !== null && c.spotify.shuffle
              text: "󰒟  Shuffle"
              tint: view.tint
              prominent: shuffled
              tooltip: shuffled ? "Shuffle is on · Click to turn off" : "Shuffle is off · Click to turn on"
              enabled: c.spotify !== null && c.spotify.canControl && c.spotify.shuffleSupported
              Accessible.name: "Shuffle"
              Accessible.checkable: true
              Accessible.checked: shuffled
              onClicked: c.spotify.shuffle = !c.spotify.shuffle
            }
          }

          Row {
            visible: view.podcasts
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(10)
            ListeningButton { text: c.speed + "× speed"; tint: view.tint; onClicked: c.cycleSpeed() }
            ListeningButton {
              text: "Next episode →"; tint: view.tint
              enabled: c.currentIndex >= 0 && !c.switchingEpisode
              onClicked: c.nextEpisode(false)
            }
          }

          Row {
            visible: view.music && c.spotify !== null && c.spotify.canControl && c.spotify.volumeSupported
            width: parent.width
            spacing: Style.space(10)
            Copy { anchors.verticalCenter: parent.verticalCenter; text: "Volume"; font.pixelSize: Style.font.caption; color: view.muted }
            PanelSlider {
              width: parent.width - x - spotifyVolume.width - parent.spacing
              value: c.spotify ? c.spotify.volume : 0
              fillColor: view.tint; knobColor: view.tint
              trackColor: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.13)
              onReleased: function(value) { if (c.spotify && c.spotify.canControl && c.spotify.volumeSupported) c.spotify.volume = value }
            }
            Copy { id: spotifyVolume; anchors.verticalCenter: parent.verticalCenter; width: Style.space(30); text: Math.round((c.spotify ? c.spotify.volume : 0) * 100) + "%"; font.pixelSize: Style.font.caption; color: view.muted }
          }
        }
      }

      Row {
        visible: view.music
        width: parent.width
        Copy {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - openMusic.width
          text: c.spotify ? c.spotify.trackAlbum || "Spotify desktop" : "Music and podcasts take turns. Ambience can stay."
          color: view.muted
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        ListeningButton { id: openMusic; text: "Browse Spotify ↗"; tint: view.tint; onClicked: c.openSpotify() }
      }

      Column {
        visible: view.music
        width: parent.width
        spacing: Style.space(10)
        Row {
          width: parent.width
          Copy {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - refreshLibrary.width
            text: "YOUR PLAYLISTS  /  " + c.playlists.length
            color: view.muted
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
          }
          ListeningButton {
            id: refreshLibrary
            text: "↻"
            tooltip: "Refresh Spotify playlists"
            enabled: !c.playlistsLoading
            tint: view.tint
            onClicked: c.refreshPlaylists(true)
          }
        }
        Copy {
          visible: c.playlistsLoading
          text: "Loading your library…"
          color: view.muted
          font.pixelSize: Style.font.caption
        }
        Copy {
          visible: c.playlistError !== ""
          width: parent.width
          text: c.playlistError
          color: Color.urgent
          wrapMode: Text.WordWrap
        }
        ListeningButton {
          visible: c.playlistError !== ""
          text: "Spotify connection ↗"
          tint: view.tint
          onClicked: c.openEverything("/settings")
        }
        Copy {
          visible: !c.playlists.length && !c.playlistsLoading && !c.playlistError
          text: "Save a playlist in Spotify, then refresh it here."
          color: view.muted
          font.pixelSize: Style.font.caption
        }
        Grid {
          id: playlistGrid
          width: parent.width
          columns: 2
          spacing: Style.space(8)
          Repeater {
            model: c.playlists
            AbstractButton {
              id: playlistCard
              required property var modelData
              readonly property bool selected: c.selectedPlaylistUri === modelData.uri
              readonly property bool pending: c.pendingPlaylistUri === modelData.uri
              width: (playlistGrid.width - playlistGrid.spacing) / 2
              height: Style.space(72)
              hoverEnabled: true
              enabled: !c.playlistStarting
              Accessible.name: "Play " + modelData.name
              ToolTip.visible: hovered
              ToolTip.text: "Play " + modelData.name + " · " + modelData.tracks_total + " tracks"
              ToolTip.delay: 500
              onClicked: c.playPlaylist(modelData)
              background: Rectangle {
                radius: Style.space(10)
                color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b,
                  playlistCard.selected ? 0.12 : playlistCard.hovered || playlistCard.activeFocus ? 0.08 : 0.035)
                border.width: 1
                border.color: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, playlistCard.selected ? 0.35 : 0.10)
              }
              contentItem: Row {
                anchors.fill: parent
                anchors.margins: Style.space(9)
                spacing: Style.space(10)
                Artwork {
                  width: Style.space(48); height: width
                  anchors.verticalCenter: parent.verticalCenter
                  source: playlistCard.modelData.artwork_url || ""
                  tint: view.tint
                  radius: Style.space(7)
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(58)
                  spacing: Style.space(4)
                  Copy {
                    width: parent.width
                    text: playlistCard.modelData.name
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.bold: true
                  }
                  Copy {
                    width: parent.width
                    text: playlistCard.pending ? "Starting…" : playlistCard.selected ? "Selected  ·  " + playlistCard.modelData.tracks_total + " tracks"
                      : playlistCard.modelData.tracks_total + " tracks  ·  ▶"
                    color: playlistCard.selected ? view.tint : view.muted
                    font.pixelSize: Style.font.caption * 0.9
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }
      }

      Column {
        visible: view.podcasts
        width: parent.width
        spacing: Style.space(10)
        Row {
          width: parent.width
          Copy {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - queueActions.width
            text: "UP NEXT  /  " + c.entries.length
            color: view.muted
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
          }
          Row {
            id: queueActions
            spacing: Style.space(6)
            ListeningButton { text: "↻"; tooltip: "Refresh queue"; enabled: !c.loading; tint: view.tint; onClicked: c.refresh() }
            ListeningButton { text: "Edit queue ↗"; tint: view.tint; onClicked: c.openEverything("/podcasts/queue") }
          }
        }
        Copy { visible: c.loading; text: "Refreshing your queue…"; color: view.muted; font.pixelSize: Style.font.caption }
        Copy { visible: c.errorText !== ""; width: parent.width; text: c.errorText; color: Color.urgent; wrapMode: Text.WordWrap }
        Copy { visible: !c.entries.length && !c.loading; text: "No episodes queued yet."; color: view.muted }
        Repeater {
          model: c.entries
          Rectangle {
            id: episodeRow
            required property var modelData
            required property int index
            readonly property bool selected: index === c.currentIndex
            width: column.width
            height: Style.space(66)
            radius: Style.space(10)
            color: selected ? Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.10)
              : episodeMouse.containsMouse ? Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.05) : "transparent"
            Artwork {
              id: episodeArt
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(46); height: width
              radius: Style.space(7)
              source: episodeRow.modelData.artwork_url || ""
              tint: view.tint
              glyph: "♬"
            }
            Column {
              x: Style.space(66)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - x - Style.space(36)
              spacing: Style.space(4)
              Copy { width: parent.width; text: episodeRow.modelData.title; elide: Text.ElideRight; font.bold: episodeRow.selected }
              Copy { width: parent.width; text: episodeRow.modelData.show_title + "  ·  " + c.clock(episodeRow.modelData.duration_seconds); color: view.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            Copy {
              anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
              text: episodeRow.selected && c.playing ? "Ⅱ" : "▶"
              color: view.tint
            }
            MouseArea {
              id: episodeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !c.switchingEpisode
              onClicked: c.playEpisode(episodeRow.index)
            }
          }
        }
        ListeningButton { text: "Manage shows ↗"; tint: view.tint; onClicked: c.openEverything("/podcasts/subscriptions") }
      }

      Column {
        visible: c.sourceTab === 2
        width: parent.width
        spacing: Style.space(12)
        Row {
          width: parent.width
          Column {
            width: parent.width - stopAmbience.width
            spacing: Style.space(4)
            Copy { text: "A place to settle in"; font.pixelSize: Style.font.body; font.bold: true }
            Copy { text: "Layer a soundscape under your listening."; color: view.muted; font.pixelSize: Style.font.caption }
          }
          ListeningButton { id: stopAmbience; text: "Ⅱ"; tooltip: "Pause all soundscapes"; tint: view.tint; enabled: c.noisePlaying || c.noiseStarting; onClicked: c.noiseCommand(["pause-all"]) }
        }
        Copy { visible: c.noiseError !== ""; width: parent.width; text: c.noiseError; color: Color.urgent; wrapMode: Text.WordWrap }

        Repeater {
          model: c.sounds
          Rectangle {
            id: sound
            required property var modelData
            readonly property var playback: c.soundState(modelData.id)
            readonly property color accent: modelData.color
            width: column.width
            height: soundContent.implicitHeight + Style.space(24)
            radius: Style.space(14)
            color: Qt.rgba(accent.r, accent.g, accent.b, playback.playing ? 0.10 : 0.035)
            border.width: 1
            border.color: Qt.rgba(accent.r, accent.g, accent.b, playback.playing ? 0.32 : 0.12)
            Column {
              id: soundContent
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)
              Row {
                width: parent.width
                spacing: Style.space(12)
                Artwork {
                  width: Style.space(68); height: width
                  source: sound.modelData.artwork
                  tint: sound.accent
                  glyph: "≈"
                }
                Column {
                  width: parent.width - Style.space(68) - soundToggle.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(5)
                  Copy { text: sound.modelData.title; width: parent.width; elide: Text.ElideRight; font.bold: true; font.pixelSize: Style.font.body }
                  Copy { text: sound.playback.loading ? "Loading soundscape…" : sound.playback.playing ? "Playing  ·  " + sound.modelData.subtitle : sound.modelData.subtitle; width: parent.width; elide: Text.ElideRight; color: sound.playback.playing ? sound.accent : view.muted; font.pixelSize: Style.font.caption }
                }
                ListeningButton {
                  id: soundToggle
                  anchors.verticalCenter: parent.verticalCenter
                  text: sound.playback.playing || (sound.playback.loading && sound.playback.requested) ? "Ⅱ" : "▶"
                  tooltip: (sound.playback.playing ? "Pause " : "Play ") + sound.modelData.title
                  tint: sound.accent
                  prominent: sound.playback.playing
                  onClicked: c.noiseCommand(["toggle", sound.modelData.id])
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(10)
                PanelSlider {
                  width: parent.width - soundVolume.width - tune.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  value: sound.playback.volume
                  fillColor: sound.accent; knobColor: sound.accent
                  trackColor: Qt.rgba(sound.accent.r, sound.accent.g, sound.accent.b, 0.15)
                  onReleased: function(value) { c.noiseCommand(["volume", sound.modelData.id, String(value)]) }
                }
                Copy { id: soundVolume; width: Style.space(31); anchors.verticalCenter: parent.verticalCenter; text: Math.round(sound.playback.volume * 100) + "%"; color: view.muted; font.pixelSize: Style.font.caption }
                ListeningButton { id: tune; text: "Tune ↗"; tooltip: "Open the myNoise mixer"; tint: sound.accent; onClicked: c.noiseCommand(["open", sound.modelData.id]) }
              }
              Copy { visible: !!sound.playback.error; width: parent.width; text: sound.playback.error || ""; color: Color.urgent; wrapMode: Text.WordWrap; font.pixelSize: Style.font.caption }
            }
          }
        }
        Copy {
          width: parent.width
          text: "Original soundscapes by myNoise · Your forest preset is saved."
          color: view.muted
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.10) }
      Copy {
        width: parent.width
        text: "1 / 2 / 3  source     Q  equalizer     Space  play / pause     Esc  close"
        color: view.muted
        font.pixelSize: Style.font.caption * 0.9
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
