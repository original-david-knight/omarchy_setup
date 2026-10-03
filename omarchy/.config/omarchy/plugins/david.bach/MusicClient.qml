import QtQuick

Item {
    id: root

    property string baseUrl: "http://127.0.0.1:8765"
    property bool polling: true
    property bool available: false
    property bool busy: false
    property string errorText: ""
    property var state: ({
        "playing": false,
        "settings": {
            "style": "counterpoint",
            "nature": "rain",
            "volume": 0.45,
            "nature_level": 0.25,
            "minutes": 0
        },
        "composition": null,
        "elapsed": 0,
        "remaining": null
    })
    readonly property bool playing: available && state.playing
    property var queue: []
    property real pendingVolume: -1
    property var activeRequest: null
    // The factory also lets the offline verification drive the real request lifecycle.
    property var requestFactory: function() {
        return new XMLHttpRequest();
    }

    function accept(data) {
        if (!data || typeof data.playing !== "boolean" || !data.settings)
            throw new Error("Bach garden returned an unreadable status.");

        state = data;
        if (!queue.some(function(operation) {
            return operation.endpoint === "settings" && operation.data.volume !== undefined;
        }))
            pendingVolume = -1;

        available = true;
        errorText = data.error || "";
    }

    function enqueue(endpoint, data) {
        queue = queue.concat([{
            "endpoint": endpoint,
            "data": data
        }]);
        pump();
    }

    function refresh() {
        if (busy || queue.length)
            return ;

        enqueue("status", null);
    }

    function finish(request, message) {
        if (activeRequest !== request)
            return ;

        timeout.stop();
        activeRequest = null;
        busy = false;
        if (message)
            errorText = message;

        Qt.callLater(pump);
    }

    function pump() {
        if (busy || !queue.length)
            return ;

        var operation = queue[0];
        queue = queue.slice(1);
        var request = requestFactory();
        activeRequest = request;
        busy = true;
        request.onreadystatechange = function() {
            if (request.readyState !== 4 || activeRequest !== request)
                return ;

            var message = "";
            if (request.status === 0) {
                available = false;
                queue = [];
                pendingVolume = -1;
                message = "Bach garden is offline. Start the music service to listen.";
            } else {
                try {
                    var result = JSON.parse(request.responseText);
                    if (request.status !== 200)
                        throw new Error(result.error || "The request failed.");

                    accept(result);
                } catch (error) {
                    message = String(error.message || error);
                }
            }
            finish(request, message);
        };
        try {
            request.open(operation.data === null ? "GET" : "POST", baseUrl + "/api/" + operation.endpoint);
            if (operation.data !== null)
                request.setRequestHeader("Content-Type", "application/json");

            timeout.restart();
            request.send(operation.data === null ? "" : JSON.stringify(operation.data));
        } catch (error) {
            available = false;
            queue = [];
            pendingVolume = -1;
            finish(request, String(error.message || error));
        }
    }

    function togglePlayback() {
        if (available)
            enqueue(playing ? "stop" : "play", {
        });

    }

    function nextComposition() {
        if (playing)
            enqueue("next", {
        });

    }

    function update(data) {
        if (available)
            enqueue("settings", data);

    }

    function changeStyle(style) {
        if (!available || style === state.settings.style)
            return ;

        update({
            "style": style
        });
        if (playing)
            nextComposition();

    }

    function nudgeVolume(steps) {
        if (!available)
            return ;

        var volume = pendingVolume >= 0 ? pendingVolume : state.settings.volume;
        for (var i = 0; i < queue.length; i++) {
            var item = queue[i];
            if (item.endpoint === "settings" && item.data.volume !== undefined)
                volume = item.data.volume;

        }
        pendingVolume = Math.max(0, Math.min(1, volume + steps * 0.04));
        update({
            "volume": pendingVolume
        });
    }

    visible: false
    Component.onDestruction: {
        if (activeRequest) {
            var request = activeRequest;
            activeRequest = null;
            request.abort();
        }
    }

    Timer {
        id: timeout

        interval: 8000
        onTriggered: {
            var request = root.activeRequest;
            if (!request)
                return ;

            // Detach first: abort can synchronously emit onreadystatechange.
            root.activeRequest = null;
            root.busy = false;
            root.available = false;
            root.queue = [];
            root.pendingVolume = -1;
            root.errorText = "The music service did not respond.";
            request.abort();
        }
    }

    Timer {
        interval: 2000
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

}
