# Arctis headset widget

Standalone plugin and installation instructions:
[omarchy-arctis-headset](https://github.com/original-david-knight/omarchy-arctis-headset).
This setup repository already deploys `david.headset`; do not install a second
copy with the same ID. [Marketplace submission](https://github.com/omacom/omarchy-plugin-marketplace/issues/6439).

`david.headset` controls a SteelSeries Arctis Nova Pro Omni from the bar. The
headset's base station (the DAC) is a USB device, `1038:2290`, whose vendor
HID interface carries every setting SteelSeries GG exposes. The widget talks
to it directly; SteelSeries GG, Arctis Sound Manager, and HeadsetControl are
not needed and not touched.

The bar shows a headset glyph, the base station volume, and a red mic glyph
while the microphone is muted. The glyph takes the accent colour while ANC is
on and dims when the headset is off or unplugged.

- **Left click** opens the panel. **Middle click** switches ANC on or off.
  **Right click** mutes or unmutes the microphone. **Scroll** turns the base
  station volume by four percent per notch.
- **Noise control:** Off, Transparent, or ANC, with ANC strength (Low, Medium,
  High) or the transparency level 1 to 10 underneath. The switch in the panel
  header is ANC on/off. Presses on the headset's own ANC button show up in the
  panel as they happen.
- **Headset volume:** the base station's analog volume, separate from the
  PipeWire volume the stock audio widget controls. The DAC reports knob turns
  but has no read for the level, so the slider learns it from the first knob
  turn after login (or the first slider drag) and remembers it in
  `~/.local/state/david-headset/state.json`.
- **Microphone:** the switch mutes the headset's PipeWire source, which every
  app hears. The mute button on the earcup is a separate hardware mute: the
  DAC reports it, the panel shows a red note while it is on, and only the
  earcup button clears it (a capture from the source is digital silence while
  it is engaged). **Hear your own voice** is sidetone: a little of your mic fed
  back into the headphones so you do not shout; 0 is off.
- **Equalizer:** the base station's own ten-band EQ (32 Hz to 16 kHz) in
  half-decibel steps up to ±10 dB. Drag and release or scroll a band; **Flat**
  resets all ten. Each edit sends the complete curve to the DAC's **Custom**
  radio EQ slot. The DAC has no verified full-curve readback, so bands show
  as neutral until the widget writes them or the DAC announces an edit made
  on its screen. On the first write, any unknown bands are set to 0 dB.
- **Battery:** headset charge and the spare battery in the charging slot,
  refreshed from the DAC every thirty seconds and on every battery event.

Keyboard: `a` ANC on/off, `t` transparency on/off, `m` mic, `+`/`-` volume,
`j`/`k` move between rows, `h`/`l` adjust the current row, `r` refresh,
`Esc` closes.

## Install and configuration

`./install_headset.sh` installs a udev rule tagging the DAC's hidraw nodes for
the seated user. It runs as part of `install_all.sh`; `stow_all.sh` deploys the
widget with the shared `omarchy` package, and both bar layouts place it next
to `omarchy.audio`. The DAC's mode switch must be on **USB-1**; the USB-2 and
Xbox positions enumerate as different products whose control protocol is
silent.

The plugin lives in `omarchy/.config/omarchy/plugins/david.headset/`:

- `headset` is a dependency-free Python helper. `headset watch` owns the
  device for the widget: it prints a JSON status line at start and on every
  change, re-reads the status block every thirty seconds, reconnects on
  hot-plug, and takes commands on stdin (`set anc on`, `set volume 60`,
  `volume up 4`, `set eq-band 3 24`, `set eq-flat 1`, `refresh`). One helper
  runs per monitor; they share `~/.local/state/david-headset/state.json` and
  serialize writes so a band edit preserves changes from another monitor.
  `headset status` and `headset set KEY VALUE`
  do the same from a terminal.
- `Panel.qml` is the bar button and popout.

Settings and their wire opcodes come from the Arctis Sound Manager project's
Omni profile, which was validated against SteelSeries GG captures on this exact
product. The base station volume write (`0x25`) is the sibling Nova Elite base
station's, which the Omni's own device spec extends; it applies silently and
is confirmed working on this headset.

EQ uses the Omni/Elite radio model format documented by
[Cisien's EQ tool](https://github.com/Cisien/arctis-things#arctis-nova-pro-omni--nova-elite-eq-tool):
`01 1b 04`, a six-byte alias, a 61-byte name, and ten six-byte parametric
filters. Each filter carries a little-endian frequency, peak type `1`, a
signed gain in tenths of a decibel, and Q in thousandths (`1410`). The
130-byte model is padded to the Omni's 1036-byte HID **Feature** report and
sent using `HIDIOCSFEATURE`; ordinary `os.write` sends an **Output** report
and cannot apply it. The old `01 31 <band> <value>` writes were inferred
from the DAC's notifications and had no audible effect.

No extra preset-select or flash-save command is sent. Successful transfer
is checked before remembering the curve; it is not a device readback or
proof of persistence after power loss. Confirm the first edit by listening
and checking Custom on the DAC's screen.

## Diagnostics

```sh
~/.config/omarchy/plugins/david.headset/headset status
~/.config/omarchy/plugins/david.headset/headset set anc transparent
~/.config/omarchy/plugins/david.headset/headset volume down
~/.config/omarchy/plugins/david.headset/headset set eq-band 1:30   # band 1 to +5 dB
omarchy-shell david.headset toggleAnc      # also toggleMic, volumeUp, volumeDown, status, open, close
omarchy plugin validate ~/omarchy_setup/omarchy/.config/omarchy/plugins/david.headset
python -m unittest tests.test_headset
getfacl /dev/hidraw*                       # the DAC nodes should list user:$USER:rw-
```

`headset status` reporting "no permission" means the udev rule is missing or
the graphical session is not seat-attached; rerun `./install_headset.sh`.
"Not connected" with the DAC plugged in almost always means the mode switch is
not on USB-1.
