import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

ColumnLayout {
    id: root

    required property MusicClient client
    property QtObject bar: null
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property var musicSettings: client.state.settings

    signal startServiceRequested()
    signal openControlsRequested()
    signal closeRequested()

    function title(value) {
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function clock(seconds) {
        var value = Math.max(0, Math.floor(seconds));
        return Math.floor(value / 60) + ":" + (value % 60 < 10 ? "0" : "") + value % 60;
    }

    width: parent.width
    spacing: Style.space(14)
    focus: true
    Keys.onEscapePressed: root.closeRequested()

    PanelHero {
        Layout.fillWidth: true
        title: "Bach garden"
        meta: !client.available ? "Service offline" : client.playing ? (client.state.composition ? root.title(client.state.composition.style) + " · " + client.state.composition.key : "Starting") : "Ambient music on demand"
        detail: client.playing ? root.clock(client.state.elapsed) : ""
        foreground: root.foreground
        fontFamily: root.fontFamily

        iconComponent: Component {
            Text {
                text: "󰝚"
                color: client.playing ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
            }

        }

    }

    Text {
        Layout.fillWidth: true
        visible: client.errorText !== ""
        text: client.errorText
        textFormat: Text.PlainText
        color: Color.urgent
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Button {
            text: !client.available ? "Start service" : client.playing ? "Stop" : "Play"
            iconText: client.playing ? "󰓛" : "󰐊"
            selected: client.playing
            focusable: true
            enabled: !client.busy
            onClicked: client.available ? client.togglePlayback() : root.startServiceRequested()
        }

        Button {
            text: "New composition"
            iconText: "󰒭"
            focusable: true
            enabled: client.playing && !client.busy
            onClicked: client.nextComposition()
        }

        Item {
            Layout.fillWidth: true
        }

    }

    Text {
        text: "Mood"
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
        enabled: client.available
        value: root.musicSettings.style
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        options: [{
            "value": "counterpoint",
            "label": "Counterpoint"
        }, {
            "value": "drift",
            "label": "Drift"
        }, {
            "value": "nocturne",
            "label": "Nocturne"
        }, {
            "value": "wander",
            "label": "Wander"
        }]
        onChanged: function(value) {
            client.changeStyle(value);
        }
    }

    Text {
        text: "Nature"
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        rowSpacing: Style.space(6)
        columnSpacing: Style.space(6)

        Repeater {
            model: [{
                "value": "none",
                "label": "Music only"
            }, {
                "value": "rain",
                "label": "Rain"
            }, {
                "value": "stream",
                "label": "Stream"
            }, {
                "value": "forest",
                "label": "Birds & breeze"
            }, {
                "value": "ocean",
                "label": "Ocean"
            }]

            Button {
                required property var modelData

                Layout.fillWidth: true
                text: modelData.label
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                selected: root.musicSettings.nature === modelData.value
                enabled: client.available
                focusable: true
                onClicked: client.update({
                    "nature": modelData.value
                })
            }

        }

    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: "Volume"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: Math.round(volume.liveValue * 100) + "%"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

    }

    PanelSlider {
        id: volume

        Layout.fillWidth: true
        bar: root.bar
        value: root.musicSettings.volume
        enabled: client.available
        onReleased: function(value) {
            client.update({
                "volume": value
            });
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: "Nature level"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: Math.round(nature.liveValue * 100) + "%"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

    }

    PanelSlider {
        id: nature

        Layout.fillWidth: true
        bar: root.bar
        value: root.musicSettings.nature_level
        enabled: client.available && root.musicSettings.nature !== "none"
        onReleased: function(value) {
            client.update({
                "nature_level": value
            });
        }
    }

    Text {
        text: "Sleep timer" + (client.playing && client.state.remaining !== null ? " · stops in " + root.clock(client.state.remaining) : "")
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
        enabled: client.available
        value: String(root.musicSettings.minutes)
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        options: [{
            "value": "0",
            "label": "Off"
        }, {
            "value": "15",
            "label": "15m"
        }, {
            "value": "30",
            "label": "30m"
        }, {
            "value": "60",
            "label": "1h"
        }, {
            "value": "120",
            "label": "2h"
        }]
        onChanged: function(value) {
            client.update({
                "minutes": Number(value)
            });
        }
    }

    Button {
        text: "Open full controls"
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        focusable: true
        onClicked: root.openControlsRequested()
    }

}
