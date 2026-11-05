import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Project title/author and the label & status vocabularies.
Dialog {
    id: dlg
    title: qsTr("Project Settings")
    modal: true
    width: 560
    height: Math.min(640, parent ? parent.height - 60 : 640)
    standardButtons: Dialog.Close
    property var lists: ({ labels: [], statuses: [] })

    readonly property int rev: Wordloom.revision
    onRevChanged: if (visible) lists = Api.get("labels", lists)
    onAboutToShow: {
        const m = Api.get("meta", null);
        if (m) { titleField.text = m.title; authorField.text = m.author; pathLabel.text = m.path; }
        lists = Api.get("labels", lists);
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        ColumnLayout {
            width: dlg.availableWidth - 12
            spacing: 8
            GridLayout {
                columns: 2
                Layout.fillWidth: true
                Label { text: qsTr("Title") }
                TextField { id: titleField; Layout.fillWidth: true; onEditingFinished: Api.call("setMeta", titleField.text, authorField.text) }
                Label { text: qsTr("Author") }
                TextField { id: authorField; Layout.fillWidth: true; onEditingFinished: Api.call("setMeta", titleField.text, authorField.text) }
                Label { text: qsTr("Location") }
                Label { id: pathLabel; Layout.fillWidth: true; elide: Text.ElideMiddle; color: Theme.subtext }
            }

            Label { text: qsTr("Labels"); font.bold: true; Layout.topMargin: 10 }
            Repeater {
                model: dlg.lists.labels
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Rectangle { width: 18; height: 18; radius: 9; color: colorF.text }
                    TextField { Layout.fillWidth: true; text: modelData.name; onEditingFinished: Api.call("upsertLabel", modelData.id, text, colorF.text) }
                    TextField { id: colorF; Layout.preferredWidth: 90; text: modelData.color; onEditingFinished: Api.call("upsertLabel", modelData.id, modelData.name, text) }
                    ToolButton { text: "✕"; onClicked: Api.call("removeLabel", modelData.id) }
                }
            }
            Button { text: qsTr("+ Label"); onClicked: Api.call("upsertLabel", "", qsTr("New Label"), "#888888") }

            Label { text: qsTr("Statuses"); font.bold: true; Layout.topMargin: 10 }
            Repeater {
                model: dlg.lists.statuses
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    TextField { Layout.fillWidth: true; text: modelData.name; onEditingFinished: Api.call("upsertStatus", modelData.id, text) }
                    ToolButton { text: "✕"; onClicked: Api.call("removeStatus", modelData.id) }
                }
            }
            Button { text: qsTr("+ Status"); onClicked: Api.call("upsertStatus", "", qsTr("New Status")) }
        }
    }
}
