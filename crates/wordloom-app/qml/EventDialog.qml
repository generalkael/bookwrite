import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Create or edit a timeline event: when, which track, who takes part, which
// scenes dramatise it, and what must happen first.
Dialog {
    id: dlg
    property var tl: null
    property var ev: null         // working copy
    property bool isNew: false
    signal openScene(string id)

    title: isNew ? qsTr("New Event") : qsTr("Edit Event")
    modal: true
    width: 620
    height: Math.min(720, parent ? parent.height - 40 : 720)
    standardButtons: Dialog.Save | Dialog.Cancel

    function openNew(trackId, start) {
        isNew = true;
        ev = { id: "", title: "", track: trackId, start: start, duration: 1, participants: [], linked_nodes: [], depends_on: [], color: null, notes: "" };
        load();
        open();
    }
    function openEdit(e) {
        isNew = false;
        ev = JSON.parse(JSON.stringify(e));
        load();
        open();
    }
    function load() {
        titleField.text = ev.title;
        trackBox.currentIndex = Math.max(0, tl.tracks.findIndex(t => t.id === ev.track));
        startBox.value = ev.start;
        durBox.value = ev.duration;
        colorField.text = ev.color || "";
        notesArea.text = ev.notes;
        partRep.model = tl.tracks.slice();
        sceneRep.model = tl.scenes.slice();
        depRep.model = tl.events.filter(x => x.id !== ev.id);
        titleField.forceActiveFocus();
    }
    function toggle(list, id, on) {
        const i = list.indexOf(id);
        if (on && i < 0) list.push(id);
        if (!on && i >= 0) list.splice(i, 1);
    }

    onAccepted: {
        ev.title = titleField.text.trim() || qsTr("Untitled event");
        ev.track = tl.tracks[trackBox.currentIndex].id;
        ev.start = startBox.value;
        ev.duration = durBox.value;
        ev.color = colorField.text.trim() ? colorField.text.trim() : null;
        ev.notes = notesArea.text;
        if (isNew) {
            const id = Api.call("addEvent", ev.title, ev.track, ev.start, ev.duration);
            if (!id) return;
            ev.id = id;
        }
        Api.call("updateEvent", ev);
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: dlg.availableWidth - 16
            spacing: 8

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 10
                Label { text: qsTr("Title") }
                TextField { id: titleField; Layout.fillWidth: true; Layout.columnSpan: 3 }
                Label { text: qsTr("Track") }
                ComboBox { id: trackBox; Layout.fillWidth: true; Layout.columnSpan: 3; model: dlg.tl ? dlg.tl.tracks.map(t => t.name) : [] }
                Label { text: qsTr("Start") }
                SpinBox { id: startBox; from: -10000000; to: 10000000; editable: true; Layout.fillWidth: true }
                Label { text: qsTr("Length") }
                SpinBox { id: durBox; from: 0; to: 10000000; editable: true; Layout.fillWidth: true }
                Item {}
                Label {
                    Layout.columnSpan: 3
                    color: Theme.subtext
                    font.pixelSize: 11
                    text: dlg.tl ? Api.unitLabel(dlg.tl, startBox.value) + (durBox.value > 0 ? "  →  " + Api.unitLabel(dlg.tl, startBox.value + durBox.value) : qsTr("  (length 0 = milestone)")) : ""
                }
                Label { text: qsTr("Colour") }
                RowLayout {
                    Layout.columnSpan: 3
                    TextField { id: colorField; placeholderText: qsTr("track colour"); Layout.preferredWidth: 110 }
                    Repeater {
                        model: ["#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f", "#edc948", "#b07aa1", "#9c755f"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 20; height: 20; radius: 10; color: modelData
                            border.width: colorField.text === modelData ? 2 : 0
                            border.color: Theme.text
                            TapHandler { onTapped: colorField.text = modelData }
                        }
                    }
                    ToolButton { text: "✕"; onClicked: colorField.text = "" }
                }
            }

            Label { text: qsTr("Also involves"); font.bold: true; color: Theme.text }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    id: partRep
                    delegate: CheckBox {
                        required property var modelData
                        visible: dlg.tl && trackBox.currentIndex >= 0 && dlg.tl.tracks[trackBox.currentIndex] && modelData.id !== dlg.tl.tracks[trackBox.currentIndex].id
                        text: modelData.name
                        checked: dlg.ev && dlg.ev.participants.indexOf(modelData.id) >= 0
                        onToggled: dlg.toggle(dlg.ev.participants, modelData.id, checked)
                    }
                }
            }

            Label { text: qsTr("Scenes"); font.bold: true; color: Theme.text }
            Label { visible: dlg.tl && dlg.tl.scenes.length === 0; text: qsTr("No manuscript scenes yet."); color: Theme.subtext }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    id: sceneRep
                    delegate: CheckBox {
                        required property var modelData
                        text: modelData.title
                        checked: dlg.ev && dlg.ev.linked_nodes.indexOf(modelData.id) >= 0
                        onToggled: dlg.toggle(dlg.ev.linked_nodes, modelData.id, checked)
                    }
                }
            }

            Label { text: qsTr("Happens after"); font.bold: true; color: Theme.text }
            Label { visible: depRep.count === 0; text: qsTr("No other events yet."); color: Theme.subtext }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    id: depRep
                    delegate: CheckBox {
                        required property var modelData
                        text: modelData.title
                        checked: dlg.ev && dlg.ev.depends_on.indexOf(modelData.id) >= 0
                        onToggled: dlg.toggle(dlg.ev.depends_on, modelData.id, checked)
                    }
                }
            }

            Label { text: qsTr("Notes"); font.bold: true; color: Theme.text }
            TextArea {
                id: notesArea
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                wrapMode: TextEdit.Wrap
                placeholderText: qsTr("What happens, and why it matters")
            }

            RowLayout {
                visible: !dlg.isNew
                Button {
                    text: dlg.ev && dlg.ev.linked_nodes.length ? qsTr("Open Scene") : qsTr("Write This Scene")
                    onClicked: { const id = Api.call("sceneForEvent", dlg.ev.id); dlg.close(); if (id) dlg.openScene(id); }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Delete Event")
                    palette.buttonText: Theme.danger
                    onClicked: { Api.call("removeEvent", dlg.ev.id); dlg.close(); }
                }
            }
        }
    }
}
