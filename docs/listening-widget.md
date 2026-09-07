# Listening widget

The existing `david.podcasts` bar slot now opens **Listening**. Its ID stays the
same in both machine profiles, preserving podcast playback, progress storage,
and existing media-key helpers. The bar shows artwork and the playing title;
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

Starting music from the widget pauses podcasts; starting a podcast pauses
Spotify. Soundscapes can play together and underneath either source. Switching
tabs only changes the view. **Ⅱ All** pauses every source controlled here.

Press `Super+M` or click the bar button to open or close. Middle-click toggles the active source;
right-click pauses all. In the panel, `1`/`2`/`3`, left/right, or Tab switch
sources, Space plays/pauses, `R` refreshes podcasts, `E` opens the queue, and
Escape closes. When several sources play, the middle-click priority is
Spotify, podcasts, then ambience; use pause-all to silence all three.

## Install and configuration

`./install_listening.sh` installs Spotify, mpv, socat, jq, curl, PySide6, and
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
~/.config/omarchy/plugins/david.podcasts/mynoise status
~/.config/omarchy/plugins/david.podcasts/mynoise shutdown
omarchy plugin validate ~/.config/omarchy/plugins/david.podcasts
python -m unittest discover -s tests -p 'test_listening.py'
```

The soundscape helper log is `~/.local/state/david-listening/mynoise.log`.
Plugin edits normally hot-reload; `omarchy restart shell` clears cached QML
after changes to shared component files.
