import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// david.agents: the stock Agents panel plus a Claude Code account switch.
//
// Copying the stock panel would freeze 1700 lines at one Omarchy release, so
// this wrapper instantiates the installed Panel.qml by URL, exactly as
// omarchy-shell would (the david.bar technique), and adds a single row. The
// row is created inside the stock panel's Claude section, just below its
// name, whenever that section is built. Every switch goes through
// ~/bin/claude-account, which owns the credential files; see
// docs/claude-accounts.md.
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
// whenever the agent list changes, so the row is placed again each time. Tab from
// this panel to its bar neighbors does not work, because the stock panel
// asks the bar for its own slot, which belongs to this wrapper.
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
  property var accounts: []
  property string accountError: ""
  property bool switching: false
  property var quotaSnapshots: ({})
  property string quotaRequestEmail: ""
  property string hoveredEmail: ""
  readonly property color foreground: inner ? inner.foreground : Commons.Color.foreground
  readonly property color urgent: inner ? inner.urgent : Commons.Color.urgent
  readonly property string fontFamily: inner ? inner.fontFamily : Style.font.family

  onOpenedChanged: {
    if (opened) {
      Qt.callLater(placeAccountRow)
      listAccounts()
    } else {
      hoveredEmail = ""
    }
  }

  Connections {
    target: agents.inner ? agents.inner.providerSections : null
    function onItemAdded() { Qt.callLater(agents.placeAccountRow) }
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
    }
    if (component.status === Component.Loading) component.statusChanged.connect(ready)
    else ready()
  }

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

  function activeQuotaLine(title, label) {
    var section = claudeSection()
    var provider = section ? section.provider : null
    var limits = provider && provider.limits ? provider.limits : []
    return quotaLine(limits, title, label) + (provider && provider.limitsStale ? " · stale" : "")
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

  // ------------------------------------------------------------- placement

  function claudeSection() {
    var sections = inner ? inner.providerSections : null
    if (!sections) return null
    for (var i = 0; i < sections.count; i++) {
      var section = sections.itemAt(i)
      if (section && section.provider && section.provider.providerId === "claude") return section
    }
    return null
  }

  function placeAccountRow() {
    var section = claudeSection()
    if (!section || (accountRow && accountRow.parent === section)) return
    var siblings = []
    var anchorIndex = -1
    for (var i = 0; i < section.children.length; i++) {
      siblings.push(section.children[i])
      if (anchorIndex < 0 && siblings[i].lit !== undefined) anchorIndex = i
    }
    if (anchorIndex < 0) {
      console.warn("david.agents: stock Claude section has no name row; account switch not shown")
      return
    }
    // A Column lays out in child order, and Item.stackAfter is not callable
    // from QML: append the row, then re-append everything that follows the
    // anchor so it lands below the row again.
    if (accountRow) accountRow.destroy()
    accountRow = accountRowComponent.createObject(section)
    for (var j = anchorIndex + 1; j < siblings.length; j++) {
      siblings[j].parent = agents
      siblings[j].parent = section
    }
  }

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

  Timer {
    interval: 60000
    repeat: true
    running: agents.opened && agents.hoveredEmail !== ""
    onTriggered: agents.loadQuota(agents.hoveredEmail)
  }

  Component {
    id: accountRowComponent

    Column {
      objectName: "accountRow"
      visible: agents.accounts.length > 0
      width: parent ? parent.width : 0
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

      Text {
        objectName: "generalAllowanceText"
        width: parent.width
        textFormat: Text.PlainText
        text: agents.activeQuotaLine("Weekly", "General weekly")
        color: agents.foreground
        font.family: agents.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        objectName: "fableAllowanceText"
        width: parent.width
        textFormat: Text.PlainText
        text: agents.activeQuotaLine("Fable Weekly", "Fable weekly")
        color: agents.foreground
        font.family: agents.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item {
        id: fableMeter
        objectName: "fableMeter"
        width: parent.width
        height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
        readonly property var section: agents.claudeSection()
        readonly property var limits: section && section.provider && section.provider.limits ? section.provider.limits : []
        readonly property var limit: agents.quotaLimit(limits, "Fable Weekly")
        readonly property real resetMs: limit ? new Date(String(limit.resetsAt || "")).getTime() : NaN
        readonly property real used: limit ? Number(limit.percent) : NaN
        readonly property bool available: isFinite(resetMs) && resetMs > (agents.inner ? agents.inner.nowMs : Date.now())
          && isFinite(used) && used >= 0 && used <= 1
        readonly property color fillColor: !Qt.colorEqual(Commons.Color.accent, agents.foreground)
          ? Commons.Color.accent : (!Qt.colorEqual(agents.urgent, agents.foreground) ? agents.urgent : "#a78bfa")

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: agents.inner ? agents.inner.track : Style.selectedFillFor(agents.foreground, Commons.Color.accent)
        }

        Rectangle {
          objectName: "fableMeterFill"
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          radius: height / 2
          width: parent.width * (fableMeter.available ? fableMeter.used : 0)
          color: fableMeter.fillColor
        }
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
