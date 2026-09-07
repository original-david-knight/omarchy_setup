# Middle-click selection paste

`primary-selection-sync.service` synchronizes text in PRIMARY between XWayland
(Chrome on this desktop) and native Wayland applications such as Ghostty.
The ordinary Ctrl+C/Ctrl+V clipboard is independent and is never read or written.

The bridge works around two behaviors in Hyprland 0.56.2's selection code:

- `CPrimarySelectionProtocol::setSelection` resets the stored selection when
  the pointer's client has no primary-selection device, including XWayland.
- `CXWM::handleSelectionRequest` does not advertise PRIMARY MIME types in its
  X11 TARGETS response.

It owns an independent X11 selection and watches Wayland PRIMARY changes.
It remembers the latest nonempty text only in memory, suppresses echoed values,
and restores a lost Wayland selection over a native window, checking every
100 ms. Over an X11 window it releases the compositor's Wayland PRIMARY owner
and supplies X11 PRIMARY itself, preventing Hyprland from reclaiming it during
Chrome's paste. The cached text is restored on returning to a native window.
Moving between applications can therefore take up to one check interval
to make the selection available. Empty selections do not erase the remembered
text. Text over 8 Mi characters and non-text selections are not synchronized.

The service uses Python, PyGObject, GTK3, libX11, wl-clipboard, and Hyprland's Lua API.
It uses GTK3's X11 text provider, verified with Chrome 152. Clipboard reads alone
are insufficient validation: the earlier bridge allowed GTK readers to retrieve
text while Chrome still received an empty paste event during the focus handoff.
These dependencies are already present on this Omarchy installation. The Stow
`bin` and `hypr` packages deploy the helper and unit; `autostart.lua` starts it.

```sh
systemctl --user status primary-selection-sync.service
systemctl --user restart primary-selection-sync.service
systemctl --user stop primary-selection-sync.service
```

To remove the workaround permanently, disable the unit and remove its startup
entry in `hypr/.config/hypr/autostart.lua`, then remove the helper and unit links.
Keep `misc.middle_click_paste = true` and GTK's `gtk-enable-primary-paste` enabled.

Validated with exact UTF-8 and multiline transfers in both directions and with
selection paste into a native Ghostty diagnostic terminal. The reverse fix was
also verified with a real Ghostty selection and a virtual mouse middle click
into an actual Chrome textarea; Chrome's paste event contained text and the
field received the expected selection. No browser or terminal restarts are needed.
