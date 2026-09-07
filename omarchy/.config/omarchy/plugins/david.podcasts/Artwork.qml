import QtQuick
import Quickshell.Widgets
import qs.Commons

ClippingRectangle {
  id: root
  property string source: ""
  property string glyph: "♫"
  property color tint: Color.accent
  radius: Style.space(10)
  color: Qt.darker(tint, 3.5)

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.darker(root.tint, 1.8) }
      GradientStop { position: 1; color: Qt.darker(root.tint, 4.5) }
    }
  }
  Rectangle {
    anchors.centerIn: parent
    width: parent.width * 0.75
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, root.width / 70)
    border.color: Qt.rgba(1, 1, 1, 0.14)
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.72
      height: width
      radius: width / 2
      color: "transparent"
      border.width: parent.border.width
      border.color: parent.border.color
    }
  }
  Text {
    anchors.centerIn: parent
    text: root.glyph
    color: root.tint
    font.family: Style.font.family
    font.pixelSize: root.width * 0.3
  }
  Image {
    anchors.fill: parent
    source: root.source
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: Math.max(64, root.width * 2)
    sourceSize.height: Math.max(64, root.width * 2)
    visible: status === Image.Ready
  }
}
