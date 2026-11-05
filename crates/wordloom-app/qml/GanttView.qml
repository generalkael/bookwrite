import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import com.wordloom.app

// Story timeline as a Gantt chart. Rows are tracks (characters, plotlines,
// places, themes); bars are events on the story clock. Drag a bar to move it,
// drag its right edge to change its length, double-click to edit. Events a
// character merely takes part in appear as outlined "ghost" bars on that
// character's row, so you can see everyone's whereabouts at a glance.
Rectangle {
    id: gv
    color: Theme.base

    property bool active: false
    property string selectedNode: ""
    property var tl: null
    property real scale: 28          // pixels per unit
    property bool cascade: true
    property bool showChronology: false
    property string selectedEvent: ""
    signal openScene(string id)

    readonly property int rowH: 44
    readonly property int headerW: 210
    readonly property int rulerH: 42
    readonly property int pad: 4
    readonly property real minScale: 0.05

    readonly property int rev: Wordloom.revision
    onRevChanged: if (active) reload()
    onActiveChanged: if (active) { reload(); Qt.callLater(autoFit); }
    // Fit once, the first time the chart is visible and has a size.
    function autoFit() { if (!fitted && active && chart.width > 0 && tl) { fitted = true; fit(); } }
    property bool fitted: false

    function reload() { tl = Api.get("timeline", null); }

    // ---- geometry ----
    readonly property int lo: tl ? tl.range[0] - pad : 0
    readonly property int hi: tl ? Math.max(tl.range[1] + pad, lo + Math.ceil(chart.width / scale) + 1) : 30
    function xOf(u) { return (u - lo) * scale; }
    function uOf(x) { return Math.round(x / scale) + lo; }
    readonly property real tickStep: {
        const want = 90 / scale;
        const steps = [1, 2, 5, 7, 10, 14, 30, 50, 100, 200, 365, 500, 1000, 5000];
        for (const s of steps) if (s >= want) return s;
        return 10000;
    }
    function trackIndex(id) { return tl ? tl.tracks.findIndex(t => t.id === id) : -1; }
    function trackOf(id) { return tl ? tl.tracks.find(t => t.id === id) : null; }
    function eventOf(id) { return tl ? tl.events.find(e => e.id === id) : null; }
    function fit() {
        if (!tl) return;
        const span = Math.max(1, tl.range[1] - tl.range[0] + 2 * pad);
        scale = Math.max(minScale, Math.min(120, chart.width / span));
        chart.contentX = 0;
    }

    readonly property var problemIds: {
        const s = {};
        if (tl) for (const p of tl.problems) {
            if (p.type === "overlap") { s[p.a] = true; s[p.b] = true; }
            else s[p.event] = true;
        }
        return s;
    }

    // Flatten events into drawable bars: one primary bar plus a ghost bar on
    // each participant's row.
    readonly property var bars: {
        const out = [];
        if (!tl) return out;
        for (const e of tl.events) {
            const r = trackIndex(e.track);
            if (r < 0) continue;
            out.push({ ev: e, row: r, ghost: false });
            for (const p of e.participants) {
                const pr = trackIndex(p);
                if (pr >= 0) out.push({ ev: e, row: pr, ghost: true });
            }
        }
        return out;
    }
    readonly property var deps: {
        const out = [];
        if (!tl) return out;
        for (const e of tl.events) for (const d of e.depends_on) {
            const pre = eventOf(d);
            if (pre) out.push({ from: pre, to: e, bad: e.start < pre.start + pre.duration });
        }
        return out;
    }

    readonly property alias eventDialogRef: eventDialog
    function closeDialogs() { eventDialog.close(); trackDialog.close(); }
    function editFirstEvent() { if (tl && tl.events.length) eventDialog.openEdit(tl.events[tl.events.length - 1]); }

    function newEventAt(trackId, start) {
        if (!tl || !tl.tracks.length) { trackDialog.openNew(); return; }
        eventDialog.openNew(trackId || tl.tracks[0].id, start === undefined ? Math.max(tl.range[0], lo + pad) : start);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- toolbar ----------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: Theme.panel
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4
                ToolButton { text: qsTr("＋ Track"); onClicked: trackDialog.openNew() }
                ToolButton { text: qsTr("＋ Event"); onClicked: gv.newEventAt("") }
                ToolButton { text: qsTr("＋ Marker"); onClicked: markerDialog.open() }
                ToolButton {
                    text: qsTr("⟳ Sync Cast")
                    onClicked: { const n = Api.call("syncTracks"); if (n !== undefined) Api.say(n ? qsTr("Added %1 track(s) from Characters and Places").arg(n) : qsTr("Tracks already match your Characters and Places")); }
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Create a track for every character and place in the binder")
                }
                ToolSeparator {}
                Label { text: qsTr("Zoom"); color: Theme.subtext }
                Slider { id: zoom; from: gv.minScale; to: 120; value: gv.scale; onMoved: gv.scale = value; Layout.preferredWidth: 140 }
                ToolButton { text: qsTr("Fit"); onClicked: gv.fit() }
                CheckBox { text: qsTr("Cascade"); checked: gv.cascade; onToggled: gv.cascade = checked; ToolTip.visible: hovered; ToolTip.text: qsTr("Moving an event pushes later dependent events along") }
                Item { Layout.fillWidth: true }
                ToolButton {
                    visible: gv.tl && gv.tl.problems.length > 0
                    text: "⚠ " + (gv.tl ? gv.tl.problems.length : 0)
                    palette.buttonText: Theme.danger
                    onClicked: problemsPopup.open()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Scheduling conflicts")
                }
                ToolButton { text: qsTr("Chronology"); checkable: true; checked: gv.showChronology; onToggled: gv.showChronology = checked }
                ToolButton { text: "⚙"; onClicked: settingsPopup.open(); ToolTip.visible: hovered; ToolTip.text: qsTr("Timeline units & calendar") }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---------------- chart ----------------
            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Track headers (scroll vertically with the chart)
                Rectangle {
                    id: headers
                    x: 0
                    y: gv.rulerH
                    width: gv.headerW
                    height: parent.height - gv.rulerH
                    color: Theme.panel
                    clip: true
                    z: 2
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                    Column {
                        y: -chart.contentY
                        width: parent.width
                        Repeater {
                            model: gv.tl ? gv.tl.tracks : []
                            delegate: Rectangle {
                                id: th
                                required property var modelData
                                required property int index
                                width: gv.headerW
                                height: gv.rowH
                                color: index % 2 ? Theme.panel : Qt.darker(Theme.panel, Theme.dark ? 0.92 : 1.02)
                                Rectangle { width: 4; height: parent.height; color: th.modelData.color }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 4
                                    spacing: 4
                                    KindIcon {
                                        visible: ["character", "plotline", "place"].indexOf(th.modelData.kind) >= 0
                                        kind: th.modelData.kind
                                        size: 14
                                    }
                                    Label {
                                        visible: ["character", "plotline", "place"].indexOf(th.modelData.kind) < 0
                                        text: th.modelData.kind === "theme" ? "✦" : "▪"
                                    }
                                    Label {
                                        text: th.modelData.name
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        font.underline: !!th.modelData.linked_node && nameHover.hovered
                                        HoverHandler { id: nameHover; cursorShape: th.modelData.linked_node ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler { onTapped: if (th.modelData.linked_node) gv.openScene(th.modelData.linked_node) }
                                    }
                                    ToolButton { text: "▴"; implicitWidth: 22; padding: 0; onClicked: Api.call("moveTrack", th.modelData.id, -1) }
                                    ToolButton { text: "▾"; implicitWidth: 22; padding: 0; onClicked: Api.call("moveTrack", th.modelData.id, 1) }
                                    ToolButton { text: "✎"; implicitWidth: 22; padding: 0; onClicked: trackDialog.openEdit(th.modelData) }
                                }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }
                            }
                        }
                    }
                }

                // Corner
                Rectangle {
                    width: gv.headerW; height: gv.rulerH; color: Theme.panel; z: 3
                    Label { anchors.centerIn: parent; text: gv.tl ? gv.tl.unit_name + "s" : ""; color: Theme.subtext }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                }

                // Ruler (scrolls horizontally with the chart)
                Rectangle {
                    id: ruler
                    x: gv.headerW
                    width: parent.width - gv.headerW
                    height: gv.rulerH
                    color: Theme.panel
                    clip: true
                    z: 2
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                    Item {
                        x: -chart.contentX
                        height: parent.height
                        Repeater {
                            model: Math.ceil((gv.hi - gv.lo) / gv.tickStep) + 1
                            delegate: Item {
                                required property int index
                                readonly property int unit: Math.ceil(gv.lo / gv.tickStep) * gv.tickStep + index * gv.tickStep
                                x: gv.xOf(unit)
                                height: gv.rulerH
                                Rectangle { y: parent.height - 8; width: 1; height: 8; color: Theme.subtext }
                                Label {
                                    x: 3; y: 6
                                    text: Api.unitLabel(gv.tl, parent.unit)
                                    color: Theme.subtext
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Repeater {
                            model: gv.tl ? gv.tl.markers : []
                            delegate: Label {
                                required property var modelData
                                x: gv.xOf(modelData.at) + 3
                                y: gv.rulerH - 18
                                text: "⚑ " + modelData.title
                                color: modelData.color
                                font.bold: true
                                font.pixelSize: 11
                                TapHandler { acceptedButtons: Qt.RightButton; onTapped: markerMenu.popup() }
                                Menu { id: markerMenu; MenuItem { text: qsTr("Remove marker"); onTriggered: Api.call("removeMarker", modelData.id) } }
                            }
                        }
                    }
                }

                Flickable {
                    id: chart
                    x: gv.headerW
                    y: gv.rulerH
                    width: parent.width - gv.headerW
                    height: parent.height - gv.rulerH
                    contentWidth: Math.max(width, gv.xOf(gv.hi))
                    contentHeight: Math.max(height, (gv.tl ? gv.tl.tracks.length : 0) * gv.rowH)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    onWidthChanged: gv.autoFit()
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }
                    ScrollBar.vertical: ScrollBar {}

                    // Ctrl+wheel zooms around the cursor
                    WheelHandler {
                        acceptedModifiers: Qt.ControlModifier
                        onWheel: (ev) => {
                            const u = (chart.contentX + point.position.x) / gv.scale + gv.lo;
                            gv.scale = Math.max(gv.minScale, Math.min(120, gv.scale * (ev.angleDelta.y > 0 ? 1.15 : 1 / 1.15)));
                            chart.contentX = Math.max(0, (u - gv.lo) * gv.scale - point.position.x);
                        }
                    }

                    // Row backgrounds — double-click empty space to add an event there.
                    Repeater {
                        model: gv.tl ? gv.tl.tracks : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            y: index * gv.rowH
                            width: chart.contentWidth
                            height: gv.rowH
                            color: index % 2 ? Theme.base : Qt.darker(Theme.base, Theme.dark ? 0.9 : 1.025)
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border; opacity: 0.5 }
                            TapHandler { onDoubleTapped: (ep) => gv.newEventAt(modelData.id, gv.uOf(ep.position.x)) }
                        }
                    }
                    // Grid lines
                    Repeater {
                        model: Math.ceil((gv.hi - gv.lo) / gv.tickStep) + 1
                        delegate: Rectangle {
                            required property int index
                            x: gv.xOf(Math.ceil(gv.lo / gv.tickStep) * gv.tickStep + index * gv.tickStep)
                            width: 1
                            height: chart.contentHeight
                            color: Theme.border
                            opacity: 0.45
                        }
                    }
                    // Markers
                    Repeater {
                        model: gv.tl ? gv.tl.markers : []
                        delegate: Rectangle {
                            required property var modelData
                            x: gv.xOf(modelData.at)
                            width: 2
                            height: chart.contentHeight
                            color: modelData.color
                            opacity: 0.6
                        }
                    }

                    // Dependency connectors
                    Repeater {
                        model: gv.deps
                        delegate: Shape {
                            id: dep
                            required property var modelData
                            readonly property real x1: gv.xOf(modelData.from.start + modelData.from.duration)
                            readonly property real y1: gv.trackIndex(modelData.from.track) * gv.rowH + gv.rowH / 2
                            readonly property real x2: gv.xOf(modelData.to.start)
                            readonly property real y2: gv.trackIndex(modelData.to.track) * gv.rowH + gv.rowH / 2
                            readonly property real mid: x2 > x1 + 16 ? (x1 + x2) / 2 : x1 + 8
                            z: 1
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: dep.modelData.bad ? Theme.danger : Theme.subtext
                                strokeWidth: 1.5
                                fillColor: "transparent"
                                strokeStyle: dep.modelData.bad ? ShapePath.DashLine : ShapePath.SolidLine
                                startX: dep.x1; startY: dep.y1
                                PathLine { x: dep.mid; y: dep.y1 }
                                PathLine { x: dep.mid; y: dep.y2 }
                                PathLine { x: dep.x2 - 1; y: dep.y2 }
                            }
                            ShapePath {
                                strokeColor: "transparent"
                                fillColor: dep.modelData.bad ? Theme.danger : Theme.subtext
                                startX: dep.x2; startY: dep.y2
                                PathLine { x: dep.x2 - 7; y: dep.y2 - 4 }
                                PathLine { x: dep.x2 - 7; y: dep.y2 + 4 }
                                PathLine { x: dep.x2; y: dep.y2 }
                            }
                        }
                    }

                    // Event bars
                    Repeater {
                        model: gv.bars
                        delegate: Item {
                            id: bar
                            required property var modelData
                            readonly property var ev: modelData.ev
                            readonly property bool ghost: modelData.ghost
                            readonly property bool milestone: ev.duration === 0
                            readonly property color tint: ev.color || (gv.trackOf(ev.track) ? gv.trackOf(ev.track).color : Theme.accent)
                            readonly property bool problem: !!gv.problemIds[ev.id]
                            readonly property bool linkedToSelection: gv.selectedNode !== "" && ev.linked_nodes.indexOf(gv.selectedNode) >= 0
                            property bool resizing: false
                            x: gv.xOf(ev.start) - (milestone ? 9 : 0)
                            y: modelData.row * gv.rowH + 7
                            z: ghost ? 2 : 3
                            width: milestone ? 18 : Math.max(6, ev.duration * gv.scale)
                            height: gv.rowH - 14

                            Rectangle {
                                visible: !bar.milestone
                                anchors.fill: parent
                                radius: 5
                                color: bar.ghost ? Qt.rgba(bar.tint.r, bar.tint.g, bar.tint.b, 0.18) : bar.tint
                                border.width: bar.problem || gv.selectedEvent === bar.ev.id || bar.linkedToSelection ? 2 : (bar.ghost ? 1 : 0)
                                border.color: bar.problem ? Theme.danger : (gv.selectedEvent === bar.ev.id || bar.linkedToSelection ? Theme.text : bar.tint)
                            }
                            Rectangle {
                                visible: bar.milestone
                                width: 14; height: 14
                                anchors.centerIn: parent
                                rotation: 45
                                color: bar.ghost ? "transparent" : bar.tint
                                border.color: bar.problem ? Theme.danger : bar.tint
                                border.width: 2
                            }
                            TextMetrics { id: tm; text: barLabel.text; font: barLabel.font }
                            Label {
                                id: barLabel
                                // Narrow bars and milestones carry their label outside, to the right.
                                readonly property bool outside: bar.milestone || bar.width < tm.width + 14
                                x: outside ? bar.width + 4 : 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: (bar.ev.linked_nodes.length ? "✎ " : "") + bar.ev.title
                                color: bar.ghost || outside ? Theme.text : "white"
                                font.pixelSize: 12
                                font.italic: bar.ghost
                                visible: !(bar.ghost && outside)
                            }

                            ToolTip.visible: dragArea.containsMouse && !dragArea.pressed
                            ToolTip.delay: 500
                            ToolTip.text: bar.ev.title + "\n" + Api.unitLabel(gv.tl, bar.ev.start)
                                + (bar.ev.duration > 0 ? " → " + Api.unitLabel(gv.tl, bar.ev.start + bar.ev.duration) : qsTr(" (milestone)"))
                                + (bar.ev.notes ? "\n\n" + bar.ev.notes : "")
                                + (bar.problem ? "\n\n⚠ " + qsTr("Scheduling conflict") : "")

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                anchors.rightMargin: bar.milestone || bar.ghost ? 0 : 6
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: bar.ghost ? Qt.PointingHandCursor : Qt.SizeHorCursor
                                drag.target: bar.ghost ? null : bar
                                drag.axis: Drag.XAxis
                                drag.threshold: 4
                                onPressed: (m) => { gv.selectedEvent = bar.ev.id; }
                                onClicked: (m) => { if (m.button === Qt.RightButton) barMenu.popup(); }
                                onDoubleClicked: eventDialog.openEdit(bar.ev)
                                onReleased: {
                                    if (drag.active || bar.x !== gv.xOf(bar.ev.start) - (bar.milestone ? 9 : 0)) {
                                        const start = gv.uOf(bar.x + (bar.milestone ? 9 : 0));
                                        if (start !== bar.ev.start) Api.call("moveEvent", bar.ev.id, start, bar.ev.duration, gv.cascade);
                                        else bar.x = Qt.binding(() => gv.xOf(bar.ev.start) - (bar.milestone ? 9 : 0));
                                    }
                                }
                            }
                            // Resize handle on the right edge
                            MouseArea {
                                visible: !bar.milestone && !bar.ghost
                                anchors.right: parent.right
                                width: 8
                                height: parent.height
                                cursorShape: Qt.SplitHCursor
                                property real startW
                                property real startX
                                onPressed: (m) => { startW = bar.width; startX = mapToItem(chart.contentItem, m.x, 0).x; bar.resizing = true; }
                                onPositionChanged: (m) => {
                                    if (!pressed) return;
                                    const nx = mapToItem(chart.contentItem, m.x, 0).x;
                                    bar.width = Math.max(gv.scale, startW + nx - startX);
                                }
                                onReleased: {
                                    bar.resizing = false;
                                    const dur = Math.max(1, Math.round(bar.width / gv.scale));
                                    if (dur !== bar.ev.duration) Api.call("moveEvent", bar.ev.id, bar.ev.start, dur, gv.cascade);
                                    else bar.width = Qt.binding(() => bar.milestone ? 18 : Math.max(6, bar.ev.duration * gv.scale));
                                }
                            }
                            Menu {
                                id: barMenu
                                MenuItem { text: qsTr("Edit Event…"); onTriggered: eventDialog.openEdit(bar.ev) }
                                MenuItem {
                                    text: bar.ev.linked_nodes.length ? qsTr("Open Scene") : qsTr("Write This Scene")
                                    onTriggered: { const id = Api.call("sceneForEvent", bar.ev.id); if (id) gv.openScene(id); }
                                }
                                MenuItem { text: qsTr("Make Milestone"); visible: !bar.milestone; height: visible ? implicitHeight : 0; onTriggered: Api.call("moveEvent", bar.ev.id, bar.ev.start, 0, false) }
                                MenuItem { text: qsTr("Add Marker Here"); onTriggered: Api.call("addMarker", bar.ev.start, bar.ev.title) }
                                MenuSeparator {}
                                MenuItem { text: qsTr("Delete Event"); onTriggered: Api.call("removeEvent", bar.ev.id) }
                            }
                        }
                    }
                }

                // Empty state
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: gv.tl !== null && gv.tl.tracks.length === 0
                    spacing: 10
                    z: 5
                    Label { text: qsTr("Plot your story in time"); font.pixelSize: 20; color: Theme.text; Layout.alignment: Qt.AlignHCenter }
                    Label {
                        text: qsTr("Tracks are rows — a character, a plotline, a place.\nEvents are bars on the story clock. Link them to scenes,\nchain them with dependencies, and spot conflicts instantly.")
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.subtext
                        Layout.alignment: Qt.AlignHCenter
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Button { text: qsTr("Create Tracks from Characters & Places"); highlighted: true; onClicked: { const n = Api.call("syncTracks"); if (n === 0) trackDialog.openNew(); } }
                        Button { text: qsTr("＋ Track"); onClicked: trackDialog.openNew() }
                    }
                }
            }

            // ---------------- chronology panel ----------------
            Rectangle {
                visible: gv.showChronology
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { width: 1; height: parent.height; color: Theme.border }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    Label { text: qsTr("Story order vs. manuscript order"); font.bold: true; color: Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label {
                        text: qsTr("Scenes linked to events, in the order they happen. # is the position in the manuscript; ↺ marks scenes told out of sequence.")
                        color: Theme.subtext; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: gv.tl ? gv.tl.chronology : []
                        delegate: ItemDelegate {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            readonly property int msIndex: gv.tl.scenes.findIndex(s => s.id === modelData.id) + 1
                            readonly property int prevMs: index > 0 ? gv.tl.scenes.findIndex(s => s.id === gv.tl.chronology[index - 1].id) + 1 : 0
                            onClicked: gv.openScene(modelData.id)
                            contentItem: RowLayout {
                                Label { text: "#" + msIndex; color: Theme.subtext; Layout.preferredWidth: 34 }
                                Label { text: modelData.title; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { visible: msIndex < prevMs; text: "↺"; color: Theme.accent; font.bold: true }
                                Label { text: Api.unitLabel(gv.tl, modelData.at); color: Theme.subtext; font.pixelSize: 10 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------- popups & dialogs ----------------
    EventDialog { id: eventDialog; anchors.centerIn: parent; tl: gv.tl; onOpenScene: (id) => gv.openScene(id) }
    TrackDialog { id: trackDialog; anchors.centerIn: parent; tl: gv.tl }

    Dialog {
        id: markerDialog
        title: qsTr("Add Marker")
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAboutToShow: { markerTitle.text = ""; markerAt.value = gv.tl ? gv.tl.range[0] : 0; }
        GridLayout {
            columns: 2
            Label { text: qsTr("Title") }
            TextField { id: markerTitle; placeholderText: qsTr("Act II begins") }
            Label { text: gv.tl ? gv.tl.unit_name : "" }
            SpinBox { id: markerAt; from: -1000000; to: 1000000; editable: true }
        }
        onAccepted: Api.call("addMarker", markerAt.value, markerTitle.text || qsTr("Marker"))
    }

    Popup {
        id: problemsPopup
        anchors.centerIn: parent
        width: 460
        height: Math.min(400, problemsCol.implicitHeight + 32)
        modal: true
        padding: 16
        ScrollView {
            anchors.fill: parent
            ColumnLayout {
                id: problemsCol
                width: 420
                Label { text: qsTr("Scheduling conflicts"); font.bold: true; font.pixelSize: 16; color: Theme.text }
                Repeater {
                    model: gv.tl ? gv.tl.problems : []
                    delegate: Label {
                        required property var modelData
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.text
                        text: {
                            const p = modelData;
                            if (p.type === "overlap") {
                                const t = gv.trackOf(p.track), a = gv.eventOf(p.a), b = gv.eventOf(p.b);
                                return "• " + qsTr("%1 is in two places at once: “%2” and “%3” overlap.").arg(t ? t.name : "?").arg(a ? a.title : "?").arg(b ? b.title : "?");
                            }
                            const e = gv.eventOf(p.event), d = gv.eventOf(p.depends_on);
                            return "• " + qsTr("“%1” starts before “%2”, which it depends on, has finished.").arg(e ? e.title : "?").arg(d ? d.title : "?");
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: settingsPopup
        anchors.centerIn: parent
        modal: true
        padding: 16
        onAboutToShow: { unitField.text = gv.tl ? gv.tl.unit_name : "Day"; calField.text = gv.tl && gv.tl.calendar_start ? gv.tl.calendar_start : ""; }
        ColumnLayout {
            Label { text: qsTr("Timeline settings"); font.bold: true; font.pixelSize: 16; color: Theme.text }
            GridLayout {
                columns: 2
                Label { text: qsTr("Unit name") }
                TextField { id: unitField; placeholderText: qsTr("Day, Hour, Year, Chapter…") }
                Label { text: qsTr("Day 0 is (YYYY-MM-DD)") }
                TextField { id: calField; placeholderText: qsTr("optional, for date labels") }
            }
            Label { text: qsTr("With a start date and a unit of “Day”, the ruler shows calendar dates."); color: Theme.subtext; font.pixelSize: 11 }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: qsTr("Cancel"); onClicked: settingsPopup.close() }
                Button { text: qsTr("Apply"); highlighted: true; onClicked: { Api.call("setTimelineSettings", unitField.text, calField.text); settingsPopup.close(); } }
            }
        }
    }
}
