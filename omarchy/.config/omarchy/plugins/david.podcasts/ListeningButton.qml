import QtQuick
import QtQuick.Controls
import qs.Commons

AbstractButton {
  id: root
  property color tint: Color.foreground
  property bool prominent: false
  property string tooltip: ""
  implicitWidth: Math.max(Style.space(34), label.implicitWidth + Style.space(22))
  implicitHeight: Style.space(34)
  hoverEnabled: true
  opacity: enabled ? 1 : 0.35
  Accessible.name: tooltip || text
  ToolTip.visible: hovered && tooltip !== ""
  ToolTip.text: tooltip
  ToolTip.delay: 500
  background: Rectangle {
    radius: height / 2
    color: root.prominent ? root.tint : Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.down ? 0.22 : root.hovered || root.activeFocus ? 0.14 : 0.06)
    border.width: root.activeFocus ? 1 : 0
    border.color: root.tint
  }
  contentItem: Text {
    id: label
    text: root.text
    textFormat: Text.PlainText
    color: root.prominent ? "#13201c" : root.tint
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: root.prominent
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
