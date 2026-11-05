import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Tabular outline of everything under the selected item, with synopsis,
// label, status, word counts and progress towards per-document targets.
Rectangle {
    id: ov
    color: Theme.base

    property string nodeId: ""
    property var node: null
    property bool active: false
    property var rows: []
    property var meta: ({ labels: [], statuses: [] })
    signal openRequested(string id)

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
        rows = out;
    }

    readonly property var widths: [230, 0, 120, 120, 64, 64, 80]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: Theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Label { text: qsTr("Title"); font.bold: true; Layout.preferredWidth: ov.widths[0]; Layout.minimumWidth: ov.widths[0]; color: Theme.subtext }
                Label { text: qsTr("Synopsis"); font.bold: true; Layout.fillWidth: true; Layout.minimumWidth: 80; color: Theme.subtext }
                Label { text: qsTr("Label"); font.bold: true; Layout.preferredWidth: ov.widths[2]; color: Theme.subtext }
                Label { text: qsTr("Status"); font.bold: true; Layout.preferredWidth: ov.widths[3]; color: Theme.subtext }
                Label { text: qsTr("Words"); font.bold: true; Layout.preferredWidth: ov.widths[4]; horizontalAlignment: Text.AlignRight; color: Theme.subtext }
                Label { text: qsTr("Target"); font.bold: true; Layout.preferredWidth: ov.widths[5]; horizontalAlignment: Text.AlignRight; color: Theme.subtext }
                Label { text: qsTr("Progress"); font.bold: true; Layout.preferredWidth: ov.widths[6]; color: Theme.subtext }
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ov.rows
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: r
                required property var modelData
                required property int index
                width: ListView.view.width
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
                        Item { Layout.preferredWidth: r.modelData.depth * 14 }
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
        visible: ov.rows.length === 0
        text: qsTr("Nothing below this item yet.")
        color: Theme.subtext
    }
}
