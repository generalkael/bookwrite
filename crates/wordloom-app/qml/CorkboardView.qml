import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Index cards for the children of the selected folder (or the siblings of
// the selected document). Synopses are edited right on the card.
Rectangle {
    id: cb
    color: Theme.cork

    property string nodeId: ""
    property var node: null
    property bool active: false
    property var cards: []
    property string containerId: ""
    property string containerTitle: ""
    property int cardWidth: 230
    signal openRequested(string id)
    signal selectRequested(string id)

    readonly property int rev: Wordloom.revision
    onRevChanged: if (active) reload()
    onActiveChanged: if (active) reload()
    onNodeIdChanged: if (active) reload()

    function reload() {
        if (!node) { cards = []; containerId = ""; return; }
        let cid = node.id;
        if (node.child_count === 0 && !node.is_root) {
            // A leaf: show it among its siblings.
            cid = parentOf(node.id);
        }
        containerId = cid || "";
        const info = containerId ? Api.get("nodeInfo", null, containerId) : null;
        containerTitle = info ? info.title : "";
        cards = containerId ? Api.get("children", [], containerId) : [];
    }
    // ---- drag and drop: move a card before / after another, or into a folder card ----
    property string dragId: ""
    property string dragTitle: ""
    property point dragPos: Qt.point(0, 0)   // pointer, in cb's coordinates
    property int dropIndex: -1
    property string dropMode: ""             // "before", "after", "inside" or "" (no move)
    function startDrag(id, title) { dragId = id; dragTitle = title; dropIndex = -1; dropMode = ""; }
    // `scenePos`: the pointer in window coordinates.
    function updateDrag(scenePos) {
        dragPos = cb.mapFromItem(null, scenePos.x, scenePos.y);
        const p = grid.contentItem.mapFromItem(null, scenePos.x, scenePos.y);
        let i = grid.indexAt(p.x, p.y);
        let mode = "";
        if (i < 0) {
            // Past the last card: drop at the end.
            if (cards.length && p.y >= 0) { i = cards.length - 1; mode = "after"; }
        } else {
            const item = grid.itemAtIndex(i);
            const fx = item ? (p.x - item.x) / item.width : 0.5;
            if (cards[i].kind === "folder" && fx > 0.3 && fx < 0.7) mode = "inside";
            else mode = fx < 0.5 ? "before" : "after";
        }
        // Dropping a card next to (or onto) itself changes nothing.
        const from = cards.findIndex(c => c.id === dragId);
        if (i === from || (mode === "after" && i === from - 1) || (mode === "before" && i === from + 1)) mode = "";
        dropIndex = i;
        dropMode = mode;
    }
    // ---- keyboard: ← → ↑ ↓ Home End move a highlight between cards, Enter
    // opens (a folder on the board, a document in the editor), Backspace
    // goes up a folder, Ctrl+arrows move the card, Delete trashes it ----
    property string keyId: ""                // the highlighted card
    property string keyAfterReload: ""       // highlight this card once the board reloads
    readonly property int columns: Math.max(1, Math.floor(grid.width / grid.cellWidth))
    readonly property int keyIndex: cards.findIndex(c => c.id === keyId)
    onCardsChanged: {
        const want = [keyAfterReload, keyId, nodeId].find(id => id && cards.some(c => c.id === id));
        keyId = want || (cards.length ? cards[0].id : "");
        keyAfterReload = "";
    }
    function highlight(i) {
        if (!cards.length) return;
        i = Math.max(0, Math.min(cards.length - 1, i));
        keyId = cards[i].id;
        grid.positionViewAtIndex(i, GridView.Contain);
    }
    function handleKey(e) {
        const i = keyIndex, ctrl = e.modifiers & Qt.ControlModifier;
        const step = (e.key === Qt.Key_Left) ? -1 : (e.key === Qt.Key_Right) ? 1
                   : (e.key === Qt.Key_Up) ? -columns : (e.key === Qt.Key_Down) ? columns : 0;
        if (step !== 0) {
            // Ctrl: one place earlier or later (the binder's order).
            if (ctrl) { if (i >= 0) Api.call("shift", cards[i].id, step < 0 ? -1 : 1); }
            else highlight(i < 0 ? 0 : i + step);
            return true;
        }
        if (e.key === Qt.Key_Home) { highlight(0); return true; }
        if (e.key === Qt.Key_End) { highlight(cards.length - 1); return true; }
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && i >= 0) {
            if (cards[i].child_count > 0) selectRequested(cards[i].id); else openRequested(cards[i].id);
            return true;
        }
        if (e.key === Qt.Key_Backspace) {
            const up = parentOf(containerId);
            if (up) { keyAfterReload = containerId; selectRequested(up); }
            return true;
        }
        if (e.key === Qt.Key_Delete && i >= 0) {
            const next = cards[i + 1] || cards[i - 1];
            keyAfterReload = next ? next.id : "";
            Api.call("trash", cards[i].id);
            return true;
        }
        return false;
    }
    function focusBoard() { grid.forceActiveFocus(); }

    // A spot on card `i` that isn't text (just inside its left edge), in
    // window coordinates: where a real drag can start.
    function cardGrip(i) { const it = grid.itemAtIndex(i); return it ? it.mapToItem(null, 12, it.height / 2) : null; }
    // A point on card `i` (fraction `fx` across it), in window coordinates.
    function cardPoint(i, fx) { const it = grid.itemAtIndex(i); return it ? it.mapToItem(null, it.width * fx, it.height / 2) : null; }
    // Returns true if the card moved.
    function finishDrag() {
        const id = dragId, mode = dropMode, target = dropIndex >= 0 && dropIndex < cards.length ? cards[dropIndex].id : "";
        dragId = ""; dropIndex = -1; dropMode = "";
        if (!id || !mode || !target) return false;
        return Api.call("dropOn", id, target, mode) !== undefined;
    }

    // Find the parent by scanning the binder (cheap for typical projects).
    function parentOf(id) {
        const rows = Api.get("binder", []);
        const i = rows.findIndex(r => r.id === id);
        for (let j = i - 1; j >= 0; --j) if (rows[j].depth < rows[i].depth) return rows[j].id;
        return "";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: Qt.darker(Theme.cork, 1.08)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Label { text: "▦  " + cb.containerTitle; font.bold: true; color: Theme.dark ? Theme.text : "#3b2b17"; Layout.fillWidth: true }
                Label { text: qsTr("Card size"); color: Theme.dark ? Theme.subtext : "#3b2b17" }
                Slider { from: 170; to: 360; value: cb.cardWidth; onMoved: cb.cardWidth = value; Layout.preferredWidth: 120 }
                Button {
                    text: qsTr("+ Card")
                    enabled: cb.containerId !== ""
                    onClicked: { const id = Api.call("add", cb.containerId, "", "", true); if (id) cb.selectRequested(id); }
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            clip: true
            cellWidth: cb.cardWidth + 16
            cellHeight: cb.cardWidth * 0.66 + 16
            model: cb.cards
            ScrollBar.vertical: ScrollBar {}
            activeFocusOnTab: true
            Keys.onPressed: (e) => { if (cb.handleKey(e)) e.accepted = true; }
            // Shows that the keys go to the board.
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: grid.activeFocus ? 2 : 0
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                radius: 4
                z: -1
            }

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: card
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.card
                    radius: 3
                    border.width: cell.modelData.id === cb.nodeId ? 2 : 1
                    border.color: cell.modelData.id === cb.nodeId ? Theme.accent : Qt.rgba(0, 0, 0, 0.18)
                    opacity: cell.modelData.id === cb.dragId ? 0.35 : cell.modelData.include_in_compile ? 1 : 0.7

                    // Label colour strip
                    Rectangle {
                        width: parent.width; height: 5; radius: 2
                        color: cell.modelData.label_color || "transparent"
                    }
                    // Ruled lines like an index card
                    Repeater {
                        model: Math.max(0, Math.floor((card.height - 40) / 20))
                        Rectangle { x: 8; width: card.width - 16; height: 1; y: 40 + index * 20; color: Theme.cardLine; required property int index }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.topMargin: 10
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            KindIcon { kind: cell.modelData.kind; size: 14 }
                            TextField {
                                id: titleEdit
                                Layout.fillWidth: true
                                text: cell.modelData.title
                                font.bold: true
                                color: Theme.ink
                                background: null
                                padding: 0
                                selectByMouse: true
                                onEditingFinished: if (text !== cell.modelData.title && text.trim().length) Api.call("setField", cell.modelData.id, "title", text)
                            }
                        }
                        TextArea {
                            id: synopsis
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: cell.modelData.synopsis
                            placeholderText: qsTr("Synopsis…")
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.editorFont
                            font.pixelSize: 13
                            color: Theme.ink
                            background: null
                            padding: 0
                            selectByMouse: true
                            onActiveFocusChanged: if (!activeFocus && text !== cell.modelData.synopsis) Api.call("setField", cell.modelData.id, "synopsis", text)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: cell.modelData.status_name || ""; color: Theme.accent; font.pixelSize: 10; font.bold: true; font.capitalization: Font.AllUppercase }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: Api.fmtNumber(cell.modelData.total_words) + (cell.modelData.target_words ? "/" + Api.fmtNumber(cell.modelData.target_words) : "") + qsTr(" w")
                                color: Theme.subtext; font.pixelSize: 10
                            }
                            Label { visible: cell.modelData.child_count > 0; text: "▤ " + cell.modelData.child_count; color: Theme.subtext; font.pixelSize: 10 }
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: { cb.keyId = cell.modelData.id; cb.selectRequested(cell.modelData.id); grid.forceActiveFocus(); }
                        onDoubleTapped: cb.openRequested(cell.modelData.id)
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: cardMenu.popup() }
                    // Drag from anywhere that isn't text (the edges, the
                    // ruled area, the footer, the icon); the title and
                    // synopsis keep the mouse for selecting text.
                    DragHandler {
                        id: dragger
                        target: null
                        acceptedButtons: Qt.LeftButton
                        cursorShape: active ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        onActiveChanged: {
                            if (active) cb.startDrag(cell.modelData.id, cell.modelData.title);
                            else cb.finishDrag();
                        }
                        onCentroidChanged: if (active) cb.updateDrag(centroid.scenePosition)
                    }
                    // The keyboard highlight.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        visible: grid.activeFocus && cb.keyId === cell.modelData.id
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        radius: 5
                    }
                    // "Drop inside this folder" highlight.
                    Rectangle {
                        anchors.fill: parent
                        visible: cb.dropMode === "inside" && cb.dropIndex === cell.index
                        color: "transparent"
                        border.width: 3
                        border.color: Theme.accent
                        radius: 3
                    }
                    Menu {
                        id: cardMenu
                        MenuItem { text: qsTr("Open in Editor"); onTriggered: cb.openRequested(cell.modelData.id) }
                        MenuItem { text: qsTr("Move Earlier"); onTriggered: Api.call("shift", cell.modelData.id, -1) }
                        MenuItem { text: qsTr("Move Later"); onTriggered: Api.call("shift", cell.modelData.id, 1) }
                        MenuItem { text: qsTr("Duplicate"); onTriggered: Api.call("duplicate", cell.modelData.id) }
                        MenuItem { text: cell.modelData.include_in_compile ? qsTr("Exclude from Compile") : qsTr("Include in Compile"); onTriggered: Api.call("setField", cell.modelData.id, "include_in_compile", !cell.modelData.include_in_compile) }
                        MenuSeparator {}
                        MenuItem { text: qsTr("Move to Trash"); onTriggered: Api.call("trash", cell.modelData.id) }
                    }
                }
            }
        }
    }

    // Where the dragged card will land: a bar between cards.
    Rectangle {
        readonly property var item: cb.dropIndex >= 0 && (cb.dropMode === "before" || cb.dropMode === "after") ? grid.itemAtIndex(cb.dropIndex) : null
        visible: item !== null
        width: 4
        radius: 2
        color: Theme.accent
        // mapToItem isn't a live binding: read contentY so scrolling moves it.
        x: { grid.contentY; return item ? grid.contentItem.mapToItem(cb, item.x + (cb.dropMode === "after" ? item.width : 0), 0).x - 2 : 0; }
        y: { grid.contentY; return item ? grid.contentItem.mapToItem(cb, 0, item.y).y + 8 : 0; }
        height: item ? item.height - 16 : 0
        z: 5
    }
    // The card under the pointer while dragging.
    Rectangle {
        visible: cb.dragId !== ""
        // Beside the pointer, kept inside the board.
        x: Math.max(4, Math.min(cb.width - width - 4, cb.dragPos.x + 14))
        y: Math.max(4, Math.min(cb.height - height - 4, cb.dragPos.y + 10))
        width: Math.min(cb.cardWidth, 220)
        height: 28
        radius: 3
        color: Theme.card
        border.color: Theme.accent
        opacity: 0.9
        z: 6
        Label { anchors.fill: parent; anchors.margins: 6; text: cb.dragTitle; elide: Text.ElideRight; font.bold: true; color: Theme.ink; verticalAlignment: Text.AlignVCenter }
    }

    Label {
        anchors.centerIn: parent
        visible: cb.cards.length === 0
        text: cb.containerId ? qsTr("No cards here yet — add one with + Card.") : qsTr("Select a folder to see its cards.")
        color: Theme.dark ? Theme.subtext : "#3b2b17"
    }
}
