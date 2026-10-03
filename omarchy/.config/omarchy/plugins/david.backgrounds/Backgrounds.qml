import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Fullscreen overlay for managing the current theme's backgrounds. All file
// work happens in the sibling `backgrounds` helper; this file only renders
// its `list` output and runs its add/remove/set commands.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginId: "david.backgrounds"
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("backgrounds").toString().replace(/^file:\/\//, ""))

  property bool opened: false
  // True while the file chooser is up; the overlay steps aside so the
  // chooser can take keyboard focus.
  property bool picking: false
  property bool loaded: false
  property string themeName: ""
  property string currentPath: ""
  property var images: []
  property string pendingRemove: ""
  property string message: ""
  property string selectAfterLoad: ""

  readonly property color cardBackground: Color.popups.background
  readonly property color cardBorder: Color.popups.border
  readonly property color textColor: Color.popups.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  readonly property int tileWidth: Style.space(232)
  readonly property int tileHeight: Style.space(130)
  readonly property int cellPadding: Style.space(8)
  readonly property int columns: 4

  readonly property var selectedItem: grid.currentIndex >= 0 && grid.currentIndex < images.length ? images[grid.currentIndex] : null
  readonly property int userCount: images.filter(function(item) { return item.kind === "user" }).length

  function nameForPath(path) {
    return String(path || "").split("/").pop()
  }

  function open(payload) {
    opened = true
    picking = false
    pendingRemove = ""
    message = ""
    reload()
  }

  function close() {
    opened = false
    picking = false
    pendingRemove = ""
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function" && shell.hide(pluginId)) return
    close()
  }

  function reload() {
    if (!selectAfterLoad && selectedItem && selectedItem.path) selectAfterLoad = selectedItem.path
    listProc.running = false
    listProc.running = true
  }

  function parseList(text) {
    var rows = String(text || "").split("\n")
    var next = []
    for (var i = 0; i < rows.length; i++) {
      var cols = rows[i].split("\t")
      if (cols.length < 3) continue
      if (cols[0] === "theme") {
        themeName = cols[1]
        currentPath = cols[2]
      } else {
        next.push({ kind: cols[0], path: cols[1], thumbnail: cols[2], name: nameForPath(cols[1]) })
      }
    }
    next.push({ kind: "add", path: "", thumbnail: "", name: "Add backgrounds" })

    var wanted = selectAfterLoad || currentPath
    var index = 0
    for (var j = 0; j < next.length; j++) {
      if (next[j].path === wanted) { index = j; break }
    }

    images = next
    selectAfterLoad = ""
    grid.currentIndex = Math.min(index, next.length - 1)
    grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)
    loaded = true
    grid.forceActiveFocus()
  }

  function run(args, label) {
    if (actionProc.running) return
    message = ""
    actionProc.label = label || ""
    actionProc.command = [helper].concat(args)
    actionProc.running = true
  }

  function addBackgrounds() {
    if (actionProc.running) return
    pendingRemove = ""
    picking = true
    run(["add"], "add")
  }

  function setCurrent(item) {
    if (!item || item.kind === "add") return
    if (item.path === currentPath) return
    currentPath = item.path
    run(["set", item.path], "set")
  }

  function activate(item) {
    if (!item) return
    if (item.kind === "add") addBackgrounds()
    else setCurrent(item)
  }

  function requestRemove(item) {
    if (!item || item.kind !== "user") {
      if (item && item.kind === "theme") message = "Backgrounds that ship with the theme can't be removed"
      return
    }
    if (pendingRemove === item.path) {
      confirmRemove()
      return
    }
    pendingRemove = item.path
    message = ""
  }

  function confirmRemove() {
    if (!pendingRemove) return
    var path = pendingRemove
    pendingRemove = ""
    var index = -1
    for (var i = 0; i < images.length; i++) if (images[i].path === path) { index = i; break }
    // Keep the cursor near where the removed tile was.
    var neighbour = images[index + 1] && images[index + 1].kind !== "add" ? images[index + 1] : images[index - 1]
    selectAfterLoad = neighbour ? neighbour.path : ""
    run(["remove", path], "remove")
  }

  Process {
    id: listProc
    command: [root.helper, "list"]
    stdout: StdioCollector {
      onStreamFinished: root.parseList(text)
    }
  }

  Process {
    id: actionProc
    property string label: ""
    stdout: StdioCollector { id: actionOut }
    stderr: StdioCollector { id: actionErr }
    onExited: function(exitCode) {
      var label = actionProc.label
      var added = String(actionOut.text || "").split("\n").filter(function(line) { return line.length > 0 })

      if (exitCode !== 0) root.message = String(actionErr.text || "").trim() || ("Couldn't " + label + " background")
      else if (label === "add" && added.length > 0) {
        root.message = added.length === 1 ? "Added " + root.nameForPath(added[0]) : "Added " + added.length + " backgrounds"
        root.selectAfterLoad = added[0]
      }

      root.picking = false
      if (label === "add" || label === "remove") Quickshell.execDetached(["omarchy-theme-bg-cache"])
      if (root.opened) root.reload()
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened && !root.picking
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-backgrounds"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) grid.forceActiveFocus()

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      visible: root.loaded
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(80), root.columns * grid.cellWidth + 2 * Style.space(20))
      height: Math.min(parent.height - Style.space(80), content.implicitHeight + 2 * Style.space(20))
      color: root.cardBackground
      border.color: root.cardBorder
      border.width: 1
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(14)

        Item {
          width: parent.width
          height: titleText.implicitHeight

          Text {
            id: titleText
            anchors.left: parent.left
            text: "Backgrounds"
            color: root.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Text {
            anchors.left: titleText.right
            anchors.leftMargin: Style.space(10)
            anchors.baseline: titleText.baseline
            text: root.themeName + " · " + root.userCount + (root.userCount === 1 ? " background" : " backgrounds")
              + (root.images.length - 1 > root.userCount ? " + " + (root.images.length - 1 - root.userCount) + " from the theme" : "")
            color: Util.alpha(root.textColor, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        GridView {
          id: grid
          width: parent.width
          height: Math.min(Math.ceil(count / root.columns), 3) * cellHeight
          cellWidth: root.tileWidth + 2 * root.cellPadding
          cellHeight: root.tileHeight + 2 * root.cellPadding + Style.space(22)
          model: root.images
          clip: true
          focus: true
          keyNavigationEnabled: true
          boundsBehavior: Flickable.StopAtBounds
          highlightFollowsCurrentItem: false

          onCurrentIndexChanged: if (root.pendingRemove && (!root.selectedItem || root.selectedItem.path !== root.pendingRemove)) root.pendingRemove = ""

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (root.pendingRemove) root.pendingRemove = ""
              else root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              if (root.pendingRemove) root.confirmRemove()
              else root.activate(root.selectedItem)
              event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
              root.requestRemove(root.selectedItem)
              event.accepted = true
            } else if (event.key === Qt.Key_A || event.key === Qt.Key_Plus || event.key === Qt.Key_Insert) {
              root.addBackgrounds()
              event.accepted = true
            } else if (event.key === Qt.Key_O) {
              Quickshell.execDetached([root.helper, "folder"])
              root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_H) { grid.moveCurrentIndexLeft(); event.accepted = true }
            else if (event.key === Qt.Key_L) { grid.moveCurrentIndexRight(); event.accepted = true }
            else if (event.key === Qt.Key_K) { grid.moveCurrentIndexUp(); event.accepted = true }
            else if (event.key === Qt.Key_J) { grid.moveCurrentIndexDown(); event.accepted = true }
          }

          delegate: Item {
            id: tile
            required property var modelData
            required property int index

            readonly property bool selected: GridView.isCurrentItem
            readonly property bool isAdd: modelData.kind === "add"
            readonly property bool isCurrent: !isAdd && modelData.path === root.currentPath
            readonly property bool confirming: !isAdd && modelData.path === root.pendingRemove
            readonly property bool hot: selected || mouse.containsMouse

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
              id: frame
              x: root.cellPadding
              y: root.cellPadding
              width: root.tileWidth
              height: root.tileHeight
              color: tile.isAdd ? Util.alpha(root.textColor, tile.hot ? 0.08 : 0.03) : Util.alpha(root.textColor, 0.05)
              radius: Style.cornerRadius
              clip: true

              Image {
                anchors.fill: parent
                visible: !tile.isAdd
                source: tile.isAdd ? "" : Util.fileUrl(tile.modelData.thumbnail)
                sourceSize.width: root.tileWidth * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
              }

              Text {
                anchors.centerIn: parent
                visible: tile.isAdd
                text: "+"
                color: Util.alpha(root.textColor, tile.hot ? 0.9 : 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge * 1.4
              }

              // Dim unselected tiles slightly so the cursor reads at a glance.
              Rectangle {
                anchors.fill: parent
                visible: !tile.isAdd
                color: Util.alpha(Color.background, tile.confirming ? 0.72 : (tile.hot ? 0 : 0.25))
              }

              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Style.space(6)
                visible: tile.isCurrent || tile.modelData.kind === "theme"
                width: badge.implicitWidth + Style.space(12)
                height: badge.implicitHeight + Style.space(4)
                radius: Style.cornerRadius
                color: tile.isCurrent ? root.accent : Util.alpha(Color.background, 0.8)

                Text {
                  id: badge
                  anchors.centerIn: parent
                  text: tile.isCurrent ? (tile.modelData.kind === "theme" ? "Current · theme" : "Current") : "Theme"
                  color: tile.isCurrent ? Color.background : root.textColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }
              }

              Column {
                anchors.centerIn: parent
                visible: tile.confirming
                spacing: Style.space(8)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Move to trash?"
                  color: root.textColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: Font.DemiBold
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(8)

                  Repeater {
                    model: [{ label: "Remove", danger: true }, { label: "Keep", danger: false }]

                    delegate: Rectangle {
                      required property var modelData
                      width: buttonText.implicitWidth + Style.space(20)
                      height: buttonText.implicitHeight + Style.space(8)
                      radius: Style.cornerRadius
                      color: modelData.danger ? root.urgent : Util.alpha(root.textColor, buttonMouse.containsMouse ? 0.2 : 0.12)

                      Text {
                        id: buttonText
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        color: parent.modelData.danger ? Color.background : root.textColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                      }

                      MouseArea {
                        id: buttonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: parent.modelData.danger ? root.confirmRemove() : (root.pendingRemove = "")
                      }
                    }
                  }
                }
              }

              Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                border.width: tile.selected ? 3 : (tile.isCurrent ? 2 : 1)
                border.color: tile.selected ? root.accent : (tile.isCurrent ? Util.alpha(root.accent, 0.6) : Util.alpha(root.textColor, 0.15))
              }
            }

            MouseArea {
              id: mouse
              anchors.fill: frame
              hoverEnabled: true
              enabled: !tile.confirming
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                grid.currentIndex = tile.index
                root.activate(tile.modelData)
              }
            }

            // Remove button, shown on hover for your own backgrounds.
            Rectangle {
              anchors.top: frame.top
              anchors.right: frame.right
              anchors.margins: Style.space(6)
              visible: tile.modelData.kind === "user" && !tile.confirming && (mouse.containsMouse || removeMouse.containsMouse)
              width: Style.space(24)
              height: Style.space(24)
              radius: width / 2
              color: removeMouse.containsMouse ? root.urgent : Util.alpha(Color.background, 0.85)

              Text {
                anchors.centerIn: parent
                text: "×"
                color: removeMouse.containsMouse ? Color.background : root.textColor
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
              }

              MouseArea {
                id: removeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  grid.currentIndex = tile.index
                  root.requestRemove(tile.modelData)
                }
              }
            }

            Text {
              anchors.top: frame.bottom
              anchors.topMargin: Style.space(4)
              anchors.left: frame.left
              width: frame.width
              text: tile.modelData.name
              color: Util.alpha(root.textColor, tile.selected ? 0.95 : 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        Text {
          width: parent.width
          text: root.message || (root.pendingRemove
            ? "Enter or Delete to move " + root.nameForPath(root.pendingRemove) + " to the trash · Esc to keep it"
            : "Enter set as background · A add · Delete remove · O open folder · Esc close")
          color: root.message ? root.textColor : Util.alpha(root.textColor, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
