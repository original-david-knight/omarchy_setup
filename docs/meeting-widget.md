# Meeting widget

`david.meeting` puts today's next work appointment, Meeting Recorder controls,
and desktop-only Logitech Litra Glow controls in one bar panel. The existing Meeting Recorder
widget stays beside it on the desktop because its live waveform is useful while
recording.

## Install

Activate it from the standard checkout with:

```sh
cd ~/omarchy_setup && ./install_meeting.sh
```

The installer honors `OMARCHY_SETUP_PROFILE=desktop` or `laptop`, and uses the
same connected-display detection as Stow for `auto`. Laptops get the calendar
and recorder without light controls, USB polling, or udev changes. The desktop
profile sets `"litra": true` on its `david.meeting` bar entry.

On desktops, the command may ask for `sudo` in the terminal. It installs one udev rule for
the Litra Glow USB product `046d:c900`, links the plugin directory into
`~/.config/omarchy/plugins/`, and adds `david.meeting` to the active bar after
the link is ready. It is safe to run again. It refuses to replace a different
file, directory, or symlink using the same plugin ID. If the shell does not
pick up the plugin automatically, run `omarchy restart shell`.

## What the panel shows

The meeting section uses the existing authenticated `/api/today` feed from
Everything App. It includes every timed, non-declined appointment that is on
one of the work account's enabled calendars; the feed has no attendee field, so
the widget cannot limit this to appointments with other people. It shows an
ongoing appointment first, then the next appointment by start time.

The work calendars come from `/api/today/calendars`, not from each event's
`account` label. When the personal account also subscribes to the work
calendar, the feed keeps only the personal-account copy of each event, so
every work meeting arrives labeled `personal`. Matching on the calendar ID
keeps those meetings.

Click the meeting title, or its button, to open it in the work Chrome profile
through `~/bin/open-work-url`. Keyboard users can select the meeting row and
press Enter, or press `j` anywhere in the panel. The button reads **Join Google Meet**
when the event has a Meet link, and **Open event** when it only has its Google
Calendar page. A feed without either link opens the meeting's day in Google
Calendar. The helper passes on only `https://meet.google.com/` links and
Google Calendar pages, and `open-work-url` refuses any other Google URL, so a
Zoom link falls back to the event page, where Calendar shows its join button.
The links come from the `meet_url` and `html_link` fields of `/api/today`.

The feed contains only today. Near midnight, the widget cannot show tomorrow's
first appointment. The panel reports unavailable or no remaining meetings
instead of guessing.

Recorder controls open, start, pause or resume, and stop the installed
`omarchy-meeting-recorder`. Tests do not start a recording. The light section
switches power and changes brightness from 20 to 250 lumens and color
temperature from 2700 K to 6500 K.

## Helpers and diagnostics

The panel runs the calendar helper, Litra helper, and recorder watcher as
independent processes. A disconnected light therefore does not hide a meeting
or recorder status, and a calendar error does not disable the light. Each
process reports its own missing, permission, connection, or protocol errors.

The local `litra` command is a dependency-free Python helper, not a third-party
Litra CLI. It reads the physical device after every write and never treats a
successful write alone as confirmed state. Polling also picks up power changes
made with the button on the light.

```sh
~/.config/omarchy/plugins/david.meeting/litra status
~/.config/omarchy/plugins/david.meeting/litra set power on
~/.config/omarchy/plugins/david.meeting/litra set brightness 120
~/.config/omarchy/plugins/david.meeting/litra set temperature 4200
~/.config/omarchy/plugins/david.meeting/calendar
omarchy plugin validate ~/omarchy_setup/omarchy/.config/omarchy/plugins/david.meeting
```

Offline checks cover the helper logic and synthetic protocol fixtures. They do
not verify hardware commands and readback, physical-button polling, seated-user
udev access, or the live calendar display. Verify those behaviors on the
installed desktop.
