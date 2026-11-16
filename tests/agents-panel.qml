import QtQuick
import Quickshell
import "Agents" as Agents

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  property var staleSection: null
  property bool screenshotDone: false

  function check(condition, message) { if (!condition) throw new Error(message) }
  function named(item, name) {
    if (!item) return null
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
          panel.open()
          test.step = 1
        } else if (test.step === 1) {
          var row = panel.accountRow
          if (!row || !row.visible || panel.accounts.length !== 2) return
          test.check(row.parent.provider && row.parent.provider.providerId === "claude",
                     "Account row is not in the Claude section")
          var siblings = row.parent.children
          var at = -1
          for (var s = 0; s < siblings.length; s++) if (siblings[s] === row) at = s
          test.check(at > 0 && siblings[at - 1].lit !== undefined, "Account row does not follow Claude's name row")
          test.check(at < siblings.length - 1, "Claude's limits did not stay below the account row")
          row.parent.forceLayout()
          test.check(row.y > siblings[at - 1].y, "Account row sits above Claude's name row")
          test.check(test.named(row, "generalAllowanceText").text.indexOf("47% left") >= 0,
                     "Active general allowance is not visible")
          test.check(test.named(row, "fableAllowanceText").text.indexOf("4% left") >= 0,
                     "Active Fable allowance is not visible")
          var meter = test.named(row, "fableMeter")
          var fill = test.named(row, "fableMeterFill")
          test.check(meter && fill && meter.visible && fill.visible && meter.width > 0,
                     "Fable quota bar is not visible")
          test.check(Math.abs(fill.width / meter.width - 0.96) < 0.001,
                     "Fable bar does not show 96% used")
          test.check(!Qt.colorEqual(fill.color, panel.foreground),
                     "Fable bar uses the general quota color")
          if (Quickshell.env("AGENTS_TEST_SEPARATE_POPUP") === "1")
            test.check(row.QsWindow.window !== window, "Account row stayed in the bar window")
          test.named(row, "accountButton:b@example.com").hovered(true)
          test.step = 2
        } else if (test.step === 2) {
          var button = test.named(panel.accountRow, "accountButton:b@example.com")
          if (!panel.quotaSnapshots["b@example.com"]) return
          test.check(button.tooltipText.indexOf("General weekly: 80% left") >= 0,
                     "Other account's general quota is missing on hover")
          test.check(button.tooltipText.indexOf("Fable weekly: 40% left") >= 0,
                     "Other account's Fable quota is missing on hover")
          test.check(panel.accounts[0].active && !panel.accounts[1].active,
                     "Hover changed the active account")
          var screenshot = Quickshell.env("AGENTS_TEST_SCREENSHOT") || ""
          if (screenshot !== "") {
            panel.accountRow.grabToImage(function(result) {
              test.screenshotDone = result.saveToFile(screenshot)
            })
            test.step = 3
          } else {
            test.step = 4
          }
        } else if (test.step === 3) {
          if (!test.screenshotDone) return
          test.step = 4
        } else if (test.step === 4) {
          panel.useAccount(panel.accounts[1])
          test.step = 5
        } else if (test.step === 5) {
          if (panel.switching || !panel.accounts[1].active) return
          test.check(!panel.accounts[0].active, "Old account still marked active")
          test.staleSection = panel.accountRow.parent
          // The stock panel drops every agent section while adding one and
          // builds them anew afterwards.
          panel.inner.addStage = "pick"
          test.step = 6
        } else if (test.step === 6) {
          if (panel.accountRow && panel.accountRow.visible) return
          panel.inner.addStage = ""
          test.step = 7
        } else if (test.step === 7) {
          var again = panel.accountRow
          if (!again || !again.visible) return
          test.check(again.parent !== test.staleSection && again.parent.provider.providerId === "claude",
                     "Account row was not placed in the rebuilt Claude section")
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
