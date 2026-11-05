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
                    opacity: cell.modelData.include_in_compile ? 1 : 0.7

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
                        onTapped: cb.selectRequested(cell.modelData.id)
                        onDoubleTapped: cb.openRequested(cell.modelData.id)
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: cardMenu.popup() }
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

    Label {
        anchors.centerIn: parent
        visible: cb.cards.length === 0
        text: cb.containerId ? qsTr("No cards here yet — add one with + Card.") : qsTr("Select a folder to see its cards.")
        color: Theme.dark ? Theme.subtext : "#3b2b17"
    }
}
