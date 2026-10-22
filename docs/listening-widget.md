# Listening widget

The existing `david.podcasts` bar slot now opens **Listening**. Its ID stays the
same in both machine profiles, preserving podcast playback, progress storage,
and existing media-key shortcuts. The bar shows artwork and the playing title;
narrow displays use a compact artwork button.

- **Spotify:** desktop playback, previous/next, shuffle, seek, volume, and album art.
  **Shuffle** glows green when enabled and follows changes made in Spotify.
  **Start Spotify** launches it in the hidden `special:spotify` workspace.
  **Browse Spotify** reveals its full window when you need it. `Super+Shift+M`
  shows or hides that workspace without stopping playback. Sign in normally
  through the full window if needed. No developer API key is needed.
  The **Your playlists** cards load your library through the existing Everything
  Spotify connection. Click a cover to start that playlist in this computer's
  hidden Spotify player. Use ↻ or `R` to refresh. The highlighted card is the
  last playlist selected in this panel; changes made in Spotify itself still
  update the track artwork and playback controls.
- **Podcasts:** the Everything queue, episode/show artwork, seek, ±15 seconds,
  playback speed, next episode, and the existing progress synchronization.
- **myNoise:** Irish Coast, Primeval Forest (the exact supplied URL preset),
  and Summer Night. Each has independent play/pause and volume. **Tune** opens
  its official web mixer; closing that window leaves playback running.

## Equalizer

**EQ** in the panel header (or `Q`) opens a ten-band equalizer, 32 Hz to
16 kHz in half-decibel steps up to ±12 dB, with Bass, Warm, Voice, Bright and
Flat presets and an on/off switch that keeps the curve. Drag or scroll a band;
double-click resets it. The button fills in while the curve is shaping sound.

It changes only the Listening sources. Spotify, podcasts and myNoise play into
a PipeWire filter-chain sink, `listening_eq`, which passes on to whatever
output is the default; games, calls and browsers never enter it. The widget's
mpv and myNoise players name the sink when they start. Spotify starts outside
the widget, so opening the panel or starting Spotify moves its stream onto the
sink, and WirePlumber remembers that for later launches. Moving Spotify
elsewhere is undone the next time the panel opens; turn the EQ off instead.
When the sink is missing, every source falls back to the default output.

A preamp lowers the output by the largest boost to add headroom. Overlapping
bands can still exceed that headroom; this is not a limiter.
Off sets every band and the preamp to unity, so the sound is unchanged.

The sink is `desktop/.config/pipewire/filter-chain.conf.d/70-listening-eq.conf`,
run by PipeWire's own `filter-chain.service`, separate from the main daemon,
so restarting it interrupts only Listening audio. `activate.sh` enables it and
restarts it only when that file changes. The curve is saved in
`~/.local/state/david-listening/eq.json`. A filter-chain drops control changes
until audio has passed through it once, so the `eq` helper sends the new sink
50 ms of silence when a write does not stick. A drop-in on the service
reapplies the saved curve whenever the sink starts, including after PipeWire
restarts.

The Arctis base station has its own hardware EQ in the headset widget; it
shapes everything sent to that headset, while this one follows Listening to any
output.

Starting music from the widget pauses podcasts; starting a podcast pauses
Spotify. Soundscapes can play together and underneath either source. Switching
tabs only changes the view. **Ⅱ All** pauses every source controlled here.

Press `Super+M` or click the bar button to open or close. Middle-click toggles the active source;
right-click pauses all. In the panel, `1`/`2`/`3`, left/right, or Tab switch
sources, Space plays/pauses, `R` refreshes podcasts, `E` opens the queue, `Q`
opens the equalizer, and Escape closes. When several sources play, the middle-click priority is
Spotify, podcasts, then ambience; use pause-all to silence all three.

Keyboard media keys follow the source that most recently started playing,
including YouTube, Spotify, and podcasts. Pausing from either the keyboard or
the app keeps that source selected until another source starts. Next/previous
also stay with that source; unsupported actions do nothing. Closing the source
does not resume an unrelated player. The widget's middle-click and panel
controls remain specific to Listening.

`david.media` is a user-owned clone of Omarchy's media service with this routing
policy. Both profiles load it as a background service and disable the stock
`omarchy.media` service. It preserves the `media` IPC target and playback OSD,
so the existing Hyprland shortcuts also use it. Playback history is held for
the lifetime of the shell; after a restart, start playback in the desired app
if all players are paused. Podcasts join the same selection through `mpv-mpris`.

## Install and configuration

`./install_listening.sh` installs Spotify, mpv, mpv-mpris, socat, jq, curl, PySide6, and
Qt WebEngine. It is included in `install_all.sh`; `stow_all.sh` deploys the
widget with the shared `omarchy` package.

The files live under `omarchy/.config/omarchy/plugins/david.podcasts/`.
Edit `soundscapes.json` to change the saved list, then restart the soundscape
helper and shell. `url` is used as supplied, including all preset parameters.
myNoise artwork stays hosted by myNoise; audio plays in its official website,
preserving its ten-channel generator. There are no copied audio files.

The background Qt WebEngine player starts only when first needed. Its control
socket is private to the current user under `$XDG_RUNTIME_DIR/david-listening/`.
Volumes and its separate website profile live in
`~/.local/state/david-listening/`. Playback does not resume automatically after
a helper restart. Volume defaults to 35%, and its sliders attenuate the original
soundscape. Internet access is required. Website changes can require an update
to the small adapter in `mynoise`.

Podcast configuration remains `~/.config/everything-agent/config.json`.
Show covers fill in missing episode artwork; unavailable images get a record
illustration. Spotify controls depend on the capabilities its desktop player
advertises through MPRIS.

## Diagnostics

```sh
omarchy-shell david.listening show spotify  # also podcasts or mynoise
omarchy-shell david.listening status
omarchy-shell david.listening pauseAll
omarchy-shell david.listening showEq
~/.config/omarchy/plugins/david.podcasts/eq status          # available, applied, curve
~/.config/omarchy/plugins/david.podcasts/eq preset voice    # also set-band 3 4.5, enable off
systemctl --user status filter-chain.service
pactl list short sink-inputs                                # Listening sources on listening_eq
~/.config/omarchy/plugins/david.podcasts/mynoise status
~/.config/omarchy/plugins/david.podcasts/mynoise shutdown
omarchy plugin validate ~/.config/omarchy/plugins/david.podcasts
omarchy-shell media status                  # includes selected and remembered player keys
python -m unittest discover -s tests -p 'test_media_keys.py'
python -m unittest discover -s tests -p 'test_listening.py'
```

The soundscape helper log is `~/.local/state/david-listening/mynoise.log`.
Plugin edits normally hot-reload; `omarchy restart shell` clears cached QML
after changes to shared component files.
