import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Go to… (Ctrl+P): type part of any item's title, Enter opens it. Matching
// and ranking are in wordloom-core's goto.rs. With nothing typed it lists
// what you changed most recently.
Popup {
    id: gp
    modal: true
    focus: true
    width: Math.min(560, parent ? parent.width - 40 : 560)
    height: Math.min(col.implicitHeight + 2 * padding, parent ? parent.height - 120 : 480)
    x: parent ? (parent.width - width) / 2 : 0
    y: 70
    padding: 8
    property var hits: []
    signal chosen(string id)

    function start() {
        field.text = "";
        refresh();
        open();
        field.forceActiveFocus();
    }
    // For the screenshot tour.
    function search(q) { field.text = q; refresh(); }
    function refresh() {
        hits = Api.get("goTo", [], field.text);
        list.currentIndex = hits.length ? 0 : -1;
    }
    function choose(i) {
        if (i < 0 || i >= hits.length) return;
        const id = hits[i].id;
        close();
        chosen(id);
    }

    background: Rectangle { color: Theme.panel; border.color: Theme.border; radius: 6 }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 6
        TextField {
            id: field
            Layout.fillWidth: true
            placeholderText: qsTr("Go to a document, folder, character…")
            selectByMouse: true
            onTextEdited: gp.refresh()
            Keys.onDownPressed: list.currentIndex = Math.min(gp.hits.length - 1, list.currentIndex + 1)
            Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
            Keys.onReturnPressed: gp.choose(list.currentIndex)
            Keys.onEnterPressed: gp.choose(list.currentIndex)
            Keys.onEscapePressed: gp.close()
        }
        Label {
            visible: field.text.trim() === ""
            text: qsTr("Recently changed")
            color: Theme.subtext
            font.pixelSize: 11
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 12 * 44)
            clip: true
            model: gp.hits
            highlightMoveDuration: 0
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 44
                highlighted: ListView.isCurrentItem
                onClicked: gp.choose(index)
                contentItem: RowLayout {
                    spacing: 8
                    KindIcon { kind: modelData.kind; role: modelData.role || "" }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Label { text: modelData.title || qsTr("Untitled"); textFormat: Text.PlainText; color: row.highlighted ? row.palette.highlightedText : modelData.in_trash ? Theme.subtext : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: modelData.path; textFormat: Text.PlainText; color: row.highlighted ? row.palette.highlightedText : Theme.subtext; opacity: row.highlighted ? 0.85 : 1; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                }
            }
        }
        Label {
            visible: gp.hits.length === 0
            text: qsTr("Nothing is called that.")
            color: Theme.subtext
            Layout.margins: 8
        }
    }
}
