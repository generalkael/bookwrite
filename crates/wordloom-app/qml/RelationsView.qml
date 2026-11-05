import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import com.wordloom.app

// Relationship map: characters as cards you can drag around, relationships
// as labelled arrows read from one card to the other ("Mara distrusts
// Tobias"). Double-click a card to open its sheet; click a label to edit it.
Rectangle {
    id: rv
    color: Theme.window

    property bool active: false
    property string selectedNode: ""
    property var map: ({ people: [], links: [] })
    signal openRequested(string id)
    signal selectRequested(string id)

    readonly property int cardW: 168
    readonly property int cardH: 52
    readonly property int rev: Wordloom.revision
    onRevChanged: if (active) reload()
    onActiveChanged: if (active) reload()
    function reload() { map = Api.get("relations", { people: [], links: [] }); }

    // Saved positions, with unplaced people spread on a circle.
    readonly property var positions: {
        const out = {};
        const loose = map.people.filter(p => p.x === null || p.y === null);
        const n = loose.length;
        const r = Math.max(160, n * 34);
        loose.forEach((p, i) => {
            const a = -Math.PI / 2 + i * 2 * Math.PI / Math.max(1, n);
            out[p.id] = { x: r + 60 + r * Math.cos(a), y: r + 40 + r * Math.sin(a) };
        });
        for (const p of map.people) if (p.x !== null && p.y !== null) out[p.id] = { x: p.x, y: p.y };
        return out;
    }
    readonly property var nameOf: {
        const o = {};
        for (const p of map.people) o[p.id] = p.title;
        return o;
    }
    // Live card positions while dragging (id -> {x, y}).
    property var dragging: ({})
    function posOf(id) { return dragging[id] || positions[id] || { x: 0, y: 0 }; }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ToolBar {
            Layout.fillWidth: true
            background: Rectangle { color: Theme.panel; Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border } }
            RowLayout {
                anchors.fill: parent
                spacing: 4
                ToolButton {
                    text: qsTr("+ Relationship")
                    enabled: rv.map.people.length >= 2
                    onClicked: relDialog.openNew(rv.map.people.some(p => p.id === rv.selectedNode) ? rv.selectedNode : rv.map.people[0].id)
                }
                Label {
                    Layout.leftMargin: 8
                    color: Theme.subtext
                    text: qsTr("Drag cards to arrange · double-click a card to open it · click a label to edit")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    color: Theme.subtext
                    text: qsTr("%1 people · %2 relationships").arg(rv.map.people.length).arg(rv.map.links.length)
                    Layout.rightMargin: 8
                }
            }
        }

        Flickable {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: Math.max(width, extent.x + rv.cardW + 80)
            contentHeight: Math.max(height, extent.y + rv.cardH + 80)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}
            readonly property point extent: {
                let x = 0, y = 0;
                for (const id in rv.positions) { x = Math.max(x, rv.positions[id].x); y = Math.max(y, rv.positions[id].y); }
                return Qt.point(x, y);
            }

            // Links (under the cards)
            Repeater {
                model: rv.map.links
                delegate: Item {
                    id: link
                    required property var modelData
                    readonly property var a: rv.posOf(modelData.from)
                    readonly property var b: rv.posOf(modelData.to)
                    readonly property real ax: a.x + rv.cardW / 2
                    readonly property real ay: a.y + rv.cardH / 2
                    readonly property real bx: b.x + rv.cardW / 2
                    readonly property real by: b.y + rv.cardH / 2
                    // Where the line meets the target card's edge, for the arrowhead.
                    readonly property real dx: bx - ax
                    readonly property real dy: by - ay
                    readonly property real t: {
                        const tx = Math.abs(dx) > 0.01 ? (rv.cardW / 2 + 4) / Math.abs(dx) : 1e9;
                        const ty = Math.abs(dy) > 0.01 ? (rv.cardH / 2 + 4) / Math.abs(dy) : 1e9;
                        return Math.min(1, Math.min(tx, ty));
                    }
                    readonly property real ex: bx - dx * t
                    readonly property real ey: by - dy * t
                    readonly property real ang: Math.atan2(dy, dx)
                    readonly property bool selected: rv.selectedNode !== "" && (modelData.from === rv.selectedNode || modelData.to === rv.selectedNode)

                    Shape {
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: link.selected ? Theme.accent : Theme.subtext
                            strokeWidth: link.selected ? 2.5 : 1.6
                            fillColor: "transparent"
                            startX: link.ax; startY: link.ay
                            PathLine { x: link.ex; y: link.ey }
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: link.selected ? Theme.accent : Theme.subtext
                            startX: link.ex; startY: link.ey
                            PathLine { x: link.ex - 11 * Math.cos(link.ang - 0.4); y: link.ey - 11 * Math.sin(link.ang - 0.4) }
                            PathLine { x: link.ex - 11 * Math.cos(link.ang + 0.4); y: link.ey - 11 * Math.sin(link.ang + 0.4) }
                            PathLine { x: link.ex; y: link.ey }
                        }
                    }
                    // Label at the midpoint
                    Rectangle {
                        z: 1
                        x: (link.ax + link.bx) / 2 - width / 2
                        y: (link.ay + link.by) / 2 - height / 2
                        width: lbl.implicitWidth + 14
                        height: lbl.implicitHeight + 6
                        radius: height / 2
                        color: Theme.base
                        border.color: link.selected ? Theme.accent : Theme.border
                        Label {
                            id: lbl
                            anchors.centerIn: parent
                            text: link.modelData.label || qsTr("(unlabelled)")
                            color: link.modelData.label ? Theme.text : Theme.subtext
                            font.pixelSize: 12
                            font.italic: !link.modelData.label
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: relDialog.openEdit(link.modelData) }
                        ToolTip.visible: !!link.modelData.notes && labelHover.hovered
                        ToolTip.text: link.modelData.notes
                        HoverHandler { id: labelHover }
                    }
                }
            }

            // People
            Repeater {
                model: rv.map.people
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool selected: rv.selectedNode === modelData.id
                    x: rv.posOf(modelData.id).x
                    y: rv.posOf(modelData.id).y
                    z: 2
                    width: rv.cardW
                    height: rv.cardH
                    radius: 6
                    color: Theme.card
                    border.color: selected ? Theme.accent : Theme.border
                    border.width: selected ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        KindIcon { kind: card.modelData.kind; size: 22 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: card.modelData.title; font.bold: true; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { visible: text !== ""; text: card.modelData.synopsis; color: Theme.subtext; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }

                    DragHandler {
                        id: drag
                        target: null
                        property point origin
                        onActiveChanged: {
                            if (active) {
                                origin = Qt.point(card.x, card.y);
                            } else {
                                const p = rv.dragging[card.modelData.id];
                                const d = Object.assign({}, rv.dragging); delete d[card.modelData.id]; rv.dragging = d;
                                if (p) Api.call("placeOnMap", card.modelData.id, Math.max(0, p.x), Math.max(0, p.y));
                            }
                        }
                        onTranslationChanged: {
                            if (!active) return;
                            const d = Object.assign({}, rv.dragging);
                            d[card.modelData.id] = { x: Math.max(0, origin.x + translation.x), y: Math.max(0, origin.y + translation.y) };
                            rv.dragging = d;
                        }
                    }
                    TapHandler { onTapped: rv.selectRequested(card.modelData.id); onDoubleTapped: rv.openRequested(card.modelData.id) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: { rv.selectRequested(card.modelData.id); cardMenu.popup(); } }
                    Menu {
                        id: cardMenu
                        MenuItem { text: qsTr("Add Relationship…"); onTriggered: relDialog.openNew(card.modelData.id) }
                        MenuItem { text: qsTr("Open"); onTriggered: rv.openRequested(card.modelData.id) }
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: rv.map.people.length === 0
        spacing: 8
        Label { Layout.alignment: Qt.AlignHCenter; text: qsTr("No characters yet"); font.bold: true; color: Theme.text }
        Label { Layout.alignment: Qt.AlignHCenter; text: qsTr("Add characters in the binder's Characters section, then connect them here."); color: Theme.subtext }
    }

    readonly property alias dialogRef: relDialog

    // Add / edit a relationship.
    Dialog {
        id: relDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 440
        property string relId: ""
        title: relId ? qsTr("Edit Relationship") : qsTr("New Relationship")
        readonly property var people: rv.map.people
        readonly property var suggestions: [qsTr("friends with"), qsTr("in love with"), qsTr("rivals of"), qsTr("parent of"), qsTr("sibling of"), qsTr("mentor to"), qsTr("enemy of"), qsTr("works for")]

        function openNew(fromId) {
            relId = "";
            const i = Math.max(0, people.findIndex(p => p.id === fromId));
            fromBox.currentIndex = i;
            toBox.currentIndex = people.length > 1 ? (i === 0 ? 1 : 0) : 0;
            labelField.text = "";
            notesField.text = "";
            open();
            labelField.forceActiveFocus();
        }
        function openEdit(l) {
            relId = l.id;
            fromBox.currentIndex = people.findIndex(p => p.id === l.from);
            toBox.currentIndex = people.findIndex(p => p.id === l.to);
            labelField.text = l.label;
            notesField.text = l.notes;
            open();
        }
        function save() {
            const from = people[fromBox.currentIndex], to = people[toBox.currentIndex];
            if (!from || !to || from.id === to.id) { Api.say(qsTr("Pick two different people")); return; }
            if (relId) {
                const old = rv.map.links.find(l => l.id === relId);
                let id = relId;
                if (old && old.from === to.id && old.to === from.id) {
                    Api.call("reverseRelation", relId);
                } else if (old && (old.from !== from.id || old.to !== to.id)) {
                    // Different people: replace the link.
                    Api.call("removeRelation", relId);
                    id = Api.call("addRelation", from.id, to.id, labelField.text);
                }
                if (id) Api.call("updateRelation", id, labelField.text, notesField.text);
            } else {
                const id = Api.call("addRelation", from.id, to.id, labelField.text);
                if (id && notesField.text) Api.call("updateRelation", id, labelField.text, notesField.text);
            }
            close();
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                ComboBox { id: fromBox; Layout.fillWidth: true; model: relDialog.people.map(p => p.title) }
                ToolButton { text: "⇄"; onClicked: { const i = fromBox.currentIndex; fromBox.currentIndex = toBox.currentIndex; toBox.currentIndex = i; } ToolTip.visible: hovered; ToolTip.text: qsTr("Swap") }
                ComboBox { id: toBox; Layout.fillWidth: true; model: relDialog.people.map(p => p.title) }
            }
            TextField {
                id: labelField
                Layout.fillWidth: true
                placeholderText: qsTr("Relationship, read left to right (e.g. “mentor to”)")
                onAccepted: relDialog.save()
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: relDialog.suggestions
                    delegate: Button {
                        required property string modelData
                        text: modelData
                        flat: true
                        font.pixelSize: 11
                        onClicked: labelField.text = modelData
                    }
                }
            }
            Label { text: qsTr("Notes"); color: Theme.subtext }
            TextArea { id: notesField; Layout.fillWidth: true; Layout.preferredHeight: 70; wrapMode: TextEdit.Wrap; placeholderText: qsTr("History, tension, what each wants from the other…") }
            RowLayout {
                Layout.fillWidth: true
                Button { visible: relDialog.relId !== ""; text: qsTr("Delete"); onClicked: { Api.call("removeRelation", relDialog.relId); relDialog.close(); } }
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: relDialog.close() }
                Button { text: relDialog.relId ? qsTr("Save") : qsTr("Add"); highlighted: true; onClicked: relDialog.save() }
            }
        }
    }
}
