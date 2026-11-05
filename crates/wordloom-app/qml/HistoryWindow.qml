import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import com.wordloom.app

// Word Count History: words written (bars) or the running total (line) over
// a preset or custom date range, grouped by day, week, month or year.
Window {
    id: hw
    title: qsTr("Word Count History")
    width: 920
    height: 620
    minimumWidth: 640
    minimumHeight: 440
    color: Theme.window
    // A separate window doesn't inherit the main window's palette; without
    // this, controls follow the system colours even when the app is forced
    // light or dark (light boxes with light text).
    palette.window: Theme.window
    palette.base: Theme.base
    palette.alternateBase: Theme.panel
    palette.text: Theme.text
    palette.windowText: Theme.text
    palette.buttonText: Theme.text
    palette.button: Theme.panel
    palette.highlight: Theme.accent
    palette.highlightedText: "white"
    palette.placeholderText: Theme.subtext
    palette.mid: Theme.border
    palette.dark: Theme.border
    palette.light: Theme.base
    palette.toolTipBase: Theme.base
    palette.toolTipText: Theme.text

    property var hist: null
    property var target: null           // daily session target, if any
    property int preset: 0
    readonly property int customPreset: presets.length - 1
    readonly property var presets: [
        { label: qsTr("Daily"), tip: qsTr("Last 30 days, by day"), days: 30, bucket: "day" },
        { label: qsTr("Weekly"), tip: qsTr("Last 26 weeks, by week"), days: 26 * 7, bucket: "week" },
        { label: qsTr("Monthly"), tip: qsTr("Last 24 months, by month"), months: 24, bucket: "month" },
        { label: qsTr("90 days"), tip: qsTr("Last 90 days, by day"), days: 90, bucket: "day" },
        { label: qsTr("Yearly"), tip: qsTr("Every year since you started, by year"), lifetime: true, bucket: "year" },
        { label: qsTr("Lifetime"), tip: qsTr("Everything since you started, grouped to fit"), lifetime: true, bucket: "auto" },
        { label: qsTr("Custom"), tip: qsTr("Your own dates and grouping") }
    ]
    readonly property var bucketIds: ["auto", "day", "week", "month", "year"]
    // 0: words written, 1: manuscript total, 2: project total
    property int measure: 0

    function iso(d) {
        const p = (n) => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
    }
    function parseIso(s) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s.trim());
        return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null;
    }
    function validDate(s) { return s.trim() === "" || parseIso(s) !== null; }

    function show(presetIndex) {
        applyPreset(presetIndex === undefined ? preset : presetIndex);
        visible = true;
        raise();
        requestActivate();
    }
    function applyPreset(i) {
        preset = i;
        const p = presets[i];
        if (i === customPreset) { reload(); return; }
        const today = new Date();
        let from = "";
        if (p.days) { const d = new Date(today); d.setDate(d.getDate() - p.days + 1); from = iso(d); }
        else if (p.months) { from = iso(new Date(today.getFullYear(), today.getMonth() - p.months + 1, 1)); }
        fromField.text = from;               // "" = since the first recorded day
        toField.text = iso(today);
        bucketBox.currentIndex = Math.max(0, bucketIds.indexOf(p.bucket));
        reload();
    }
    function reload() {
        const s = Api.get("stats", null);
        target = s ? s.session_target : null;
        hist = Api.get("statsHistory", null, fromField.text, toField.text, bucketIds[bucketBox.currentIndex]);
        if (hist && fromField.text === "") fromField.text = hist.from;
    }
    // Move the whole range back (-1) or forward (+1) by its own length.
    function shift(dir) {
        const a = parseIso(fromField.text), b = parseIso(toField.text);
        if (!a || !b) return;
        const len = Math.round((b - a) / 86400000) + 1;
        a.setDate(a.getDate() + dir * len); b.setDate(b.getDate() + dir * len);
        fromField.text = iso(a); toField.text = iso(b);
        preset = customPreset;
        reload();
    }

    readonly property var buckets: hist ? hist.buckets : []
    readonly property var values: buckets.map(b => measure === 0 ? b.written : measure === 1 ? b.manuscript : b.project)
    readonly property bool lineMode: measure !== 0
    readonly property bool showGoal: !lineMode && hist && hist.bucket === "day" && !!target
    function niceCeil(v) {
        if (v <= 0) return 10;
        const p = Math.pow(10, Math.floor(Math.log10(v)));
        for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return m * p;
        return 10 * p;
    }
    // Axis from minV to maxV in four round steps.
    readonly property real lowest: lineMode ? 0 : Math.min(0, ...values.filter(v => v !== null))
    readonly property real minV: lowest < 0 ? -4 * niceCeil(Math.max(1, -lowest / 4)) : 0
    readonly property real maxV: 4 * niceCeil(Math.max(1, Math.max(1, ...values.filter(v => v !== null), showGoal ? target : 0) / 4))
    function bucketLabel(b, full) {
        const d = parseIso(b.start), loc = Qt.locale();
        switch (hist.bucket) {
        case "year": return String(d.getFullYear());
        case "month": return d.toLocaleDateString(loc, full ? "MMMM yyyy" : "MMM yy");
        case "week": return full ? qsTr("Week of %1").arg(d.toLocaleDateString(loc, "d MMM yyyy")) : d.toLocaleDateString(loc, "d MMM");
        default: return d.toLocaleDateString(loc, full ? "ddd d MMM yyyy" : "d MMM");
        }
    }

    // Painted background (also makes screenshots of the window faithful).
    Rectangle { anchors.fill: parent; color: Theme.window }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---- presets ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: hw.presets
                delegate: Button {
                    required property var modelData
                    required property int index
                    text: modelData.label
                    checkable: true
                    checked: hw.preset === index
                    flat: !checked
                    onClicked: hw.applyPreset(index)
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.tip
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ---- range, grouping, measure ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ToolButton { text: "‹"; onClicked: hw.shift(-1); ToolTip.visible: hovered; ToolTip.text: qsTr("Earlier") }
            Label { text: qsTr("From") }
            TextField {
                id: fromField
                Layout.preferredWidth: 110
                placeholderText: "YYYY-MM-DD"
                color: hw.validDate(text) ? Theme.text : Theme.danger
                onEditingFinished: if (hw.validDate(text)) { hw.preset = hw.customPreset; hw.reload(); }
            }
            Label { text: qsTr("to") }
            TextField {
                id: toField
                Layout.preferredWidth: 110
                placeholderText: "YYYY-MM-DD"
                color: hw.validDate(text) ? Theme.text : Theme.danger
                onEditingFinished: if (hw.validDate(text)) { hw.preset = hw.customPreset; hw.reload(); }
            }
            ToolButton { text: "›"; onClicked: hw.shift(1); ToolTip.visible: hovered; ToolTip.text: qsTr("Later") }
            Item { Layout.preferredWidth: 12 }
            Label { text: qsTr("Group by") }
            ComboBox {
                id: bucketBox
                model: [qsTr("Auto"), qsTr("Day"), qsTr("Week"), qsTr("Month"), qsTr("Year")]
                onActivated: { hw.preset = hw.customPreset; hw.reload(); }
            }
            Item { Layout.fillWidth: true }
            ComboBox {
                id: measureBox
                Layout.preferredWidth: 220
                model: [qsTr("Words written"), qsTr("Total words: manuscript"), qsTr("Total words: whole project")]
                currentIndex: hw.measure
                onActivated: (i) => hw.measure = i
            }
        }

        // ---- summary ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 32
            Repeater {
                model: hw.hist ? [
                    [qsTr("Written in range"), Api.fmtNumber(hw.hist.total_written)],
                    [qsTr("Days written"), Api.fmtNumber(hw.hist.days_written)],
                    [qsTr("Average per day"), Api.fmtNumber(Math.round(hw.hist.average_per_day))],
                    [qsTr("Best day"), hw.hist.best_day ? Api.fmtNumber(hw.hist.best_day[1]) + "  (" + hw.parseIso(hw.hist.best_day[0]).toLocaleDateString(Qt.locale(), "d MMM yyyy") + ")" : "—"]
                ] : []
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 0
                    Label { text: modelData[0]; color: Theme.subtext; font.pixelSize: 11 }
                    Label { text: modelData[1]; color: Theme.text; font.pixelSize: 18 }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ---- chart ----
        Rectangle {
            id: chartBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.base
            border.color: Theme.border
            radius: 4

            Item {
                id: plot
                anchors.fill: parent
                anchors.leftMargin: 64
                anchors.rightMargin: 16
                anchors.topMargin: 16
                anchors.bottomMargin: 34
                readonly property real slot: hw.buckets.length ? width / hw.buckets.length : width
                function yOf(v) { return height - (v - hw.minV) / (hw.maxV - hw.minV) * height; }

                // Grid and y-axis labels
                Repeater {
                    model: 5
                    delegate: Item {
                        required property int index
                        readonly property real v: hw.minV + (hw.maxV - hw.minV) * index / 4
                        y: plot.yOf(v)
                        width: plot.width
                        Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: index === 0 ? 1 : 0.5 }
                        Label {
                            x: -width - 8; y: -height / 2
                            text: Api.fmtNumber(Math.round(parent.v))
                            color: Theme.subtext; font.pixelSize: 11
                        }
                    }
                }
                // Zero line when there are negative bars
                Rectangle { visible: hw.minV < 0; y: plot.yOf(0); width: plot.width; height: 1; color: Theme.subtext }

                // Bars (words written)
                Repeater {
                    model: hw.lineMode ? [] : hw.buckets
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property real v: modelData.written
                        x: index * plot.slot + plot.slot * 0.12
                        width: Math.max(1, plot.slot * 0.76)
                        y: v >= 0 ? plot.yOf(v) : plot.yOf(0)
                        height: Math.max(v === 0 ? 0 : 1, Math.abs(plot.yOf(v) - plot.yOf(0)))
                        radius: Math.min(3, width / 3)
                        color: v < 0 ? Theme.danger : hw.showGoal && v >= hw.target ? Theme.ok : Theme.accent
                    }
                }
                // Goal line (daily target, day view)
                Shape {
                    visible: hw.showGoal
                    ShapePath {
                        strokeColor: Theme.ok; strokeWidth: 1.5; strokeStyle: ShapePath.DashLine; fillColor: "transparent"
                        startX: 0; startY: hw.showGoal ? plot.yOf(hw.target) : 0
                        PathLine { x: plot.width; y: hw.showGoal ? plot.yOf(hw.target) : 0 }
                    }
                }
                Label {
                    visible: hw.showGoal
                    x: plot.width - width; y: hw.showGoal ? plot.yOf(hw.target) - height - 2 : 0
                    text: qsTr("Daily goal %1").arg(Api.fmtNumber(hw.target || 0))
                    color: Theme.ok; font.pixelSize: 11
                }
                // Line (running totals)
                Shape {
                    visible: hw.lineMode
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.accent; strokeWidth: 2.5; fillColor: "transparent"; joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: hw.lineMode ? hw.values.map((v, i) => v === null ? null : Qt.point(i * plot.slot + plot.slot / 2, plot.yOf(v))).filter(p => p !== null) : []
                        }
                    }
                }
                Repeater {
                    model: hw.lineMode && hw.buckets.length <= 120 ? hw.values : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        visible: modelData !== null
                        width: 6; height: 6; radius: 3
                        color: Theme.accent
                        x: index * plot.slot + plot.slot / 2 - 3
                        y: modelData === null ? 0 : plot.yOf(modelData) - 3
                    }
                }

                // Hover areas and tooltips (one per bucket)
                Repeater {
                    model: hw.buckets
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        x: index * plot.slot
                        width: plot.slot
                        height: plot.height
                        HoverHandler { id: cellHover }
                        Rectangle { anchors.fill: parent; color: Theme.selection; opacity: cellHover.hovered ? 0.35 : 0 }
                        ToolTip.visible: cellHover.hovered
                        ToolTip.delay: 0
                        ToolTip.text: {
                            const b = cell.modelData;
                            const label = hw.bucketLabel(b, true) + (hw.hist.bucket !== "day" && b.start !== b.end ? "\n" + b.start + " – " + b.end : "");
                            const v = hw.values[cell.index];
                            return label + "\n" + (hw.lineMode ? (v === null ? qsTr("No total recorded yet") : qsTr("%1 words in total").arg(Api.fmtNumber(v)))
                                                               : qsTr("%1 words written").arg(Api.fmtNumber(b.written)));
                        }
                    }
                }

                // X-axis labels, thinned to fit
                Repeater {
                    model: hw.buckets
                    delegate: Label {
                        required property var modelData
                        required property int index
                        readonly property int every: Math.max(1, Math.ceil(hw.buckets.length / Math.max(1, Math.floor(plot.width / 70))))
                        visible: index % every === 0
                        text: hw.bucketLabel(modelData, false)
                        color: Theme.subtext
                        font.pixelSize: 11
                        x: index * plot.slot + plot.slot / 2 - width / 2
                        y: plot.height + 8
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: hw.hist !== null && !hw.lineMode && hw.hist.total_written === 0 && hw.hist.days_written === 0
                text: qsTr("No writing recorded in this range.")
                color: Theme.subtext
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.subtext
            font.pixelSize: 11
            text: qsTr("Words written are net words added to the manuscript each day (cuts count against them). Totals are recorded each time the project saves. History is kept in the project file.")
        }
    }
}
