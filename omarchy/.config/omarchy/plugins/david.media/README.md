# Media key ownership

Cloned with `omarchy plugin clone omarchy.media` from the installed Omarchy
media plugin on 2026-09-13. `BarWidget.qml` and `MediaModel.js` retain the stock
implementation; `Service.qml` changes source selection:

- Observe each real MPRIS player's transition into playback.
- Keep the most recently started source selected through pauses and stops.
- Ignore proxy players, metadata updates, and lingering PipeWire streams when
  deciding which source receives keys.
- Send all actions to that source. An unsupported action or a missing source
  does nothing instead of controlling a different player.
- Retain explicit source selection and cycling, targeted controls, and OSD.

Both setup profiles enable this clone in `plugins` and disable `omarchy.media`.
The existing Listening widget remains the bar UI. The clone's stock bar widget
is available but is not added to either layout.

Tests run the service with synthetic QML players on a private D-Bus session:
`python -m unittest discover -s tests -p 'test_media_keys.py'`.
