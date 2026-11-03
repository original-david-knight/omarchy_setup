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
// row is declared here and moved into the stock panel's content column the
// first time the panel opens, just below the subscription switch, and only
// shows while the Claude tab is selected. Every switch goes through
// ~/bin/claude-account, which owns the credential files; see
// docs/claude-accounts.md.
//
// Extending the stock panel as a QML type instead does not work: the shell
// rewrites its own files to qs:// URLs, and the stock panel's inline
// components ("DayRow is not a type") fail to resolve when it is a base type.
//
// Relied-on stock facts, checked at runtime and logged when missing: the
// content column holds a PanelHero (the only item with `iconComponent`), and
// the subscription switch is the Row after it carrying `cellWidth`. Tab from
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
  readonly property bool claudeSelected: !!inner && !!inner.provider && inner.provider.providerId === "claude"
  readonly property color foreground: inner ? inner.foreground : Commons.Color.foreground
  readonly property color urgent: inner ? inner.urgent : Commons.Color.urgent
  readonly property string fontFamily: inner ? inner.fontFamily : Style.font.family

  onOpenedChanged: if (opened) {
    placeAccountRow()
    listAccounts()
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

  // ------------------------------------------------------------- placement

  function findHero(object, depth) {
    if (!object || depth > 12) return null
    if (object.iconComponent !== undefined && object.title !== undefined) return object
    // An Item's data covers its children; a window only exposes contentItem.
    var lists = [object.data || object.children]
    if (object.contentItem) lists.push([object.contentItem])
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l]
      if (!list) continue
      for (var i = 0; i < list.length; i++) {
        if (list[i] === accountRow) continue
        var found = findHero(list[i], depth + 1)
        if (found) return found
      }
    }
    return null
  }

  function placeAccountRow() {
    if (accountRow.placed) return
    var hero = findHero(inner, 0)
    if (!hero || !hero.parent) {
      console.warn("david.agents: stock agents panel has no hero; account switch not shown")
      return
    }
    var column = hero.parent
    var siblings = []
    var anchorIndex = 0
    for (var i = 0; i < column.children.length; i++) {
      siblings.push(column.children[i])
      if (siblings[i] === hero || siblings[i].cellWidth !== undefined) anchorIndex = i
    }
    // A Column lays out in child order, and Item.stackAfter is not callable
    // from QML: append the row, then re-append everything that follows the
    // anchor so it lands below the row again.
    accountRow.parent = column
    for (var j = anchorIndex + 1; j < siblings.length; j++) {
      siblings[j].parent = agents
      siblings[j].parent = column
    }
    accountRow.placed = true
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

  Column {
    id: accountRow
    objectName: "accountRow"
    property bool placed: false
    visible: placed && agents.claudeSelected && agents.accounts.length > 0
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
          width: accountButtons.cellWidth
          text: agents.shortName(modelData.email) + (modelData.signInExpired ? " ⟳" : "")
          tooltipText: modelData.email + (modelData.plan ? " · " + modelData.plan : "")
            + (modelData.signInExpired ? " · sign-in expired, click to sign in again" : "")
          selected: modelData.active
          bordered: true
          foreground: agents.foreground
          fontFamily: agents.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
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
      visible: agents.accountError !== ""
      width: parent.width
      text: agents.accountError
      color: agents.urgent
      font.family: agents.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
