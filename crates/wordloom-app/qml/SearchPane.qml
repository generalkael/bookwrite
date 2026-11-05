import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Project-wide search results with replace-all.
ColumnLayout {
    id: sp
    property string query: ""
    property var hits: []
    signal chosen(string id)
    spacing: 4

    readonly property int rev: Wordloom.revision
    onRevChanged: run()
    onQueryChanged: debounce.restart()
    Timer { id: debounce; interval: 200; onTriggered: sp.run() }
    function run() { hits = query.trim().length ? Api.get("search", [], query) : []; }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        TextField { id: replaceField; Layout.fillWidth: true; placeholderText: qsTr("Replace with…") }
        Button {
            text: qsTr("Replace All")
            enabled: sp.query.trim().length > 0
            onClicked: {
                const r = Api.call("replaceAll", sp.query, replaceField.text);
                if (r) Api.say(qsTr("Replaced %1 occurrence(s) in %2 document(s)").arg(r.replacements).arg(r.documents));
            }
        }
    }
    Label {
        Layout.leftMargin: 8
        color: Theme.subtext
        text: sp.hits.length ? qsTr("%1 match(es)").arg(sp.hits.length) : qsTr("No matches")
    }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: sp.hits
        ScrollBar.vertical: ScrollBar {}
        delegate: ItemDelegate {
            required property var modelData
            width: ListView.view.width
            onClicked: sp.chosen(modelData.id)
            contentItem: ColumnLayout {
                spacing: 1
                RowLayout {
                    Label { text: modelData.title; font.bold: true; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { text: modelData.field + (modelData.count > 1 ? " ×" + modelData.count : ""); color: Theme.accent; font.pixelSize: 11 }
                }
                Label { text: modelData.snippet; color: Theme.subtext; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true; font.pixelSize: 12 }
            }
        }
    }
}
