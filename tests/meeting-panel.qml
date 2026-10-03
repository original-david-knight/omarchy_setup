import QtQuick
import Quickshell
import "Meeting" as Meeting

ShellRoot {
  id: test
  readonly property bool laptop: Quickshell.env("MEETING_TEST_LAPTOP") === "1"
  property int step: 0
  property int ticks: 0
  property int actionTick: 0
  property real clock: Date.now()

  function check(condition, message) { if (!condition) throw new Error(message) }
  function named(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = named(item.children[i], name)
      if (found) return found
    }
    return null
  }
  function event(id, start, end) {
    return { id: id, title: id, starts_at: new Date(start).toISOString(),
             ends_at: new Date(end).toISOString(), calendar_name: "Work", location: "" }
  }
  function finish() {
    var preview = Quickshell.env("MEETING_PREVIEW_PATH")
    if (!preview) { console.log("MEETING PANEL TEST PASSED"); Qt.quit(); return }
    window.contentItem.grabToImage(function(image) {
      if (!image.saveToFile(preview)) console.error("MEETING PANEL PREVIEW FAILED")
      else console.log("MEETING PANEL PREVIEW SAVED: " + preview)
      console.log("MEETING PANEL TEST PASSED")
      Qt.quit()
    })
  }

  Window {
    id: window
    visible: true
    width: 720
    height: 1000
    color: "#202326"
    Rectangle { anchors.fill: parent; color: window.color }
    Meeting.Panel { id: panel; x: 24; y: 24; settings: ({ litra: !test.laptop }) }
  }

  Timer {
    running: true
    repeat: true
    interval: 30
    onTriggered: {
      try {
        test.check(++test.ticks < 300, "Panel test timed out at step " + test.step)
        if (test.laptop) {
          if (panel.calendarData.status !== "ready" || panel.recorderState !== "off") return
          if (test.step === 0) {
            panel.open()
            panel.readLight()
            panel.setLight("power", "on")
            test.check(!test.named(panel, "lightPower").visible, "Laptop showed light power")
            test.check(!test.named(panel, "lightBrightness").visible, "Laptop showed brightness")
            test.check(!test.named(panel, "lightTemperature").visible, "Laptop showed temperature")
            panel.moveCursor(0, 1)
            test.check(panel.cursorRow === "refresh", "Laptop keyboard focused hidden light controls")
            panel.moveCursor(0, 1)
            test.check(panel.cursorRow === "recorder", "Laptop keyboard did not wrap to recorder")
            test.actionTick = test.ticks
            test.step++
          } else if (test.ticks >= test.actionTick + 10) {
            test.check(!panel.lightBusy && panel.lightData.status === "loading", "Laptop queried the light")
            test.check(panel.calendarCurrent, "Laptop calendar unavailable")
            console.log("MEETING PANEL TEST PASSED")
            Qt.quit()
          }
          return
        }
        if (test.step === 0 && panel.calendarData.status === "ready" && panel.lightReady && panel.recorderState === "off") {
          test.check(panel.calendarCurrent, "Today's calendar was not accepted")
          test.check(panel.lightData.power === false, "Initial light readback was wrong")
          panel.open()
          test.check(test.named(panel, "lightPower") !== null, "Power control is missing")
          test.step++
        } else if (test.step === 1 && panel.lightReady && !panel.lightBusy) {
          test.check(test.named(panel, "lightPower").enabled, "Power control stayed disabled")
          test.named(panel, "lightPower").clicked()
          test.step++
        } else if (test.step === 2 && panel.lightReady && panel.lightData.power === true && !panel.lightBusy) {
          test.named(panel, "lightBrightness").released(129)
          test.step++
        } else if (test.step === 3 && panel.lightData.brightness === 129 && !panel.lightBusy) {
          test.named(panel, "lightTemperature").released(4254)
          test.step++
        } else if (test.step === 4 && panel.lightData.temperature === 4300 && !panel.lightBusy) {
          panel.nowMs = test.clock
          panel.calendarData = { status: "ready", date: panel.localDate(test.clock), events: [
            test.event("Next", test.clock + 600000, test.clock + 1800000),
            test.event("Current", test.clock - 60000, test.clock + 300000)] }
          test.check(panel.nextMeeting.title === "Current" && panel.meetingOngoing, "Ongoing meeting not selected")
          test.check(panel.meetingTime.indexOf("In progress") === 0, "Ongoing meeting countdown is wrong")
          panel.nowMs = test.clock + 300001
          test.check(panel.nextMeeting.title === "Next", "Next meeting not selected after current ended")
          panel.nowMs = test.clock + 1800001
          test.check(panel.nextMeeting === null, "Ended meeting was retained")
          test.check(panel.calendarMessage.indexOf("No more work meetings") === 0, "Today empty state is wrong")
          panel.calendarData = Object.assign({}, panel.calendarData, { warning: "Calendar sync failed" })
          test.check(panel.calendarMessage === "Next work meeting unavailable",
                     "A failed sync was presented as an empty work calendar")
          panel.nowMs = test.clock + 172800000
          test.check(!panel.calendarCurrent && panel.nextMeeting === null, "Prior-day events survived rollover")
          panel.calendarData = { status: "error", message: "Calendar unavailable", events: [] }
          test.check(panel.lightReady, "Calendar error disabled the light")
          panel.consumeRecorder('{"state":"idle"}')
          panel.recorderAction("start")
          test.check(panel.pendingRecorderAction === "start" && panel.recorderState === "idle",
                     "Start changed state without watch confirmation")
          test.actionTick = test.ticks
          test.step++
        } else if (test.step === 5 && panel.pendingRecorderAction === "start" && test.ticks >= test.actionTick + 5) {
          panel.consumeRecorder('{"state":"recording","elapsed":8}')
          test.check(panel.pendingRecorderAction === "" && panel.recorderState === "recording",
                     "Watch did not confirm start")
          panel.recorderAction("pause")
          test.check(panel.pendingRecorderAction === "pause" && panel.recorderState === "recording",
                     "Pause changed state without watch confirmation")
          test.actionTick = test.ticks
          test.step++
        } else if (test.step === 6 && panel.pendingRecorderAction === "pause" && test.ticks >= test.actionTick + 5) {
          panel.consumeRecorder('{"state":"paused","elapsed":8}')
          test.check(panel.pendingRecorderAction === "" && panel.recorderState === "paused",
                     "Watch did not confirm pause")
          panel.recorderAction("stop")
          test.check(panel.pendingRecorderAction === "stop" && panel.recorderState === "paused",
                     "Stop changed state without watch confirmation")
          test.actionTick = test.ticks
          test.step++
        } else if (test.step === 7 && panel.pendingRecorderAction === "stop" && test.ticks >= test.actionTick + 5) {
          panel.consumeRecorder('{"state":"transcribing","progress":0.4}')
          test.check(panel.pendingRecorderAction === "" && panel.recorderState === "transcribing",
                     "Watch did not confirm stop")
          panel.lightData = { status: "error", message: "Light unavailable" }
          test.check(panel.recorderState === "transcribing" && panel.calendarData.status === "error",
                     "Light failure changed another domain")
          panel.consumeRecorder('{bad json')
          test.check(panel.recorderWatchError !== "" && panel.recorderState === "unknown",
                     "Malformed watch state did not surface an error")
          panel.consumeRecorder('{"state":"idle"}')
          test.check(panel.recorderWatchError === "" && panel.recorderState === "idle",
                     "Valid watch state did not clear the error")
          panel.nowMs = test.clock
          panel.calendarData = { status: "ready", date: panel.localDate(test.clock),
            events: [test.event("Design review", test.clock + 900000, test.clock + 2700000)] }
          panel.lightData = { status: "ready", power: true, brightness: 129, temperature: 4300 }
          test.check(panel.nextMeeting.title === "Design review" && panel.lightReady,
                     "Preview state was not ready")
          test.finish()
        }
      } catch (error) {
        console.error("MEETING PANEL TEST FAILED: " + error)
        Qt.quit()
      }
    }
  }
}
