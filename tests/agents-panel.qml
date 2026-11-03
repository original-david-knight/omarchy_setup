import QtQuick
import Quickshell
import "Agents" as Agents

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0

  function check(condition, message) { if (!condition) throw new Error(message) }
  function named(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = named(item.children[i], name)
      if (found) return found
    }
    return null
  }

  Window {
    id: window
    visible: true
    width: 480
    height: 900
    Agents.Panel { id: panel; x: 24; y: 24 }
  }

  Timer {
    running: true
    repeat: true
    interval: 30
    onTriggered: {
      try {
        test.check(++test.ticks < 300, "Agents test timed out at step " + test.step)
        if (test.step === 0) {
          if (!panel.inner || panel.inner.providers.length === 0) return
          test.check(panel.inner.provider.providerId === "claude", "Claude was not the selected provider")
          panel.open()
          test.step = 1
        } else if (test.step === 1) {
          var row = test.named(panel, "accountRow")
          if (!row || !row.visible || panel.accounts.length !== 2) return
          var hero = null
          for (var i = 0; i < row.parent.children.length; i++)
            if (row.parent.children[i].iconComponent !== undefined) hero = row.parent.children[i]
          test.check(hero !== null, "Account row was not moved next to the stock hero")
          test.check(row.y > hero.y, "Account row sits above the hero")
          var siblings = row.parent.children
          var at = -1
          for (var s = 0; s < siblings.length; s++) if (siblings[s] === row) at = s
          test.check(at > 0 && siblings[at - 1].cellWidth !== undefined,
                     "Account row does not follow the subscription switch")
          test.check(at < siblings.length - 1, "Stock sections did not stay below the account row")
          panel.useAccount(panel.accounts[1])
          test.step = 2
        } else if (test.step === 2) {
          if (panel.switching || !panel.accounts[1].active) return
          test.check(!panel.accounts[0].active, "Old account still marked active")
          panel.inner.selectProvider(1)
          test.step = 3
        } else if (test.step === 3) {
          if (panel.claudeSelected) return
          test.check(!test.named(panel, "accountRow").visible, "Account row shown on a non-Claude tab")
          console.log("AGENTS PANEL TEST PASSED")
          Qt.quit()
        }
      } catch (e) {
        console.error("AGENTS PANEL TEST FAILED: " + e.message)
        Qt.quit()
      }
    }
  }
}
