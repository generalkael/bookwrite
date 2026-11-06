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
    // Filter: rows matching all of these are shown, with the folders they
    // sit in (dimmed) for context. Folding is ignored while filtering.
    property string filterText: ""
    property string filterLabel: ""     // label id, "none" for no label, "" for any
    property string filterStatus: ""    // likewise for status
    readonly property bool filtering: isFiltering()
    // A function, so refilter() (run from the change handlers below) never
    // sees a stale value of the binding.
    function isFiltering() { return filterText.trim() !== "" || filterLabel !== "" || filterStatus !== ""; }
    property int matchCount: 0
    property int matchWords: 0
    onFilterTextChanged: refilter()
    onFilterLabelChanged: refilter()
    onFilterStatusChanged: refilter()
    function clearFilter() { filterText = ""; filterLabel = ""; filterStatus = ""; }
    function matches(r) {
        const want = (f, v) => f === "" || (f === "none" ? !v : v === f);
        if (!want(filterLabel, r.label) || !want(filterStatus, r.status)) return false;
        const q = filterText.trim().toLowerCase();
        if (q === "") return true;
        const hay = [r.title, r.synopsis].concat(r.keywords || []).concat(Object.values(r.fields || {}));
        return hay.some(h => String(h).toLowerCase().indexOf(q) >= 0);
    }
    // Hide everything inside a collapsed folder, or apply the filter.
    function refilter() {
        if (isFiltering()) {
            const shown = [], stack = [];
            let count = 0, words = 0;
            for (const r of allRows) {
                stack.length = r.depth;
                if (matches(r)) {
                    // Folders above it that aren't shown yet, as context.
                    for (const a of stack) if (!a.shown) { a.shown = true; shown.push(Object.assign({}, a.row, { context: true })); }
                    shown.push(r);
                    count++;
                    words += r.words;
                    stack.push({ row: r, shown: true });
                } else {
                    stack.push({ row: r, shown: false });
                }
            }
            matchCount = count;
            matchWords = words;
            rows = shown;
            return;
        }
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
                TextField {
                    id: filterField
                    Layout.preferredWidth: 170
                    Layout.minimumWidth: 90
                    Layout.fillWidth: false
                    placeholderText: qsTr("Filter…")
                    text: ov.filterText
                    onTextEdited: ov.filterText = text
                    selectByMouse: true
                    Keys.onEscapePressed: ov.clearFilter()
                    ToolTip.visible: hovered && !activeFocus
                    ToolTip.text: qsTr("Show only items whose title, synopsis, keywords or custom fields contain this")
                }
                ComboBox {
                    id: labelFilter
                    Layout.preferredWidth: 130
                    readonly property var ids: ["", "none"].concat(ov.meta.labels.map(l => l.id))
                    model: [qsTr("Any Label"), qsTr("No Label")].concat(ov.meta.labels.map(l => l.name))
                    currentIndex: Math.max(0, ids.indexOf(ov.filterLabel))
                    onActivated: (i) => ov.filterLabel = ids[i]
                }
                ComboBox {
                    id: statusFilter
                    Layout.preferredWidth: 130
                    readonly property var ids: ["", "none"].concat(ov.meta.statuses.map(s => s.id))
                    model: [qsTr("Any Status"), qsTr("No Status")].concat(ov.meta.statuses.map(s => s.name))
                    currentIndex: Math.max(0, ids.indexOf(ov.filterStatus))
                    onActivated: (i) => ov.filterStatus = ids[i]
                }
                ToolButton { text: "✕"; visible: ov.filtering; font.pixelSize: 12; onClicked: ov.clearFilter(); ToolTip.visible: hovered; ToolTip.text: qsTr("Clear the filter (Esc)") }
                Item { Layout.fillWidth: true }
                ToolButton { text: qsTr("Collapse All"); enabled: !ov.filtering; font.pixelSize: 12; onClicked: ov.setAllCollapsed(true) }
                ToolButton { text: qsTr("Expand All"); enabled: !ov.filtering; font.pixelSize: 12; onClicked: ov.setAllCollapsed(false) }
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
                    // A folder shown only because something inside it matches.
                    opacity: r.modelData.context ? 0.5 : 1
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
                            text: r.modelData.child_count > 0 && !ov.filtering ? (ov.collapsed[r.modelData.id] ? "▸" : "▾") : ""
                            color: Theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea { anchors.fill: parent; enabled: r.modelData.child_count > 0 && !ov.filtering; cursorShape: Qt.PointingHandCursor; onClicked: ov.toggle(r.modelData.id) }
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
        // Counts for the item, or for what the filter shows.
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            elide: Text.ElideRight
            color: Theme.subtext
            font.pixelSize: 12
            text: ov.filtering
                ? qsTr("%1 of %2 items match · %3 words in them").arg(ov.matchCount).arg(ov.allRows.length).arg(Api.fmtNumber(ov.matchWords))
                : (ov.allRows.length === 1 ? qsTr("1 item") : qsTr("%1 items").arg(ov.allRows.length)) + " · " + qsTr("%1 words").arg(Api.fmtNumber(ov.allRows.filter(x => x.depth === 0).reduce((t, x) => t + x.total_words, 0)))
        }
    }
    Label {
        anchors.centerIn: parent
        visible: ov.allRows.length > 0 && ov.filtering && ov.matchCount === 0
        text: qsTr("Nothing here matches the filter.")
        color: Theme.subtext
    }
    Label {
        anchors.centerIn: parent
        visible: ov.allRows.length === 0
        text: qsTr("Nothing below this item yet.")
        color: Theme.subtext
    }
}
