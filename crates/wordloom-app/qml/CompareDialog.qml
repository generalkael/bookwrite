import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Side-by-side comparison of two versions of a document: any snapshot
// against the current text or another snapshot. Paragraphs line up, and
// changed words are highlighted (red on the left, green on the right).
Dialog {
    id: dlg
    title: qsTr("Compare Versions")
    modal: true
    width: Math.min(1100, parent ? parent.width - 60 : 1100)
    height: Math.min(760, parent ? parent.height - 60 : 760)
    standardButtons: Dialog.Close

    property string nodeId: ""
    property var snaps: []
    property var cmp: null
    // Left: a snapshot. Right: "Current text" (index 0) or a snapshot.
    property int leftIndex: 0
    property int rightIndex: 0

    readonly property color removedBg: Theme.dark ? "#5c2b2b" : "#f6cfc9"
    readonly property color addedBg: Theme.dark ? "#25502f" : "#c9eacf"
    readonly property color removedRow: Theme.dark ? "#2f2424" : "#fbefed"
    readonly property color addedRow: Theme.dark ? "#223026" : "#edf8ef"

    // Open comparing snapshot `snapId` with the current text.
    function openFor(id, snapId) {
        nodeId = id;
        snaps = Api.get("snapshots", [], id);
        leftIndex = Math.max(0, snaps.findIndex(s => s.id === snapId));
        rightIndex = 0;
        refresh();
        open();
    }
    function refresh() {
        if (!nodeId || !snaps.length) { cmp = null; return; }
        const left = snaps[leftIndex].id;
        const right = rightIndex === 0 ? "" : snaps[rightIndex - 1].id;
        cmp = Api.get("compareSnapshots", null, nodeId, left, right);
    }
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function html(segs, bg) {
        return segs.map(s => s.mark ? "<span style=\"background-color:" + bg + "\">" + esc(s.text) + "</span>" : esc(s.text)).join("");
    }
    readonly property var visibleRows: cmp ? cmp.rows.filter(r => !onlyChanges.checked || r.kind !== "same") : []

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ComboBox {
                Layout.fillWidth: true
                model: dlg.snaps.map(s => s.title + "  ·  " + new Date(s.created).toLocaleString(Qt.locale(), Locale.ShortFormat))
                currentIndex: dlg.leftIndex
                onActivated: (i) => { dlg.leftIndex = i; dlg.refresh(); }
            }
            Label { text: "→"; color: Theme.subtext; font.pixelSize: 18 }
            ComboBox {
                Layout.fillWidth: true
                model: [qsTr("Current text")].concat(dlg.snaps.map(s => s.title + "  ·  " + new Date(s.created).toLocaleString(Qt.locale(), Locale.ShortFormat)))
                currentIndex: dlg.rightIndex
                onActivated: (i) => { dlg.rightIndex = i; dlg.refresh(); }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            CheckBox { id: onlyChanges; text: qsTr("Only changed paragraphs") }
            Item { Layout.fillWidth: true }
            Label {
                color: Theme.subtext
                text: !dlg.cmp ? ""
                    : dlg.cmp.words_added + dlg.cmp.words_removed === 0 ? qsTr("No differences")
                    : qsTr("%1 words added · %2 removed").arg(dlg.cmp.words_added).arg(dlg.cmp.words_removed)
            }
        }

        // Column headings
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Label { Layout.fillWidth: true; Layout.preferredWidth: 1; text: dlg.cmp ? dlg.cmp.left_title : ""; font.bold: true; color: Theme.text; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; Layout.preferredWidth: 1; text: dlg.cmp ? dlg.cmp.right_title : ""; font.bold: true; color: Theme.text; elide: Text.ElideRight }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: dlg.visibleRows
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                width: list.width - 12
                height: Math.max(l.implicitHeight, r.implicitHeight) + 12
                color: Theme.paper
                border.color: modelData.kind === "same" ? "transparent" : Theme.border
                radius: 3
                Rectangle {
                    x: 0; width: parent.width / 2 - 6; height: parent.height; radius: 3
                    color: row.modelData.kind === "removed" ? dlg.removedRow : "transparent"
                }
                Rectangle {
                    x: parent.width / 2 + 6; width: parent.width / 2 - 6; height: parent.height; radius: 3
                    color: row.modelData.kind === "added" ? dlg.addedRow : "transparent"
                }
                Text {
                    id: l
                    x: 8; y: 6
                    width: parent.width / 2 - 22
                    text: dlg.html(row.modelData.left, dlg.removedBg)
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    color: row.modelData.kind === "same" ? Theme.subtext : Theme.ink
                    font.family: Theme.editorFont
                    font.pixelSize: 14
                }
                Text {
                    id: r
                    x: parent.width / 2 + 14; y: 6
                    width: parent.width / 2 - 22
                    text: dlg.html(row.modelData.right, dlg.addedBg)
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    color: row.modelData.kind === "same" ? Theme.subtext : Theme.ink
                    font.family: Theme.editorFont
                    font.pixelSize: 14
                }
            }
        }
        Label {
            visible: dlg.snaps.length === 0
            text: qsTr("This document has no snapshots yet.")
            color: Theme.subtext
        }
    }
}
