import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root

    readonly property var musicSettings: client.state.settings
    property real wheelAccumulator: 0

    function title(value) {
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function clock(seconds) {
        var value = Math.max(0, Math.floor(seconds));
        return Math.floor(value / 60) + ":" + (value % 60 < 10 ? "0" : "") + value % 60;
    }

    function startService() {
        Quickshell.execDetached(["systemctl", "--user", "start", "bach-ambient.service"]);
        serviceRefresh.restart();
    }

    function openControls() {
        Qt.openUrlExternally(client.baseUrl);
        root.close();
    }

    moduleName: "david.bach"
    ipcTarget: "david.bach"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onOpenedChanged: {
        if (opened)
            client.refresh();

    }

    MusicClient {
        id: client

        baseUrl: "http://127.0.0.1:" + root.setting("port", 8765)
    }

    Timer {
        id: serviceRefresh

        interval: 750
        onTriggered: client.refresh()
    }

    WidgetButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: "󰝚"
        fontSize: Style.bar.iconFont
        foreground: client.playing ? Color.accent : root.barForeground
        dimmed: !client.available
        tooltipText: "Bach garden · " + (!client.available ? "Service offline" : client.playing ? root.title(root.musicSettings.style) + " · " + root.clock(client.state.elapsed) : "Stopped") + "\nLeft: controls · Middle: play/stop · Right: new composition · Scroll: volume"
        onPressed: function(code) {
            if (code === Qt.MiddleButton) {
                if (client.available)
                    client.togglePlayback();
                else
                    root.startService();
            } else if (code === Qt.RightButton) {
                client.nextComposition();
            } else {
                root.toggle();
            }
        }
        onWheelMoved: function(delta) {
            var wheel = Util.wheelSteps(root.wheelAccumulator, delta);
            root.wheelAccumulator = wheel.remainder;
            if (wheel.steps)
                client.nudgeVolume(wheel.steps);

        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: content
        contentWidth: panel.fittedContentWidth(Style.space(410))
        contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(750))

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Content {
                id: content

                width: parent.width
                client: client
                bar: root.bar
                onStartServiceRequested: root.startService()
                onOpenControlsRequested: root.openControls()
                onCloseRequested: root.close()
            }

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
            }

        }

    }

}
