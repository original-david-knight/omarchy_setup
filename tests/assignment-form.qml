import QtQuick
import Quickshell
import QtTest
import "Plugins/david.tasks" as Tasks

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  property int assignments: 0
  function check(value, message) { if (!value) throw new Error(message) }
  function control(item, property, value) {
    if (item[property] === value) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = control(item.children[i], property, value)
      if (found) return found
    }
    return null
  }
  function dropdown(item, label) { return control(item, "label", label) }
  function choose(label, value) {
    var control = dropdown(form, label)
    test.check(control !== null, "Missing dropdown: " + label)
    var index = control.options.findIndex(function(option) { return option.value === value })
    test.check(index >= 0, "Missing option: " + value)
    control.open()
    // Exercise the real dropdown's keyboard selection, including its writes
    // to value. Setting form.agent directly misses broken value bindings.
    for (var i = 0; i < control.options.length; i++) events.keyClick(Qt.Key_Up, Qt.NoModifier, 1)
    for (var j = 0; j < index; j++) events.keyClick(Qt.Key_Down, Qt.NoModifier, 1)
    events.keyClick(Qt.Key_Return, Qt.NoModifier, 1)
    test.check(control.value === value, "Dropdown did not select " + value)
  }
  TestEvent { id: events }
  Window {
    visible: true
    width: 460
    height: 680
    Tasks.AssignAgent {
      id: form
      anchors.fill: parent
      onAssigned: test.assignments++
    }
  }
  Timer {
    running: true
    repeat: true
    interval: 30
    onTriggered: {
      try {
        test.check(++test.ticks < 300, "Assignment test timed out at step " + test.step)
        if (test.step === 0) {
          form.start("jira", "DEMO-1", "Implement the issue")
          test.step++
        } else if (test.step === 1 && form.task) {
          test.check(form.project === "project-one", "Existing project was not selected")
          test.check(form.agent === "", "An agent was chosen without the owner's selection")
          test.check(form.validProject && !form.validAgent, "Invalid initial selection")
          form.cancel()
          test.check(!form.active && test.assignments === 0, "Cancel assigned work")
          form.start("github", "demo/repo#3", "Review the PR")
          test.step++
        } else if (test.step === 2 && form.task) {
          test.choose("Project", "project-two")
          test.choose("Agent", "worker")
          test.check(form.validProject && form.validAgent, "Could not choose a different project and agent")
          form.submit()
          form.submit()
          form.cancel()
          test.check(form.active && form.busy, "An in-flight write could be cancelled")
          test.step++
        } else if (test.step === 3 && test.assignments === 1) {
          test.check(!form.active, "Successful assignment did not close the form")
          form.start("task", "stale", "Changed task")
          test.step++
        } else if (test.step === 4 && form.task) {
          test.check(test.dropdown(form, "Project").value === form.project, "Previous project is still displayed for the next task")
          test.check(test.dropdown(form, "Agent").value === form.agent, "Previous agent is still displayed for the next task")
          test.choose("Agent", "worker")
          form.submit()
          test.step++
        } else if (test.step === 5 && form.errorText !== "" && !form.busy) {
          test.check(form.active, "Conflict discarded the form")
          test.check(form.errorText.indexOf("Reload options") !== -1, "Conflict has no recovery")
          form.submit()
          test.check(!form.busy, "Conflict could retry a stale assignment")
          form.reload()
          test.step++
        } else if (test.step === 6 && form.task) {
          test.check(form.errorText === "", "Reload did not clear the error")
          form.cancel()
          form.start("jira", "slow", "First task")
          form.cancel()
          form.start("task", "second", "Second task")
          test.step++
        } else if (test.step === 7 && form.task) {
          test.check(form.task.title === "second", "Cancelled preview replaced the next task's context")
          test.check(test.assignments === 1, "Assignment submitted more than once")
          test.choose("Agent", "worker")
          test.check(form.validProject && form.validAgent, "Assign stays disabled for the next task")
          test.check(test.control(form, "iconText", "Assign").enabled, "Assign button stays disabled for the next task")
          form.submit()
          test.step++
        } else if (test.step === 8 && test.assignments === 2) {
          test.check(!form.active, "Second assignment did not close the form")
          console.log("WIDGET ASSIGNMENT TEST PASSED")
          Qt.quit()
        }
      } catch (error) {
        console.error("WIDGET ASSIGNMENT TEST FAILED: " + error)
        Qt.quit()
      }
    }
  }
}
