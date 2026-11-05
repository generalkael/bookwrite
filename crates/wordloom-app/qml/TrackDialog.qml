import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Create or edit a timeline track.
Dialog {
    id: dlg
    property var tl: null
    property var track: null
    property bool isNew: true
    readonly property var kinds: ["character", "plotline", "place", "theme", "custom"]

    title: isNew ? qsTr("New Track") : qsTr("Edit Track")
    modal: true
    width: 440
    standardButtons: Dialog.Save | Dialog.Cancel

    function openNew() {
        isNew = true;
        track = null;
        nameField.text = "";
        kindBox.currentIndex = 0;
        colorField.text = "";
        notesField.text = "";
        open();
        nameField.forceActiveFocus();
    }
    function openEdit(t) {
        isNew = false;
        track = JSON.parse(JSON.stringify(t));
        nameField.text = t.name;
        kindBox.currentIndex = Math.max(0, kinds.indexOf(t.kind));
        colorField.text = t.color;
        notesField.text = t.notes || "";
        open();
    }

    onAccepted: {
        let t = track;
        if (isNew) {
            const id = Api.call("addTrack", nameField.text, kinds[kindBox.currentIndex]);
            if (!id) return;
            const tl2 = Api.call("timeline");
            t = tl2.tracks.find(x => x.id === id);
        }
        t.name = nameField.text.trim() || t.name;
        t.kind = kinds[kindBox.currentIndex];
        if (colorField.text.trim()) t.color = colorField.text.trim();
        t.notes = notesField.text;
        Api.call("updateTrack", t);
    }

    GridLayout {
        anchors.fill: parent
        columns: 2
        Label { text: qsTr("Name") }
        TextField { id: nameField; Layout.fillWidth: true; placeholderText: qsTr("e.g. Elena, The Heist, Old Town") }
        Label { text: qsTr("Kind") }
        ComboBox { id: kindBox; Layout.fillWidth: true; model: [qsTr("Character"), qsTr("Plotline"), qsTr("Place"), qsTr("Theme"), qsTr("Custom")] }
        Label { text: qsTr("Colour") }
        RowLayout {
            TextField { id: colorField; Layout.preferredWidth: 100; placeholderText: qsTr("auto") }
            Repeater {
                model: ["#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f", "#edc948", "#b07aa1", "#ff9da7", "#9c755f"]
                delegate: Rectangle {
                    required property string modelData
                    width: 20; height: 20; radius: 10; color: modelData
                    border.width: colorField.text === modelData ? 2 : 0
                    border.color: Theme.text
                    TapHandler { onTapped: colorField.text = modelData }
                }
            }
        }
        Label { text: qsTr("Notes") }
        TextField { id: notesField; Layout.fillWidth: true }
        Item { visible: !dlg.isNew }
        Button {
            visible: !dlg.isNew
            text: qsTr("Delete Track and Its Events")
            palette.buttonText: Theme.danger
            onClicked: { Api.call("removeTrack", dlg.track.id); dlg.close(); }
        }
    }
}
