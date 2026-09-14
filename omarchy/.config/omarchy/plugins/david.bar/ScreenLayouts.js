// Pure helpers behind david.bar: which `bar.screenLayouts` entry from
// shell.json applies to a given screen. No QML or Quickshell dependency, so
// tests/test_bar_screen_layouts.py can run this file under Node.

var ORIENTATIONS = ["portrait", "landscape"]
var SECTIONS = ["left", "center", "right"]
var MATCH_KEYS = ["orientation", "name", "model", "serialNumber"]

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function lower(value) {
  return String(value === undefined || value === null ? "" : value).trim().toLowerCase()
}

function orientationOf(screen) {
  if (!screen) return ""
  var width = Number(screen.width) || 0
  var height = Number(screen.height) || 0
  if (width <= 0 || height <= 0) return ""
  return height > width ? "portrait" : "landscape"
}

// A match is a string ("portrait", "landscape", or a connector name such as
// "DP-1") or an object whose keys are all required to match. Each key takes
// one value or a list of alternatives; comparisons ignore case.
function normalizeMatch(match) {
  var out = {}
  if (typeof match === "string") {
    var word = lower(match)
    if (word === "") return null
    if (ORIENTATIONS.indexOf(word) !== -1) out.orientation = [word]
    else out.name = [word]
    return out
  }
  if (!isObject(match)) return null
  var keys = 0
  for (var i = 0; i < MATCH_KEYS.length; i++) {
    var key = MATCH_KEYS[i]
    if (!(key in match)) continue
    var raw = Array.isArray(match[key]) ? match[key] : [match[key]]
    var values = []
    for (var j = 0; j < raw.length; j++) {
      var value = lower(raw[j])
      if (value !== "") values.push(value)
    }
    if (values.length === 0) return null
    if (key === "orientation") {
      for (var k = 0; k < values.length; k++) {
        if (ORIENTATIONS.indexOf(values[k]) === -1) return null
      }
    }
    out[key] = values
    keys++
  }
  return keys > 0 ? out : null
}

function screenMatches(screen, match) {
  if (!screen || !match) return false
  var actual = {
    orientation: orientationOf(screen),
    name: lower(screen.name),
    model: lower(screen.model),
    serialNumber: lower(screen.serialNumber)
  }
  for (var key in match) {
    var wanted = match[key]
    if (!Array.isArray(wanted)) continue
    if (actual[key] === "" || wanted.indexOf(actual[key]) === -1) return false
  }
  return true
}

function normalizeEntry(entry) {
  if (typeof entry === "string") return entry.trim() === "" ? null : { id: entry.trim() }
  if (isObject(entry) && typeof entry.id === "string" && entry.id.trim() !== "") {
    return JSON.parse(JSON.stringify(entry))
  }
  return null
}

function normalizeLayout(layout) {
  var source = isObject(layout) ? layout : {}
  var out = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    var section = SECTIONS[i]
    var list = Array.isArray(source[section]) ? source[section] : []
    out[section] = []
    for (var j = 0; j < list.length; j++) {
      var entry = normalizeEntry(list[j])
      if (entry) out[section].push(entry)
    }
  }
  return out
}

// Reads `bar.screenLayouts` from a bar config. Invalid entries are dropped and
// reported through `warn` so a typo in shell.json cannot take the bar down.
function parse(barConfig, warn) {
  var list = isObject(barConfig) && Array.isArray(barConfig.screenLayouts) ? barConfig.screenLayouts : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var label = isObject(item) && typeof item.name === "string" && item.name !== "" ? item.name : "#" + (i + 1)
    var match = isObject(item) ? normalizeMatch(item.match) : null
    if (!match) {
      if (warn) warn("screenLayouts entry " + label + " has no usable match; expected \"portrait\", \"landscape\", a connector name, or an object with orientation/name/model/serialNumber")
      continue
    }
    if (!isObject(item.layout)) {
      if (warn) warn("screenLayouts entry " + label + " has no layout object")
      continue
    }
    out.push({ name: label, match: match, layout: normalizeLayout(item.layout) })
  }
  return out
}

// The first matching entry wins; null means the screen keeps the stock layout.
function layoutFor(layouts, screen) {
  if (!Array.isArray(layouts)) return null
  for (var i = 0; i < layouts.length; i++) {
    if (screenMatches(screen, layouts[i].match)) return layouts[i]
  }
  return null
}

function describeScreen(screen) {
  if (!screen) return "(no screen)"
  var parts = [String(screen.name || "?"), (Number(screen.width) || 0) + "x" + (Number(screen.height) || 0)]
  var orientation = orientationOf(screen)
  if (orientation) parts.push(orientation)
  if (screen.model) parts.push("(" + String(screen.model) + ")")
  return parts.join(" ")
}

function layoutIds(layout) {
  var ids = []
  for (var i = 0; i < SECTIONS.length; i++) {
    var list = layout && Array.isArray(layout[SECTIONS[i]]) ? layout[SECTIONS[i]] : []
    for (var j = 0; j < list.length; j++) ids.push(String(list[j].id))
  }
  return ids
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    orientationOf: orientationOf,
    normalizeMatch: normalizeMatch,
    screenMatches: screenMatches,
    normalizeLayout: normalizeLayout,
    parse: parse,
    layoutFor: layoutFor,
    describeScreen: describeScreen,
    layoutIds: layoutIds
  }
}
