import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import com.wordloom.app

// Tabular outline of everything under the selected item, with synopsis,
// label, status, word counts and progress towards per-document targets.
// Folders collapse with their ▸ / ▾ toggle; the Columns menu adds keywords
// and any custom field (POV, Setting, …) used below the item.
Rectangle {
    id: ov
    color: Theme.base

    property string nodeId: ""
    property var node: null
    property bool active: false
    property var rows: []          // the rows shown (collapsed folders hide their contents)
    property var allRows: []       // every row below the item
    property var meta: ({ labels: [], statuses: [] })
    property var collapsed: ({})   // folder id → true while collapsed (this session only)
    // Extra columns, "keywords" or "field:<name>", remembered between runs.
    property string columnsSaved: "[]"
    readonly property var columns: { try { return JSON.parse(columnsSaved) || []; } catch (e) { return []; } }
    readonly property var fieldKeys: {
        const keys = {};
        for (const r of allRows) for (const k in (r.fields || {})) keys[k] = true;
        return Object.keys(keys).sort((a, b) => a.localeCompare(b));
    }
    signal openRequested(string id)

    Settings {
        category: "outliner"
        property alias columns: ov.columnsSaved
    }

    readonly property int rev: Wordloom.revision
    onRevChanged: if (active) reload()
    onActiveChanged: if (active) reload()
    onNodeIdChanged: if (active) reload()

    function walk(id, depth, out) {
        for (const k of Api.get("children", [], id)) {
            k.depth = depth;
            out.push(k);
            if (k.child_count > 0) walk(k.id, depth + 1, out);
        }
    }
    function reload() {
        meta = Api.get("labels", { labels: [], statuses: [] });
        const out = [];
        const root = node ? node.id : Api.get("rootId", "", "manuscript");
        if (root) walk(root, 0, out);
        allRows = out;
        refilter();
    }
    // Hide everything inside a collapsed folder.
    function refilter() {
        const shown = [];
        let hideBelow = -1;
        for (const r of allRows) {
            if (hideBelow >= 0 && r.depth > hideBelow) continue;
            hideBelow = -1;
            shown.push(r);
            if (collapsed[r.id] && r.child_count > 0) hideBelow = r.depth;
        }
        rows = shown;
    }
    function toggle(id) {
        const c = Object.assign({}, collapsed);
        if (c[id]) delete c[id]; else c[id] = true;
        collapsed = c;
        refilter();
    }
    // Collapse (or expand) every folder at once.
    function setAllCollapsed(on) {
        const c = {};
        if (on) for (const r of allRows) if (r.child_count > 0) c[r.id] = true;
        collapsed = c;
        refilter();
    }
    function hasColumn(key) { return columns.indexOf(key) >= 0; }
    function toggleColumn(key) {
        columnsSaved = JSON.stringify(hasColumn(key) ? columns.filter(c => c !== key) : columns.concat([key]));
    }
    function columnTitle(key) { return key === "keywords" ? qsTr("Keywords") : key.substring(6); }
    function cellText(row, key) {
        if (key === "keywords") return (row.keywords || []).join(", ");
        return (row.fields || {})[key.substring(6)] || "";
    }
    // Save an edited extra cell (keywords are comma separated).
    function setCell(row, key, text) {
        if (text === cellText(row, key)) return;
        Api.call("setField", row.id, key, text);
    }

    readonly property var widths: [250, 0, 120, 120, 64, 64, 80]
    readonly property int extraWidth: 120

    // Narrowest the table gets before it scrolls sideways.
    readonly property int synopsisMin: 220
    readonly property int tableWidth: Math.max(list.width,
        20 + widths[0] + synopsisMin + columns.length * extraWidth + widths[2] + widths[3] + widths[4] + widths[5] + widths[6] + 8 * (6 + columns.length))

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        // Above the table, so it stays in view however wide the table is.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: Theme.base
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Theme.subtext
                    text: (ov.allRows.length === 1 ? qsTr("1 item") : qsTr("%1 items").arg(ov.allRows.length)) + " · " + qsTr("%1 words").arg(Api.fmtNumber(ov.allRows.filter(x => x.depth === 0).reduce((t, x) => t + x.total_words, 0)))
                }
                ToolButton { text: qsTr("Collapse All"); font.pixelSize: 12; onClicked: ov.setAllCollapsed(true) }
                ToolButton { text: qsTr("Expand All"); font.pixelSize: 12; onClicked: ov.setAllCollapsed(false) }
                ToolButton {
                    text: qsTr("Columns ▾")
                    font.pixelSize: 12
                    onClicked: columnMenu.popup()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Show keywords or custom fields (POV, Setting, …) as columns")
                    Menu {
                        id: columnMenu
                        MenuItem { text: qsTr("Keywords"); checkable: true; checked: ov.hasColumn("keywords"); onTriggered: ov.toggleColumn("keywords") }
                        MenuSeparator { visible: ov.fieldKeys.length > 0 }
                        Instantiator {
                            model: ov.fieldKeys
                            delegate: MenuItem {
                                required property var modelData
                                text: modelData
                                checkable: true
                                checked: ov.hasColumn("field:" + modelData)
                                onTriggered: ov.toggleColumn("field:" + modelData)
                            }
                            onObjectAdded: (index, object) => columnMenu.insertItem(2 + index, object)
                            onObjectRemoved: (index, object) => columnMenu.removeItem(object)
                        }
                        MenuItem { enabled: false; visible: ov.fieldKeys.length === 0; height: visible ? implicitHeight : 0; text: qsTr("(no custom fields below this item)") }
                    }
                }
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ov.rows
            contentWidth: ov.tableWidth
            flickableDirection: Flickable.AutoFlickIfNeeded
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            // Always shown when the table is wider than the pane, so the
            // columns past the edge are discoverable.
            ScrollBar.horizontal: ScrollBar { policy: list.contentWidth > list.width + 1 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }
            headerPositioning: ListView.OverlayHeader
            header: Rectangle {
                z: 3
                width: ov.tableWidth
                height: 30
                color: Theme.panel
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Label { text: qsTr("Title"); font.bold: true; Layout.preferredWidth: ov.widths[0]; Layout.minimumWidth: ov.widths[0]; color: Theme.subtext }
                    Label { text: qsTr("Synopsis"); font.bold: true; Layout.fillWidth: true; Layout.minimumWidth: 80; color: Theme.subtext }
                    Repeater {
                        model: ov.columns
                        Label { required property var modelData; text: ov.columnTitle(modelData); font.bold: true; elide: Text.ElideRight; Layout.preferredWidth: ov.extraWidth; color: Theme.subtext }
                    }
                    Label { text: qsTr("Label"); font.bold: true; Layout.preferredWidth: ov.widths[2]; color: Theme.subtext }
                    Label { text: qsTr("Status"); font.bold: true; Layout.preferredWidth: ov.widths[3]; color: Theme.subtext }
                    Label { text: qsTr("Words"); font.bold: true; Layout.preferredWidth: ov.widths[4]; horizontalAlignment: Text.AlignRight; color: Theme.subtext }
                    Label { text: qsTr("Target"); font.bold: true; Layout.preferredWidth: ov.widths[5]; horizontalAlignment: Text.AlignRight; color: Theme.subtext }
                    Label { text: qsTr("Progress"); font.bold: true; Layout.preferredWidth: ov.widths[6]; color: Theme.subtext }
                }
            }
            delegate: Rectangle {
                id: r
                required property var modelData
                required property int index
                width: ov.tableWidth
                height: Math.max(34, syn.implicitHeight + 10)
                color: index % 2 ? Theme.panel : Theme.base
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    RowLayout {
                        Layout.preferredWidth: ov.widths[0]
                        Layout.minimumWidth: ov.widths[0]
                        Layout.maximumWidth: ov.widths[0]
                        spacing: 2
                        Item { Layout.preferredWidth: r.modelData.depth * 14 }
                        // ▸ / ▾ for folders with something inside.
                        Label {
                            Layout.preferredWidth: 14
                            text: r.modelData.child_count > 0 ? (ov.collapsed[r.modelData.id] ? "▸" : "▾") : ""
                            color: Theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea { anchors.fill: parent; enabled: r.modelData.child_count > 0; cursorShape: Qt.PointingHandCursor; onClicked: ov.toggle(r.modelData.id) }
                        }
                        KindIcon { kind: r.modelData.kind }
                        Label {
                            text: r.modelData.title; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true
                            font.bold: r.modelData.kind === "folder"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onDoubleClicked: ov.openRequested(r.modelData.id) }
                        }
                    }
                    TextField {
                        id: syn
                        Layout.fillWidth: true
                        Layout.minimumWidth: 80
                        Component.onCompleted: cursorPosition = 0
                        onTextChanged: if (!activeFocus) cursorPosition = 0
                        text: r.modelData.synopsis
                        placeholderText: "—"
                        background: null
                        color: Theme.text
                        selectByMouse: true
                        onEditingFinished: if (text !== r.modelData.synopsis) Api.call("setField", r.modelData.id, "synopsis", text)
                    }
                    Repeater {
                        model: ov.columns
                        TextField {
                            required property var modelData
                            Layout.preferredWidth: ov.extraWidth
                            text: ov.cellText(r.modelData, modelData)
                            placeholderText: "—"
                            background: null
                            color: Theme.text
                            selectByMouse: true
                            Component.onCompleted: cursorPosition = 0
                            onEditingFinished: ov.setCell(r.modelData, modelData, text)
                        }
                    }
                    ComboBox {
                        Layout.preferredWidth: ov.widths[2]
                        model: [qsTr("No Label")].concat(ov.meta.labels.map(l => l.name))
                        currentIndex: 1 + ov.meta.labels.findIndex(l => l.id === r.modelData.label)
                        onActivated: (i) => Api.call("setField", r.modelData.id, "label", i === 0 ? "" : ov.meta.labels[i - 1].id)
                    }
                    ComboBox {
                        Layout.preferredWidth: ov.widths[3]
                        model: [qsTr("No Status")].concat(ov.meta.statuses.map(s => s.name))
                        currentIndex: 1 + ov.meta.statuses.findIndex(s => s.id === r.modelData.status)
                        onActivated: (i) => Api.call("setField", r.modelData.id, "status", i === 0 ? "" : ov.meta.statuses[i - 1].id)
                    }
                    Label { text: Api.fmtNumber(r.modelData.total_words); Layout.preferredWidth: ov.widths[4]; horizontalAlignment: Text.AlignRight; color: Theme.text }
                    TextField {
                        Layout.preferredWidth: ov.widths[5]
                        text: r.modelData.target_words ? String(r.modelData.target_words) : ""
                        placeholderText: "—"
                        horizontalAlignment: Text.AlignRight
                        validator: IntValidator { bottom: 0 }
                        background: null
                        color: Theme.text
                        onEditingFinished: Api.call("setField", r.modelData.id, "target_words", text)
                    }
                    ProgressBar {
                        Layout.preferredWidth: ov.widths[6]
                        visible: !!r.modelData.target_words
                        from: 0; to: 1
                        value: r.modelData.target_words ? Math.min(1, r.modelData.total_words / r.modelData.target_words) : 0
                    }
                    Item { Layout.preferredWidth: ov.widths[6]; visible: !r.modelData.target_words }
                }
            }
        }
    }
    Label {
        anchors.centerIn: parent
        visible: ov.allRows.length === 0
        text: qsTr("Nothing below this item yet.")
        color: Theme.subtext
    }
}
