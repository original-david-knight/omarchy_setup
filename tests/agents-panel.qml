import QtQuick
import Quickshell
import "Agents" as Agents

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  property var staleSection: null
  property var staleAgySection: null
  property bool screenshotDone: false
  property bool agyScreenshotDone: false

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
          var agyRow = panel.agyQuotaRow
          if (!row || !row.visible || panel.accounts.length !== 2) return
          if (!agyRow || !agyRow.visible || !panel.agyQuota || panel.agyQuota.limits.length !== 2) return
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

          // Antigravity section checks.
          test.check(agyRow.parent.provider && agyRow.parent.provider.providerId === "agy",
                     "Antigravity quota row is not in the Antigravity section")
          var agySiblings = agyRow.parent.children
          var agyAt = -1
          for (var a = 0; a < agySiblings.length; a++) if (agySiblings[a] === agyRow) agyAt = a
          test.check(agyAt > 0 && agySiblings[agyAt - 1].lit !== undefined,
                     "Antigravity quota row does not follow Antigravity's name row")
          var hiddenStock = false
          for (var h = agyAt + 1; h < agySiblings.length; h++) {
            if (agySiblings[h].spacing !== undefined && !agySiblings[h].visible) hiddenStock = true
          }
          test.check(hiddenStock, "Broken stock Antigravity limits column was not hidden")
          test.check(test.named(agyRow, "agyLimitPct:Weekly").text === "82.42%",
                     "Antigravity weekly remaining percent is wrong: " + test.named(agyRow, "agyLimitPct:Weekly").text)
          test.check(test.named(agyRow, "agyLimitPct:Session").text === "98.36%",
                     "Antigravity 5-hour remaining percent is wrong: " + test.named(agyRow, "agyLimitPct:Session").text)
          test.check(test.named(agyRow, "agyLimitReset:Weekly").text.indexOf("Refreshes in 126h") === 0,
                     "Antigravity weekly reset text is wrong: " + test.named(agyRow, "agyLimitReset:Weekly").text)
          test.check(test.named(agyRow, "agyLimitReset:Session").text.indexOf("Refreshes in 4h") === 0,
                     "Antigravity 5-hour reset text is wrong: " + test.named(agyRow, "agyLimitReset:Session").text)
          var agyWeeklyMeter = test.named(agyRow, "agyMeter:Weekly")
          var agyWeeklyFill = test.named(agyRow, "agyMeterFill:Weekly")
          test.check(agyWeeklyMeter && agyWeeklyFill && agyWeeklyMeter.width > 0,
                     "Antigravity weekly bar is not visible")
          test.check(Math.abs(agyWeeklyFill.width / agyWeeklyMeter.width - 0.8242) < 0.01,
                     "Antigravity weekly bar does not match 82.42% remaining")
          var agySessionMeter = test.named(agyRow, "agyMeter:Session")
          var agySessionFill = test.named(agyRow, "agyMeterFill:Session")
          test.check(Math.abs(agySessionFill.width / agySessionMeter.width - 0.9836) < 0.01,
                     "Antigravity 5-hour bar does not match 98.36% remaining")
          if (Quickshell.env("AGENTS_TEST_SEPARATE_POPUP") === "1") {
            test.check(row.QsWindow.window !== window, "Account row stayed in the bar window")
            test.check(agyRow.QsWindow.window !== window, "Antigravity row stayed in the bar window")
          }
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
          var agyShot = Quickshell.env("AGENTS_TEST_AGY_SCREENSHOT") || ""
          test.screenshotDone = (screenshot === "")
          test.agyScreenshotDone = (agyShot === "")
          if (screenshot !== "") {
            panel.accountRow.grabToImage(function(result) {
              test.screenshotDone = result.saveToFile(screenshot)
            })
          }
          if (agyShot !== "") {
            panel.agyQuotaRow.parent.grabToImage(function(result) {
              test.agyScreenshotDone = result.saveToFile(agyShot)
            })
          }
          test.step = (screenshot !== "" || agyShot !== "") ? 3 : 4
        } else if (test.step === 3) {
          if (!test.screenshotDone || !test.agyScreenshotDone) return
          test.step = 4
        } else if (test.step === 4) {
          panel.useAccount(panel.accounts[1])
          test.step = 5
        } else if (test.step === 5) {
          if (panel.switching || !panel.accounts[1].active) return
          test.check(!panel.accounts[0].active, "Old account still marked active")
          test.staleSection = panel.accountRow.parent
          test.staleAgySection = panel.agyQuotaRow.parent
          // The stock panel drops every agent section while adding one and
          // builds them anew afterwards.
          panel.inner.addStage = "pick"
          test.step = 6
        } else if (test.step === 6) {
          if ((panel.accountRow && panel.accountRow.visible) || (panel.agyQuotaRow && panel.agyQuotaRow.visible)) return
          panel.inner.addStage = ""
          test.step = 7
        } else if (test.step === 7) {
          var again = panel.accountRow
          var agyAgain = panel.agyQuotaRow
          if (!again || !again.visible || !agyAgain || !agyAgain.visible) return
          test.check(again.parent !== test.staleSection && again.parent.provider.providerId === "claude",
                     "Account row was not placed in the rebuilt Claude section")
          test.check(agyAgain.parent !== test.staleAgySection && agyAgain.parent.provider.providerId === "agy",
                     "Antigravity quota row was not placed in the rebuilt Antigravity section")
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
