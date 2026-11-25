import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// david.agents: the stock Agents panel with unified remaining-quota bars across
// Antigravity, Claude Code, and Codex, plus a Claude Code account switch.
//
// Copying the stock panel would freeze 2100 lines at one Omarchy release, so
// this wrapper instantiates the installed Panel.qml by URL, exactly as
// omarchy-shell would (the david.bar technique), and injects custom rows into
// specific provider sections:
// - Antigravity: live weekly and 5-hour remaining quota bars via
//   ~/bin/agy-quota (aicode.googleapis.com/v1alpha:fetchQuotaStatus),
//   replacing the stock limits column because Omarchy's packaged collector
//   queries daily-cloudcode-pa which no longer returns Gemini buckets.
// - Claude Code: an Account switch via ~/bin/claude-account (see
//   docs/claude-accounts.md) plus unified remaining-quota bars in the theme's
//   orange color, replacing the stock used-quota bars.
// - Codex: unified remaining-quota bars in the theme's magenta color,
//   replacing the stock used-quota bars while keeping reset-credit info.
//
// Extending the stock panel as a QML type instead does not work: the shell
// rewrites its own files to qs:// URLs, and the stock panel's inline
// components ("DayRow is not a type") fail to resolve when it is a base type.
//
// Stock 4.5 has its own account switch, but it gives each account a separate
// CLAUDE_CONFIG_DIR that only reaches `claude` launched through its mise
// wrapper; claude-account swaps the login inside the one ~/.claude instead.
//
// Relied-on stock facts, checked at runtime and logged when missing: the
// panel exposes `providerSections`, a Repeater with one Column per agent, and
// a section's name row is its only child carrying `lit`. Sections are rebuilt
// whenever the agent list changes, so custom rows are placed again each time.
// Tab from this panel to its bar neighbors does not work, because the stock
// panel asks the bar for its own slot, which belongs to this wrapper.
Item {
  id: agents

  // Injected by the bar.
  property QtObject bar: null
  property string moduleName: "david.agents"
  property var settings: ({})

  readonly property string stockUrl: "file://" + (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
    + "/shell/plugins/agents/Panel.qml"
  property var inner: null
  property Item accountRow: null
  property Item agyQuotaRow: null
  property Item codexQuotaRow: null

  readonly property bool opened: !!inner && inner.opened === true
  function open() { if (inner) inner.open() }
  function close() { if (inner) inner.close() }
  function toggle() { if (inner) inner.toggle() }
  function closeForPopoutSwitch() { if (inner) inner.closeForPopoutSwitch() }

  // The stock panel leaves the bar until some agent has usage to show.
  visible: !!inner && inner.providers.length > 0
  implicitWidth: inner ? inner.implicitWidth : 0
  implicitHeight: inner ? inner.implicitHeight : 0

  readonly property string cli: (Quickshell.env("HOME") || "") + "/bin/claude-account"
  readonly property string agyCli: (Quickshell.env("HOME") || "") + "/bin/agy-quota"
  property var accounts: []
  property string accountError: ""
  property bool switching: false
  property var quotaSnapshots: ({})
  property string quotaRequestEmail: ""
  property string hoveredEmail: ""
  property var agyQuota: null
  property double agyLastSyncMs: 0
  readonly property bool agyQuotaActive: !!agyQuota && ((agyQuota.limits && agyQuota.limits.length > 0) || String(agyQuota.status || "") !== "")
  readonly property color foreground: inner ? inner.foreground : Commons.Color.foreground
  readonly property color dim: inner ? inner.dim : Qt.darker(foreground, 1.55)
  readonly property color urgent: inner ? inner.urgent : Commons.Color.urgent
  readonly property string fontFamily: inner ? inner.fontFamily : Style.font.family

  // Provider bar colors: Antigravity keeps the accent/green bar; Claude uses
  // the active theme's orange and Codex uses the active theme's magenta.
  property color themeOrange: "#ff9a4d"
  property color themeMagenta: "#e07ae8"
  readonly property color agyBarColor: !Qt.colorEqual(Commons.Color.accent, agents.foreground)
    ? Commons.Color.accent : "#86dc5e"
  readonly property color claudeBarColor: themeOrange
  readonly property color codexBarColor: themeMagenta

  FileView {
    id: themeColorsFile
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state")
      + "/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: agents.parseThemeColors(text())
    onFileChanged: reload()
  }

  function parseThemeColors(content) {
    var src = String(content || "")
    var orangeMatch = src.match(/^\s*orange\s*=\s*"(#[0-9a-fA-F]{6})"/m)
    var magentaMatch = src.match(/^\s*magenta\s*=\s*"(#[0-9a-fA-F]{6})"/m)
    themeOrange = orangeMatch ? orangeMatch[1] : "#ff9a4d"
    themeMagenta = magentaMatch ? magentaMatch[1] : "#e07ae8"
  }

  onOpenedChanged: {
    if (opened) {
      Qt.callLater(placeCustomRows)
      listAccounts()
      loadAgyQuota(false)
    } else {
      hoveredEmail = ""
    }
  }

  Connections {
    target: agents.inner ? agents.inner.providerSections : null
    function onItemAdded() { Qt.callLater(agents.placeCustomRows) }
  }

  Connections {
    target: agents.inner
    function onProvidersChanged() { agents.maybeResyncAgy() }
  }

  Component.onCompleted: {
    var component = Qt.createComponent(stockUrl, Component.Asynchronous)
    function ready() {
      if (component.status === Component.Loading) return
      if (component.status !== Component.Ready) {
        console.warn("david.agents: " + stockUrl + " failed to load: " + component.errorString())
        return
      }
      var created = component.createObject(agents, {
        bar: agents.bar, settings: agents.settings, moduleName: agents.moduleName, ipcTarget: "david.agents"
      })
      if (!created) {
        console.warn("david.agents: " + stockUrl + " could not be instantiated: " + component.errorString())
        return
      }
      created.anchors.fill = agents
      created.bar = Qt.binding(function() { return agents.bar })
      created.settings = Qt.binding(function() { return agents.settings })
      agents.inner = created
      Qt.callLater(function() {
        agents.placeCustomRows()
        if (agents.hasProvider("agy")) agents.loadAgyQuota(false)
      })
    }
    if (component.status === Component.Loading) component.statusChanged.connect(ready)
    else ready()
  }

  // ------------------------------------------------------------- accounts

  function listAccounts() {
    if (!listProcess.running) listProcess.running = true
  }

  function useAccount(account) {
    if (account.active || switching) return
    if (account.signInExpired) {
      addAccount()
      return
    }
    accountError = ""
    switching = true
    useProcess.command = [cli, "use", account.email]
    useProcess.running = true
  }

  // Signing in is a browser round trip with prompts, so it gets a terminal.
  function addAccount() {
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-lc",
      'exec "$HOME/bin/claude-account" add; read -rp "Press Enter to close."', "claude-account"])
    agents.close()
  }

  function shortName(email) {
    return String(email || "").split("@")[0]
  }

  function loadQuota(email) {
    if (!opened || !email) return
    hoveredEmail = email
    if (quotaRequestEmail !== "") return
    quotaRequestEmail = email
    quotaProcess.command = [cli, "usage", email, "--json"]
    quotaProcess.running = true
  }

  function quotaLimit(limits, title) {
    for (var i = 0; i < limits.length; i++) {
      var limit = limits[i]
      if (limit.title === title || limit.label === title
          || (title === "Weekly" && String(limit.label || "").indexOf("Weekly (") === 0)) return limit
    }
    return null
  }

  function quotaLine(limits, title, label) {
    var limit = quotaLimit(limits, title)
    if (!limit) return label + ": unavailable"
    var reset = new Date(String(limit.resetsAt || ""))
    if (!isFinite(reset.getTime()) || reset.getTime() <= (inner ? inner.nowMs : Date.now()))
      return label + ": checking after reset"
    var percent = Number(limit.percent)
    if (!isFinite(percent) || percent < 0 || percent > 1)
      return label + ": unavailable"
    return label + ": " + Math.round((1 - percent) * 100) + "% left · resets "
      + Qt.formatDateTime(reset, "MMM d, h:mm AP")
  }

  function accountTooltip(account) {
    var heading = account.email + (account.plan ? " · " + account.plan : "")
    if (account.signInExpired) return heading + "\nSign-in expired. Use + Add to sign in again."
    if (account.active) return heading + "\nCurrent account"
    var snapshot = quotaSnapshots[account.email]
    if (!snapshot) return heading + "\nChecking allowance…"
    var lines = snapshot.limits || []
    var details = quotaLine(lines, "Weekly", "General weekly") + "\n"
      + quotaLine(lines, "Fable Weekly", "Fable weekly")
    if (snapshot.stale) {
      var age = snapshot.fetchedAt > 0 ? Math.max(0, Math.floor(
        ((inner ? inner.nowMs : Date.now()) - snapshot.fetchedAt) / 60000)) : -1
      details += "\nStale" + (age >= 0 ? " · checked " + age + "m ago" : "")
        + " · " + snapshot.status
    }
    return heading + "\n" + details
  }

  // ----------------------------------------------------------- Antigravity

  function providerRecord(providerId) {
    var list = inner ? inner.providers : null
    if (!list) return null
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].providerId === providerId) return list[i]
    }
    return null
  }

  function hasProvider(providerId) {
    return !!providerRecord(providerId)
  }

  function loadAgyQuota(force) {
    if (!hasProvider("agy") || agyProcess.running) return
    agyLastSyncMs = Date.now()
    var cmd = [agyCli, "--json", "--sync-usage"]
    if (force) cmd.push("--force")
    agyProcess.command = cmd
    agyProcess.running = true
  }

  function agyHasRealLimits(snapshot) {
    if (!snapshot || !snapshot.limits) return false
    for (var i = 0; i < snapshot.limits.length; i++) {
      var lim = snapshot.limits[i]
      if (lim && (Number(lim.percent) > 0 || String(lim.resetsAt || "") !== "")) return true
    }
    return false
  }

  function maybeResyncAgy() {
    var provider = providerRecord("agy")
    if (!provider) return
    var limits = provider.limits || []
    var allBlank = limits.length > 0
    for (var i = 0; i < limits.length; i++) {
      if (Number(limits[i].percent) > 0 || String(limits[i].resetsAt || "") !== "") {
        allBlank = false
        break
      }
    }
    // Stock omarchy-agent-usage-agy writes 0% with empty resetsAt because
    // daily-cloudcode-pa no longer returns Gemini buckets. Re-sync agy.json
    // (served from agy-quota's 60s cache) whenever stock clobbers it.
    if (!agyQuota) {
      loadAgyQuota(false)
    } else if (allBlank && agyHasRealLimits(agyQuota) && !agyResyncTimer.running) {
      agyResyncTimer.restart()
    }
  }

  // ------------------------------------------------------- unified quotas

  function limitRemainingFraction(limit) {
    if (!limit) return NaN
    var resetStr = String(limit.resetsAt || "")
    var now = inner ? inner.nowMs : Date.now()
    if (resetStr !== "") {
      var resetMs = new Date(resetStr).getTime()
      if (!isFinite(resetMs) || resetMs <= now) return NaN
    }
    var rem = limit.remainingFraction !== undefined ? Number(limit.remainingFraction) : (1 - Number(limit.percent))
    if (!isFinite(rem) || rem < 0 || rem > 1) return NaN
    return rem
  }

  function limitKey(limit) {
    var title = String(limit && limit.title || "").trim()
    var label = String(limit && limit.label || "").trim()
    if (title !== "") return title
    var lower = label.toLowerCase()
    if (lower.indexOf("720h") >= 0 || lower.indexOf("month") >= 0 || lower.indexOf("30-day") >= 0) return "Monthly"
    if (lower.indexOf("week") >= 0 || lower.indexOf("7-day") >= 0) return "Weekly"
    if (lower.indexOf("session") >= 0 || lower.indexOf("5-hour") >= 0 || lower.indexOf("5h") >= 0) return "Session"
    return label
  }

  function limitDisplayTitle(limit) {
    var title = String(limit && limit.title || "").trim()
    var label = String(limit && limit.label || "").trim()
    var key = limitKey(limit)
    if (key === "Weekly") return "Weekly Limit Remaining"
    if (key === "Session") return "Five Hour Limit Remaining"
    if (key === "Monthly") return "Monthly Limit Remaining"
    if (title !== "") {
      if (title.slice(-8) === " Session") return title.slice(0, -8) + " Five Hour Remaining"
      return title + " Remaining"
    }
    var clean = label.replace(/\s+window$/i, "").trim()
    return clean !== "" ? clean + " Remaining" : "Limit Remaining"
  }

  function limitPercentText(remaining) {
    if (!isFinite(remaining)) return "—"
    var pct = remaining * 100
    if (pct <= 0) return "0%"
    if (pct >= 100) return "100%"
    if (Math.abs(pct - Math.round(pct)) < 0.005) return Math.round(pct) + "%"
    return pct.toFixed(2) + "%"
  }

  function formatHoursMinutes(ms) {
    if (!(ms > 0)) return "now"
    var totalMinutes = Math.floor(ms / 60000)
    var hours = Math.floor(totalMinutes / 60)
    var minutes = totalMinutes % 60
    if (hours > 0) return hours + "h " + minutes + "m"
    return Math.max(1, minutes) + "m"
  }

  function limitRefreshText(limit) {
    if (!limit) return ""
    var resetStr = String(limit.resetsAt || "")
    if (resetStr === "") return "Full allowance"
    var reset = new Date(resetStr)
    var now = inner ? inner.nowMs : Date.now()
    var ms = reset.getTime() - now
    if (!isFinite(ms) || ms <= 0) return "Refreshing…"
    return "Refreshes in " + formatHoursMinutes(ms) + " · " + Qt.formatDateTime(reset, "MMM d, h:mm AP")
  }

  function formatStaleText(stale, fetchedAt, status, hasLimits) {
    if (!stale) return ""
    var cleanStatus = String(status || "").trim()
    if (!hasLimits) return cleanStatus
    var age = fetchedAt > 0 ? Math.max(0, Math.floor(
      ((inner ? inner.nowMs : Date.now()) - fetchedAt) / 60000)) : -1
    var parts = ["Stale"]
    if (age >= 0) parts.push("checked " + age + "m ago")
    if (cleanStatus !== "") parts.push(cleanStatus)
    return parts.join(" · ")
  }

  function limitTooltipText(limit, staleText) {
    var rem = limitRemainingFraction(limit)
    var title = String(limit && (limit.label || limit.title) || "Quota")
    var lines = []
    if (isFinite(rem)) {
      var used = (1 - rem) * 100
      var usedStr = Math.abs(used - Math.round(used)) < 0.005 ? Math.round(used) + "%" : used.toFixed(2) + "%"
      lines.push(title + ": " + limitPercentText(rem) + " left (" + usedStr + " used)")
    } else {
      lines.push(title + ": refreshing")
    }
    var refresh = limitRefreshText(limit)
    if (refresh !== "") lines.push(refresh)
    if (staleText !== "") lines.push(staleText)
    return lines.join("\n")
  }

  // ------------------------------------------------------------- placement

  function providerSection(providerId) {
    var sections = inner ? inner.providerSections : null
    if (!sections) return null
    for (var i = 0; i < sections.count; i++) {
      var section = sections.itemAt(i)
      if (section && section.provider && section.provider.providerId === providerId) return section
    }
    return null
  }

  function claudeSection() {
    return providerSection("claude")
  }

  function agySection() {
    return providerSection("agy")
  }

  function codexSection() {
    return providerSection("codex")
  }

  function placeCustomRows() {
    placeAccountRow()
    placeAgyQuotaRow()
    placeCodexQuotaRow()
  }

  // Inserts a custom component right after a ProviderSection's name row and
  // optionally hides the stock limits Column underneath it.
  function installSectionRow(section, existingRow, rowObjectName, component, hideStockPredicate, warnLabel) {
    if (!section || (existingRow && existingRow.parent === section)) return existingRow
    var siblings = []
    var anchorIndex = -1
    var stockLimitsColumn = null
    for (var i = 0; i < section.children.length; i++) {
      var child = section.children[i]
      siblings.push(child)
      if (anchorIndex < 0 && child.lit !== undefined) {
        anchorIndex = i
      } else if (anchorIndex >= 0 && !stockLimitsColumn
                 && child.objectName !== rowObjectName
                 && child.spacing !== undefined) {
        stockLimitsColumn = child
      }
    }
    if (anchorIndex < 0) {
      console.warn("david.agents: stock " + warnLabel + " section has no name row; custom row not shown")
      return existingRow
    }
    // A Column lays out in child order, and Item.stackAfter is not callable
    // from QML: append the row, then re-append everything that follows the
    // anchor so it lands below the row again.
    if (existingRow) existingRow.destroy()
    var created = component.createObject(section, { ownerSection: section })
    for (var j = anchorIndex + 1; j < siblings.length; j++) {
      siblings[j].parent = agents
      siblings[j].parent = section
    }
    if (stockLimitsColumn && hideStockPredicate) {
      stockLimitsColumn.visible = Qt.binding(function() {
        return !section.multi && section.windows.length > 0 && !hideStockPredicate(section)
      })
    }
    return created
  }

  function placeAccountRow() {
    accountRow = installSectionRow(
      claudeSection(),
      accountRow,
      "accountRow",
      accountRowComponent,
      function(section) {
        return !section.multi && !!section.provider && !!section.provider.limits && section.provider.limits.length > 0
      },
      "Claude"
    )
  }

  function placeAgyQuotaRow() {
    agyQuotaRow = installSectionRow(
      agySection(),
      agyQuotaRow,
      "agyQuotaRow",
      agyQuotaComponent,
      function() { return agents.agyQuotaActive },
      "Antigravity"
    )
  }

  function placeCodexQuotaRow() {
    codexQuotaRow = installSectionRow(
      codexSection(),
      codexQuotaRow,
      "codexQuotaRow",
      codexQuotaComponent,
      function(section) {
        return !section.multi && !!section.provider && !!section.provider.limits && section.provider.limits.length > 0
      },
      "Codex"
    )
  }

  // ------------------------------------------------------------- processes

  Process {
    id: listProcess
    command: [agents.cli, "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          agents.accounts = JSON.parse(text).accounts || []
        } catch (e) {
          agents.accounts = []
        }
      }
    }
  }

  Process {
    id: useProcess
    onExited: function(exitCode) {
      agents.switching = false
      agents.listAccounts()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: agents.accountError = text.trim()
    }
  }

  Process {
    id: quotaProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var requested = agents.quotaRequestEmail
        try {
          var snapshot = JSON.parse(text)
          if (snapshot.email !== requested) throw new Error("wrong account")
          var next = Object.assign({}, agents.quotaSnapshots)
          next[snapshot.email] = snapshot
          agents.quotaSnapshots = next
        } catch (e) {
          var failed = Object.assign({}, agents.quotaSnapshots)
          failed[requested] = { limits: [], stale: true, status: "Allowance check failed." }
          agents.quotaSnapshots = failed
        }
        agents.quotaRequestEmail = ""
        if (agents.hoveredEmail !== "" && agents.hoveredEmail !== requested)
          Qt.callLater(function() { agents.loadQuota(agents.hoveredEmail) })
      }
    }
  }

  Process {
    id: agyProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var snapshot = JSON.parse(text)
          if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.limits))
            throw new Error("invalid agy quota snapshot")
          agents.agyQuota = snapshot
          Qt.callLater(agents.placeAgyQuotaRow)
        } catch (e) {
          if (!agents.agyQuota) {
            agents.agyQuota = { limits: [], stale: true, fetchedAt: 0, status: "Antigravity quota check failed." }
          }
        }
      }
    }
  }

  Timer {
    interval: 60000
    repeat: true
    running: agents.opened && agents.hoveredEmail !== ""
    onTriggered: agents.loadQuota(agents.hoveredEmail)
  }

  Timer {
    id: agyResyncTimer
    interval: 1000
    repeat: false
    onTriggered: agents.loadAgyQuota(false)
  }

  Timer {
    interval: agents.opened ? 60000 : 300000
    repeat: true
    running: !!agents.inner && agents.hasProvider("agy")
    onTriggered: agents.loadAgyQuota(false)
  }

  // ------------------------------------------------------------ components

  component QuotaBars: Column {
    id: quotaList
    property string providerPrefix: "quota"
    property var limits: []
    property color barColor: agents.agyBarColor
    property string staleText: ""
    property string footerNote: ""
    spacing: Style.space(12)

    Repeater {
      model: quotaList.limits || []

      Column {
        id: limitBlock
        required property var modelData
        readonly property string key: agents.limitKey(modelData)
        objectName: quotaList.providerPrefix + "Limit:" + key
        width: quotaList.width
        spacing: Style.space(5)

        readonly property real remaining: agents.limitRemainingFraction(modelData)
        readonly property bool available: isFinite(remaining)
        readonly property bool alarming: available && remaining <= 0.1

        HoverHandler { id: limitHover }

        PanelToolTip {
          visible: limitHover.hovered
          text: agents.limitTooltipText(limitBlock.modelData, quotaList.staleText)
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(limitTitle.implicitHeight, limitPct.implicitHeight)

          Text {
            id: limitTitle
            objectName: quotaList.providerPrefix + "LimitTitle:" + limitBlock.key
            anchors.left: parent.left
            anchors.right: limitPct.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: agents.limitDisplayTitle(limitBlock.modelData)
            color: agents.foreground
            font.family: agents.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: limitPct
            objectName: quotaList.providerPrefix + "LimitPct:" + limitBlock.key
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: agents.limitPercentText(limitBlock.remaining)
            color: limitBlock.alarming ? agents.urgent : agents.foreground
            font.family: agents.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        Item {
          id: meter
          objectName: quotaList.providerPrefix + "Meter:" + limitBlock.key
          width: parent.width
          height: Math.max(Style.space(6), Math.round(Style.spacing.controlHeight * 0.2))

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: agents.inner ? agents.inner.track : Style.selectedFillFor(agents.foreground, Commons.Color.accent)
          }

          Rectangle {
            objectName: quotaList.providerPrefix + "MeterFill:" + limitBlock.key
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: height / 2
            width: parent.width * (limitBlock.available ? limitBlock.remaining : 0)
            color: limitBlock.alarming ? agents.urgent : quotaList.barColor
          }
        }

        Text {
          objectName: quotaList.providerPrefix + "LimitReset:" + limitBlock.key
          width: parent.width
          textFormat: Text.PlainText
          text: agents.limitRefreshText(limitBlock.modelData)
          color: agents.dim
          font.family: agents.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Text {
      objectName: quotaList.providerPrefix + "FooterNote"
      visible: text !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: quotaList.footerNote
      color: agents.dim
      font.family: agents.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      objectName: quotaList.providerPrefix + "QuotaStatus"
      visible: text !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: quotaList.staleText
      color: (quotaList.limits && quotaList.limits.length > 0) ? agents.dim : agents.urgent
      font.family: agents.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Component {
    id: agyQuotaComponent

    QuotaBars {
      property var ownerSection: null
      objectName: "agyQuotaRow"
      providerPrefix: "agy"
      visible: agents.agyQuotaActive
      width: parent ? parent.width : 0
      limits: agents.agyQuota && agents.agyQuota.limits ? agents.agyQuota.limits : []
      barColor: agents.agyBarColor
      staleText: agents.agyQuota
        ? agents.formatStaleText(
            agents.agyQuota.stale === true,
            Number(agents.agyQuota.fetchedAt || 0),
            agents.agyQuota.status,
            limits.length > 0)
        : ""
    }
  }

  Component {
    id: codexQuotaComponent

    QuotaBars {
      property var ownerSection: null
      readonly property var provider: ownerSection ? ownerSection.provider : null
      objectName: "codexQuotaRow"
      providerPrefix: "codex"
      visible: !!provider && !ownerSection.multi && limits.length > 0
      width: parent ? parent.width : 0
      limits: provider && provider.limits ? provider.limits : []
      barColor: agents.codexBarColor
      staleText: provider
        ? agents.formatStaleText(
            provider.limitsStale === true,
            Number(provider.limitsFetchedAt || 0),
            provider.usageStatusText,
            limits.length > 0)
        : ""
      footerNote: provider && agents.inner ? agents.inner.resetCreditsText(provider.resetCredits) : ""
    }
  }

  Component {
    id: accountRowComponent

    Column {
      id: claudeRow
      property var ownerSection: null
      readonly property var provider: ownerSection ? ownerSection.provider : null
      readonly property var providerLimits: provider && provider.limits ? provider.limits : []
      objectName: "accountRow"
      visible: agents.accounts.length > 0 || (providerLimits.length > 0 && (!ownerSection || !ownerSection.multi))
      width: parent ? parent.width : 0
      spacing: Style.space(12)

      Column {
        visible: agents.accounts.length > 0
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: agents.switching ? "ACCOUNT · SWITCHING…" : "ACCOUNT"
          foreground: agents.foreground
          fontFamily: agents.fontFamily
        }

        Row {
          id: accountButtons
          width: parent.width
          spacing: Style.spacing.md
          readonly property int count: agents.accounts.length + 1
          readonly property real cellWidth: (width - spacing * (count - 1)) / count

          Repeater {
            model: agents.accounts

            Button {
              required property var modelData
              objectName: "accountButton:" + modelData.email
              width: accountButtons.cellWidth
              text: agents.shortName(modelData.email) + (modelData.signInExpired ? " ⟳" : "")
              tooltipText: agents.accountTooltip(modelData)
              selected: modelData.active
              bordered: true
              foreground: agents.foreground
              fontFamily: agents.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onHovered: function(isHovered) {
                if (isHovered && !modelData.active && !modelData.signInExpired)
                  agents.loadQuota(modelData.email)
                else if (!isHovered && agents.hoveredEmail === modelData.email)
                  agents.hoveredEmail = ""
              }
              onClicked: agents.useAccount(modelData)
            }
          }

          Button {
            width: accountButtons.cellWidth
            text: "+ Add"
            tooltipText: "Sign in another Claude account"
            bordered: true
            foreground: agents.foreground
            fontFamily: agents.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: agents.addAccount()
          }
        }
      }

      QuotaBars {
        visible: claudeRow.providerLimits.length > 0 && (!claudeRow.ownerSection || !claudeRow.ownerSection.multi)
        width: parent.width
        providerPrefix: "claude"
        limits: claudeRow.providerLimits
        barColor: agents.claudeBarColor
        staleText: claudeRow.provider
          ? agents.formatStaleText(
              claudeRow.provider.limitsStale === true,
              Number(claudeRow.provider.limitsFetchedAt || 0),
              claudeRow.provider.usageStatusText,
              claudeRow.providerLimits.length > 0)
          : ""
      }

      Text {
        visible: agents.accountError !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: agents.accountError
        color: agents.urgent
        font.family: agents.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
