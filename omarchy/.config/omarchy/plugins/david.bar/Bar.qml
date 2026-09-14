import QtQuick
import Quickshell
import Quickshell.Io
import "ScreenLayouts.js" as ScreenLayouts

// david.bar: the stock Omarchy bar with a different widget layout per screen.
//
// The stock bar (omarchy.bar) builds one surface per monitor from the single
// `bar.layout` in shell.json, so the layout sized for the 5120 px desktop
// monitor also lands on the 1440 px portrait side monitors, where its sections
// overlap. Cloning and patching Bar.qml would freeze a 2000-line file at one
// Omarchy release, so this wrapper never copies that source. It instantiates
// the installed Bar.qml by URL, exactly as omarchy-shell would (the approach of
// the marketplace-approved "Bar Screens" plugin), and then rebinds the module
// lists of every bar surface whose screen matches a `bar.screenLayouts` entry.
// Screens without a match keep the stock bindings untouched, so the primary
// monitor behaves exactly like the built-in bar.
//
// Relied-on stock facts, all checked at runtime and logged when missing:
//   - Quickshell's `Variants.instances` and `PanelWindow.screen`;
//   - each surface lays its widgets out from three objects a few levels below
//     the panel content: two module lists carrying `entries` + `region`
//     ("left" / "right") and a center item carrying `entries`, `hasAnchor` and
//     `anchorEntry`;
//   - `layoutEntries(region)`, `normalizeLayout(layout)`, `entryIndex()` and
//     `centerAnchor` on the stock bar root.
Item {
  id: root

  // Injected by omarchy-shell's configureBar() once this component is loaded.
  property string omarchyPath: ""
  property var barWidgetRegistry: null
  property var barConfig: null
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string stockUrl: "file://"
    + (omarchyPath !== "" ? omarchyPath : (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"))
    + "/shell/plugins/bar/Bar.qml"

  property var inner: null
  property bool loading: false
  property string failure: ""

  // omarchy-shell and first-party plugins (the notifications service, panel
  // hotkeys, `omarchy bar` IPC) read these from the active bar object, which
  // is this wrapper. Forward them so popups keep clearing the bar and the
  // stock IPC surface keeps working.
  readonly property bool barHidden: inner ? inner.barHidden === true : false
  readonly property int barSize: inner ? Math.max(0, inner.barSize || 0) : 0
  readonly property string fontFamily: inner ? String(inner.fontFamily || "") : ""
  readonly property string position: inner ? String(inner.position || "top") : "top"
  readonly property bool vertical: inner ? inner.vertical === true : false
  readonly property bool transparent: inner ? inner.transparent === true : false

  function summonBarWidget(pluginId) {
    return inner && typeof inner.summonBarWidget === "function" ? inner.summonBarWidget(pluginId) : false
  }

  function hideBarWidget(pluginId) {
    return inner && typeof inner.hideBarWidget === "function" ? inner.hideBarWidget(pluginId) : false
  }

  function isBarWidgetOpen(pluginId) {
    return inner && typeof inner.isBarWidgetOpen === "function" ? inner.isBarWidgetOpen(pluginId) : false
  }

  function toggleTransparency() {
    if (inner && typeof inner.toggleTransparency === "function") inner.toggleTransparency()
  }

  function debugBarGeometry() {
    return inner && typeof inner.debugBarGeometry === "function" ? inner.debugBarGeometry() : []
  }

  function panelWidgetIdAt(region, index) {
    return inner && typeof inner.panelWidgetIdAt === "function" ? inner.panelWidgetIdAt(region, index) : ""
  }

  // ── loading the stock bar ─────────────────────────────────────────────

  readonly property bool hostReady: barWidgetRegistry !== null
  onHostReadyChanged: if (hostReady && !inner && !loading) load()
  Component.onCompleted: if (hostReady && !inner && !loading) load()

  function load() {
    loading = true
    var component = Qt.createComponent(stockUrl, Component.Asynchronous)
    function ready() {
      if (component.status === Component.Loading) return
      loading = false
      if (component.status !== Component.Ready) {
        fail(stockUrl + " failed to load: " + component.errorString())
        return
      }
      var initial = { barWidgetRegistry: root.barWidgetRegistry, shell: root.shell }
      if (root.omarchyPath !== "") initial.omarchyPath = root.omarchyPath
      var created = component.createObject(root, initial)
      if (!created) {
        fail(stockUrl + " could not be instantiated: " + component.errorString())
        return
      }
      // barConfig and manifest go in after creation. Passed as initial
      // properties, their nested arrays arrive as sequence wrappers that the
      // stock bar's Array.isArray checks reject.
      created.manifest = root.manifest
      if ("pluginRegistry" in created) created.pluginRegistry = root.pluginRegistry
      root.inner = created
      guardConfigWrites()
      refreshScreenLayouts(true)
      hookVariants()
      // Bind the matching screens before the stock bar sees the real config:
      // its layout is still empty here, so those screens build their own
      // widgets once instead of building the full layout and replacing it.
      apply()
      created.barConfig = root.barConfig
      Qt.callLater(root.apply)
    }
    if (component.status === Component.Loading) component.statusChanged.connect(ready)
    else ready()
  }

  function fail(reason) {
    failure = reason
    console.warn("david.bar: " + reason)
    Quickshell.execDetached(["omarchy-notification-send", "Bar failed to load", reason])
  }

  onBarConfigChanged: {
    if (inner) inner.barConfig = barConfig
    refreshScreenLayouts(false)
  }
  onBarWidgetRegistryChanged: if (inner) inner.barWidgetRegistry = barWidgetRegistry
  onManifestChanged: if (inner) inner.manifest = manifest
  onShellChanged: {
    if (inner) inner.shell = shell
    guardConfigWrites()
  }

  // ── per-screen layouts from shell.json ───────────────────────────────

  property var screenLayouts: []
  property int screenLayoutsRevision: 0
  property string screenLayoutsJson: ""

  function refreshScreenLayouts(force) {
    var parsed = ScreenLayouts.parse(root.barConfig, function(message) { console.warn("david.bar: " + message) })
    var json = JSON.stringify(parsed)
    if (!force && json === screenLayoutsJson) return
    screenLayoutsJson = json
    // The stock normalization canonicalizes widget ids and keeps the tray at
    // the inner edge of its section, the same treatment `bar.layout` gets.
    if (inner && typeof inner.normalizeLayout === "function") {
      for (var i = 0; i < parsed.length; i++) parsed[i].layout = inner.normalizeLayout(parsed[i].layout)
    }
    screenLayouts = parsed
    screenLayoutsRevision++
    scheduleApply()
  }

  function scheduleApply() {
    Qt.callLater(root.apply)
  }

  property var hooked: []

  function variantsOf(item) {
    var out = []
    if (!item) return out
    var list = item.data
    var n = list ? list.length : 0
    for (var i = 0; i < n; i++) {
      var v = list[i]
      if (v && ("instances" in v) && ("model" in v) && ("delegate" in v)) out.push(v)
    }
    return out
  }

  function hookVariants() {
    var vs = variantsOf(inner)
    for (var i = 0; i < vs.length; i++) {
      var v = vs[i]
      if (hooked.indexOf(v) !== -1) continue
      v.instancesChanged.connect(root.scheduleApply)
      hooked.push(v)
    }
  }

  // One bar surface per screen. Drag and move ghost panels carry
  // `ghostScreen`; they have no module lists and are skipped.
  function barPanels() {
    var panels = []
    var vs = variantsOf(inner)
    for (var i = 0; i < vs.length; i++) {
      var inst = vs[i].instances
      var n = inst ? inst.length : 0
      for (var j = 0; j < n; j++) {
        var w = inst[j]
        if (!w || !("screen" in w) || !("contentItem" in w) || ("ghostScreen" in w)) continue
        panels.push(w)
      }
    }
    return panels
  }

  function findSections(item, depth, found) {
    if (!item || depth > 6) return found
    var kids = item.children
    var n = kids ? kids.length : 0
    for (var i = 0; i < n; i++) {
      var child = kids[i]
      if (!child) continue
      if (("entries" in child) && ("hasAnchor" in child) && ("anchorEntry" in child)) {
        found.center = child
        continue
      }
      if (("entries" in child) && ("region" in child)) {
        var region = String(child.region || "")
        if (region === "left" || region === "right") found[region] = child
        continue
      }
      findSections(child, depth + 1, found)
    }
    return found
  }

  // Sections carrying our bindings. A binding reads the matching screen
  // layout and falls back to the stock `layoutEntries(region)` when no entry
  // matches any more, so a section is bound at most once. Sections on screens
  // that never matched are never touched, which keeps the primary monitor's
  // widgets from being rebuilt at startup.
  //
  // Only `entries` is rebound. The center section's `hasAnchor` derives from
  // it, so `bar.centerAnchor` anchors a screen layout's center only when that
  // layout lists the anchor widget; otherwise the center group is centered as
  // a whole. Its read-only `anchorEntry` keeps naming the stock layout's
  // anchor entry, so an anchored widget takes its inline settings from
  // `bar.layout`, and the stock layout's anchor stays loaded but hidden on
  // screens whose layout omits it.
  property var bound: []

  function bindSection(section, screen, region) {
    section.entries = Qt.binding(function() {
      var revision = root.screenLayoutsRevision
      var layout = ScreenLayouts.layoutFor(root.screenLayouts, screen)
      if (layout) return layout.layout[region]
      return root.inner && typeof root.inner.layoutEntries === "function" ? root.inner.layoutEntries(region) : []
    })
  }

  property string lastSummary: ""

  function applyPanel(panel, stillBound) {
    var screen = panel.screen
    var layout = ScreenLayouts.layoutFor(root.screenLayouts, screen)
    var sections = findSections(panel.contentItem, 0, { left: null, center: null, right: null })
    var regions = ["left", "center", "right"]
    var missing = []
    for (var r = 0; r < regions.length; r++) {
      var region = regions[r]
      var section = sections[region]
      if (!section) {
        missing.push(region)
        continue
      }
      if (bound.indexOf(section) !== -1) {
        stillBound.push(section)
        continue
      }
      if (!layout) continue
      bindSection(section, screen, region)
      stillBound.push(section)
    }
    if (layout && missing.length > 0) {
      console.warn("david.bar: could not find the " + missing.join("/") + " module list on "
        + ScreenLayouts.describeScreen(screen) + "; the stock bar layout code may have changed")
    }
    return ScreenLayouts.describeScreen(screen) + " -> " + (layout ? layout.name : "stock layout")
  }

  function apply() {
    if (!inner) return
    hookVariants()
    var panels = barPanels()
    var stillBound = []
    var summary = []
    for (var i = 0; i < panels.length; i++) {
      try {
        summary.push(applyPanel(panels[i], stillBound))
      } catch (error) {
        var label = panels[i] && panels[i].screen ? ScreenLayouts.describeScreen(panels[i].screen) : "a bar surface"
        console.warn("david.bar: leaving " + label + " on the stock layout: " + error)
        summary.push(label + " -> stock layout (error)")
      }
    }
    bound = stillBound
    var text = summary.length > 0 ? summary.join("; ") : "no bar surfaces found"
    if (text !== lastSummary) {
      lastSummary = text
      console.log("david.bar: " + text)
    }
  }

  // ── keep widget drags on custom screens away from bar.layout ─────────
  //
  // Dragging a widget makes the stock bar move that id inside `bar.layout`,
  // which on a screen showing a screen layout would silently reorder the
  // primary monitor instead. The bar clears its drag state right before it
  // writes the drop, in the same event handler, so remember where the drag
  // started and drop the write that follows.

  property var dragScreen: null
  property bool dragEndedOnCustomScreen: false
  property var guardedShell: null

  Connections {
    target: root.inner
    enabled: root.inner !== null
    ignoreUnknownSignals: true

    function onBarDragSourceChanged() {
      if (root.inner.barDragSource) {
        root.dragScreen = root.inner.barDragScreen || null
        return
      }
      root.dragEndedOnCustomScreen = ScreenLayouts.layoutFor(root.screenLayouts, root.dragScreen) !== null
      root.dragScreen = null
      Qt.callLater(function() { root.dragEndedOnCustomScreen = false })
    }

    function onVerticalChanged() {
      root.scheduleApply()
    }
  }

  function guardConfigWrites() {
    var api = root.shell
    if (!api || api === root.guardedShell || typeof api._mutateBarConfig !== "function") return
    var original = api._mutateBarConfig
    api._mutateBarConfig = function(mutator) {
      if (root.dragEndedOnCustomScreen) {
        console.warn("david.bar: ignored a widget drag on a screen that uses bar.screenLayouts; edit that layout in shell.json instead")
        return false
      }
      return original(mutator)
    }
    root.guardedShell = api
  }

  // `omarchy-shell david.bar status` prints which layout each screen shows.
  IpcHandler {
    target: "david.bar"

    function status(): string {
      if (root.failure !== "") return "failed: " + root.failure
      return root.lastSummary !== "" ? root.lastSummary : "stock bar not loaded yet"
    }
  }
}
