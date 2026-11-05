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

    readonly property int rev: Wordloom.revision
    onRevChanged: reload()
    Component.onCompleted: reload()

    function reload() { rows = Api.get("binder", []); }
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
            placeholderText: qsTr("🔍 Search project…")
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
            Keys.onDeletePressed: if (pane.currentId) { Api.call("trash", pane.currentId); }
            Keys.onPressed: (e) => { if (e.key === Qt.Key_F2 && pane.currentId) { pane.startRename(pane.currentId); e.accepted = true; } }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 28
                readonly property bool isCurrent: modelData.id === pane.currentId
                readonly property bool isRoot: modelData.role !== null && modelData.role !== undefined

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    radius: 4
                    color: row.isCurrent ? Theme.selection : (hover.hovered ? Qt.rgba(0.5, 0.5, 0.5, 0.12) : "transparent")
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
                    Label { text: Theme.kindIcon(row.modelData.kind, row.modelData.role); font.pixelSize: 13 }
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

                    onPressed: (m) => { pressPos = Qt.point(m.x, m.y); list.forceActiveFocus(); if (m.button === Qt.LeftButton) pane.selected(row.modelData.id); }
                    onClicked: (m) => { if (m.button === Qt.RightButton) { pane.selected(row.modelData.id); menu.popup(); } }
                    onDoubleClicked: { if (row.isRoot) Api.call("toggleExpanded", row.modelData.id); else pane.startRename(row.modelData.id); }
                    onPositionChanged: (m) => {
                        if (row.isRoot || !(m.buttons & Qt.LeftButton)) return;
                        if (!dragging && Math.abs(m.y - pressPos.y) > 6) { dragging = true; ghost.text = row.modelData.title; }
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
                        const pos = pane.dropPos;
                        dragging = false; ghost.visible = false; pane.dropIndex = -1;
                        if (target && target.id !== row.modelData.id)
                            Api.call("dropOn", row.modelData.id, target.id, pos);
                    }
                }

                Menu {
                    id: menu
                    MenuItem { text: qsTr("New Document"); onTriggered: { const id = Api.call("add", row.modelData.id, "", "", row.isRoot || row.modelData.kind === "folder"); if (id) { pane.selected(id); pane.startRename(id); } } }
                    MenuItem { text: qsTr("New Folder"); onTriggered: { const id = Api.call("add", row.modelData.id, "folder", "", row.isRoot); if (id) { pane.selected(id); pane.startRename(id); } } }
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
                            MenuItem { required property string modelData; text: Theme.kindIcon(modelData, null) + " " + modelData; onTriggered: Api.call("setField", row.modelData.id, "kind", modelData) }
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

    Label {
        id: ghost
        visible: false
        z: 10
        padding: 4
        color: Theme.text
        background: Rectangle { color: Theme.base; border.color: Theme.accent; radius: 4; opacity: 0.9 }
    }
}
