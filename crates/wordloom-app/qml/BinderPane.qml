import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// The binder: project tree with drag-and-drop, inline rename, keyboard
// navigation and a project search field.
Rectangle {
    id: pane
    color: Theme.panel

    property string currentId: ""
    property var rows: []
    property string renamingId: ""
    property alias searchText: searchField.text
    property int dropIndex: -1
    property string dropPos: ""
    signal selected(string id)
    signal activated(string id)
    signal openInSplit(string id)
    signal filesDropped(var urls)

    readonly property int rev: Wordloom.revision
    onRevChanged: reload()
    Component.onCompleted: reload()

    function reload() {
        rows = Api.get("binder", []);
        // Forget picks that went away (trashed, undone, collapsed out of view).
        const keep = {};
        for (const r of rows) if (picked[r.id]) keep[r.id] = true;
        if (Object.keys(keep).length !== pickCount) picked = keep;
    }

    // ---- Multi-selection: Ctrl+click adds or removes an item, Shift+click
    // picks a range. Right-click on a picked item, or Delete, acts on all
    // of them (one undo step); a plain click or Esc goes back to one.
    property var picked: ({})
    readonly property int pickCount: Object.keys(picked).length
    function pickedIds() { return rows.filter(r => picked[r.id]).map(r => r.id); }
    function clearPicks() { if (pickCount) picked = {}; }
    function togglePick(id) {
        const p = Object.assign({}, picked);
        // Starting a multi-selection includes the item already selected.
        if (!pickCount && currentId && currentId !== id) p[currentId] = true;
        if (p[id]) delete p[id]; else p[id] = true;
        picked = p;
    }
    function pickRange(id) {
        const a = rowIndex(currentId), b = rowIndex(id);
        if (a < 0 || b < 0) { togglePick(id); return; }
        const p = {};
        for (let i = Math.min(a, b); i <= Math.max(a, b); ++i) p[rows[i].id] = true;
        picked = p;
    }
    function trashPicked() {
        const ids = pickedIds();
        if (!ids.length) return;
        const n = Api.call("trashMany", ids);
        if (n !== undefined) { picked = {}; Api.say(qsTr("Moved %1 item(s) to the Trash").arg(n)); }
    }
    // The middle of item `id`'s row, in window coordinates (self-test).
    function rowPoint(id) {
        const i = rowIndex(id);
        if (i < 0) return null;
        list.positionViewAtIndex(i, ListView.Contain);
        const it = list.itemAtIndex(i);
        return it ? it.mapToItem(null, it.width / 2, it.height / 2) : null;
    }
    function setPicked(field, value) { Api.call("setFieldMany", pickedIds(), field, value); }
    function rowIndex(id) { for (let i = 0; i < rows.length; ++i) if (rows[i].id === id) return i; return -1; }
    function startRename(id) { renamingId = id; const i = rowIndex(id); if (i >= 0) list.positionViewAtIndex(i, ListView.Contain); }
    function focusSearch() { searchField.forceActiveFocus(); searchField.selectAll(); }
    function step(delta) {
        const i = rowIndex(currentId);
        const j = Math.max(0, Math.min(rows.length - 1, i + delta));
        if (rows.length) { selected(rows[j].id); list.positionViewAtIndex(j, ListView.Contain); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.margins: 6
            placeholderText: qsTr("Search project…")
            selectByMouse: true
            Keys.onEscapePressed: { text = ""; list.forceActiveFocus(); }
        }

        SearchPane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: searchField.text.trim().length > 0
            query: searchField.text
            onChosen: (id) => pane.activated(id)
        }

        ListView {
            id: list
            visible: searchField.text.trim().length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: pane.rows
            focus: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Keys.onUpPressed: (e) => { if (e.modifiers & Qt.ControlModifier) Api.call("shift", pane.currentId, -1); else pane.step(-1); }
            Keys.onDownPressed: (e) => { if (e.modifiers & Qt.ControlModifier) Api.call("shift", pane.currentId, 1); else pane.step(1); }
            Keys.onRightPressed: (e) => {
                if (e.modifiers & Qt.ControlModifier) { Api.call("indent", pane.currentId); return; }
                const r = pane.rows[pane.rowIndex(pane.currentId)];
                if (r && r.has_children && !r.expanded) Api.call("toggleExpanded", r.id);
            }
            Keys.onLeftPressed: (e) => {
                if (e.modifiers & Qt.ControlModifier) { Api.call("outdent", pane.currentId); return; }
                const r = pane.rows[pane.rowIndex(pane.currentId)];
                if (r && r.has_children && r.expanded) Api.call("toggleExpanded", r.id);
            }
            Keys.onReturnPressed: if (pane.currentId) pane.activated(pane.currentId)
            Keys.onDeletePressed: { if (pane.pickCount > 1) pane.trashPicked(); else if (pane.currentId) Api.call("trash", pane.currentId); }
            Keys.onEscapePressed: pane.clearPicks()
            Keys.onPressed: (e) => { if (e.key === Qt.Key_F2 && pane.currentId) { pane.startRename(pane.currentId); e.accepted = true; } }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 28
                readonly property bool isCurrent: modelData.id === pane.currentId
                readonly property bool isPicked: pane.pickCount > 0 && !!pane.picked[modelData.id]
                readonly property bool isRoot: modelData.role !== null && modelData.role !== undefined

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    radius: 4
                    color: row.isCurrent || row.isPicked ? Theme.selection : (hover.hovered ? Qt.rgba(0.5, 0.5, 0.5, 0.12) : "transparent")
                    border.width: row.isPicked ? 1 : 0
                    border.color: Theme.accent
                }
                // drop indicator
                Rectangle {
                    visible: pane.dropIndex === row.index
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8 + row.modelData.depth * 16
                    height: pane.dropPos === "inside" ? parent.height : 2
                    y: pane.dropPos === "after" ? parent.height - 2 : 0
                    color: pane.dropPos === "inside" ? "transparent" : Theme.accent
                    border.color: Theme.accent
                    border.width: pane.dropPos === "inside" ? 2 : 0
                    radius: 4
                }
                HoverHandler { id: hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 + row.modelData.depth * 16
                    anchors.rightMargin: 8
                    spacing: 4
                    Label {
                        text: row.modelData.has_children ? (row.modelData.expanded ? "▾" : "▸") : ""
                        color: Theme.subtext
                        Layout.preferredWidth: 12
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            enabled: row.modelData.has_children
                            onClicked: Api.call("toggleExpanded", row.modelData.id)
                        }
                    }
                    KindIcon { kind: row.modelData.kind; role: row.modelData.role || "" }
                    Rectangle {
                        visible: !!row.modelData.label_color
                        width: 8; height: 8; radius: 4
                        color: row.modelData.label_color || "transparent"
                    }
                    Label {
                        visible: pane.renamingId !== row.modelData.id
                        text: row.modelData.title
                        color: Theme.text
                        font.bold: row.isRoot
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    // Progress toward this item's word target.
                    Rectangle {
                        id: targetBar
                        visible: !!row.modelData.target_words && pane.renamingId !== row.modelData.id
                        readonly property real p: row.modelData.target_words ? Math.min(1, (row.modelData.words || 0) / row.modelData.target_words) : 0
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 5
                        Layout.rightMargin: 4
                        radius: 2
                        color: Theme.border
                        Rectangle {
                            width: parent.width * targetBar.p
                            height: parent.height
                            radius: 2
                            color: targetBar.p >= 1 ? Theme.ok : Theme.accent
                        }
                        HoverHandler { id: targetHover }
                        ToolTip.visible: targetHover.hovered
                        ToolTip.text: row.modelData.target_words ? qsTr("%1 of %2 words (%3%)").arg(Api.fmtNumber(row.modelData.words || 0)).arg(Api.fmtNumber(row.modelData.target_words)).arg(Math.round(targetBar.p * 100)) : ""
                    }
                    TextField {
                        id: renameField
                        visible: pane.renamingId === row.modelData.id
                        Layout.fillWidth: true
                        text: row.modelData.title
                        selectByMouse: true
                        onVisibleChanged: if (visible) { text = row.modelData.title; forceActiveFocus(); selectAll(); }
                        onAccepted: { Api.call("setField", row.modelData.id, "title", text); pane.renamingId = ""; list.forceActiveFocus(); }
                        Keys.onEscapePressed: { pane.renamingId = ""; list.forceActiveFocus(); }
                        onActiveFocusChanged: if (!activeFocus && visible) { Api.call("setField", row.modelData.id, "title", text); pane.renamingId = ""; }
                    }
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    anchors.leftMargin: 8 + row.modelData.depth * 16 + 16
                    enabled: pane.renamingId !== row.modelData.id
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property point pressPos
                    property bool dragging: false
                    // A plain press on one of several picked items: it may
                    // start dragging them all; a click without a drag goes
                    // back to just this item.
                    property bool pressedPicked: false

                    onPressed: (m) => {
                        pressPos = Qt.point(m.x, m.y);
                        list.forceActiveFocus();
                        if (m.button !== Qt.LeftButton) return;
                        if (m.modifiers & Qt.ControlModifier) { if (!row.isRoot) pane.togglePick(row.modelData.id); return; }
                        if (m.modifiers & Qt.ShiftModifier) { pane.pickRange(row.modelData.id); return; }
                        pressedPicked = row.isPicked && pane.pickCount > 1;
                        if (pressedPicked) return;
                        pane.clearPicks();
                        pane.selected(row.modelData.id);
                    }
                    onClicked: (m) => {
                        if (m.button !== Qt.RightButton) return;
                        if (row.isPicked && pane.pickCount > 1) { pickMenu.popup(); return; }
                        pane.clearPicks();
                        pane.selected(row.modelData.id);
                        menu.popup();
                    }
                    onDoubleClicked: { if (row.isRoot) Api.call("toggleExpanded", row.modelData.id); else pane.startRename(row.modelData.id); }
                    onPositionChanged: (m) => {
                        if (row.isRoot || !(m.buttons & Qt.LeftButton)) return;
                        if (!dragging && Math.abs(m.y - pressPos.y) > 6) {
                            dragging = true;
                            ghost.text = pressedPicked ? qsTr("%1 items").arg(pane.pickCount) : row.modelData.title;
                        }
                        if (!dragging) return;
                        const p = mapToItem(list.contentItem, m.x, m.y);
                        const g = mapToItem(pane, m.x, m.y);
                        ghost.x = g.x + 12; ghost.y = g.y - 10;
                        const i = list.indexAt(10, p.y);
                        ghost.visible = true;
                        if (i < 0) { pane.dropIndex = -1; return; }
                        const item = list.itemAtIndex(i);
                        const rel = p.y - item.y;
                        const target = pane.rows[i];
                        pane.dropPos = (target.role || (rel > item.height * 0.3 && rel < item.height * 0.7))
                            ? "inside" : (rel <= item.height * 0.3 ? "before" : "after");
                        pane.dropIndex = i;
                    }
                    onReleased: {
                        const target = dragging && pane.dropIndex >= 0 ? pane.rows[pane.dropIndex] : null;
                        const pos = pane.dropPos, wasDrag = dragging, many = pressedPicked;
                        dragging = false; ghost.visible = false; pane.dropIndex = -1; pressedPicked = false;
                        if (many && !wasDrag) { pane.clearPicks(); pane.selected(row.modelData.id); return; }
                        if (!target) return;
                        // Several picked: they all move, in binder order (one undo step).
                        if (many) { if (!pane.picked[target.id]) Api.call("moveMany", pane.pickedIds(), target.id, pos); }
                        else if (target.id !== row.modelData.id) Api.call("dropOn", row.modelData.id, target.id, pos);
                    }
                }

                Menu {
                    id: menu
                    MenuItem { text: qsTr("New Document"); onTriggered: { const id = Api.call("add", row.modelData.id, "", "", row.isRoot || row.modelData.kind === "folder"); if (id) { pane.selected(id); pane.startRename(id); } } }
                    MenuItem { text: qsTr("New Folder"); onTriggered: { const id = Api.call("add", row.modelData.id, "folder", "", row.isRoot); if (id) { pane.selected(id); pane.startRename(id); } } }
                    MenuSeparator {}
                    MenuItem { text: qsTr("Open in Split Editor"); enabled: !row.isRoot; onTriggered: pane.openInSplit(row.modelData.id) }
                    MenuSeparator {}
                    MenuItem { text: qsTr("Rename"); enabled: !row.isRoot; onTriggered: pane.startRename(row.modelData.id) }
                    MenuItem { text: qsTr("Duplicate"); enabled: !row.isRoot; onTriggered: Api.call("duplicate", row.modelData.id) }
                    MenuItem { text: qsTr("Move Up"); enabled: !row.isRoot; onTriggered: Api.call("shift", row.modelData.id, -1) }
                    MenuItem { text: qsTr("Move Down"); enabled: !row.isRoot; onTriggered: Api.call("shift", row.modelData.id, 1) }
                    MenuItem { text: qsTr("Indent"); enabled: !row.isRoot; onTriggered: Api.call("indent", row.modelData.id) }
                    MenuItem { text: qsTr("Outdent"); enabled: !row.isRoot; onTriggered: Api.call("outdent", row.modelData.id) }
                    MenuSeparator {}
                    Menu {
                        title: qsTr("Convert to")
                        enabled: !row.isRoot
                        Repeater {
                            model: ["text", "folder", "character", "place", "research", "note"]
                            MenuItem { required property string modelData; text: modelData; icon.source: Theme.kindIcon(modelData, null); icon.color: "transparent"; onTriggered: Api.call("setField", row.modelData.id, "kind", modelData) }
                        }
                    }
                    MenuItem { text: qsTr("Expand All"); onTriggered: Api.call("setAllExpanded", true) }
                    MenuItem { text: qsTr("Collapse All"); onTriggered: Api.call("setAllExpanded", false) }
                    MenuSeparator {}
                    MenuItem { text: qsTr("Move to Trash"); enabled: !row.isRoot; onTriggered: Api.call("trash", row.modelData.id) }
                    MenuItem { text: qsTr("Empty Trash"); visible: row.modelData.role === "trash"; height: visible ? implicitHeight : 0; onTriggered: Api.call("emptyTrash") }
                }
            }
        }
    }

    // The right-click menu for several picked items.
    Menu {
        id: pickMenu
        property var meta: ({ labels: [], statuses: [] })
        onAboutToShow: meta = Api.get("labels", { labels: [], statuses: [] })
        MenuItem { text: qsTr("%1 items selected").arg(pane.pickCount); enabled: false }
        MenuSeparator {}
        Menu {
            id: pickLabels
            title: qsTr("Label")
            MenuItem { text: qsTr("No Label"); onTriggered: pane.setPicked("label", "") }
            Instantiator {
                model: pickMenu.meta.labels
                delegate: MenuItem { required property var modelData; text: modelData.name; onTriggered: pane.setPicked("label", modelData.id) }
                onObjectAdded: (i, o) => pickLabels.insertItem(1 + i, o)
                onObjectRemoved: (i, o) => pickLabels.removeItem(o)
            }
        }
        Menu {
            id: pickStatuses
            title: qsTr("Status")
            MenuItem { text: qsTr("No Status"); onTriggered: pane.setPicked("status", "") }
            Instantiator {
                model: pickMenu.meta.statuses
                delegate: MenuItem { required property var modelData; text: modelData.name; onTriggered: pane.setPicked("status", modelData.id) }
                onObjectAdded: (i, o) => pickStatuses.insertItem(1 + i, o)
                onObjectRemoved: (i, o) => pickStatuses.removeItem(o)
            }
        }
        MenuItem { text: qsTr("Include in Compile"); onTriggered: pane.setPicked("include_in_compile", true) }
        MenuItem { text: qsTr("Exclude from Compile"); onTriggered: pane.setPicked("include_in_compile", false) }
        MenuSeparator {}
        MenuItem { text: qsTr("Move to Trash"); onTriggered: pane.trashPicked() }
        MenuItem { text: qsTr("Select Just One"); onTriggered: pane.clearPicks() }
    }

    // Files dragged in from the desktop are imported as research items.
    DropArea {
        anchors.fill: parent
        onEntered: (drag) => drag.accepted = drag.hasUrls
        onDropped: (drop) => { if (drop.hasUrls) { pane.filesDropped(drop.urls); drop.accept(Qt.CopyAction); } }
        Rectangle {
            anchors.fill: parent
            visible: parent.containsDrag
            color: "transparent"
            border.color: Theme.accent
            border.width: 2
        }
    }

    Label {
        id: ghost
        visible: false
        z: 10
        padding: 4
        color: Theme.text
        background: Rectangle { color: Theme.base; border.color: Theme.accent; radius: 4; opacity: 0.9 }
    }
}
