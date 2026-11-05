import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Name generator: pick a style and gender, generate a list, and add any
// name as a new character (or copy it).
Dialog {
    id: dlg
    title: qsTr("Name Generator")
    modal: true
    width: 460
    height: Math.min(560, parent ? parent.height - 60 : 560)
    standardButtons: Dialog.Close

    property var styles: []
    property var names: []
    property var added: ({})
    readonly property var genders: ["any", "feminine", "masculine"]

    function generate() {
        if (!styles.length) return;
        names = Api.get("generateNames", [], styles[styleBox.currentIndex].id, genders[genderBox.currentIndex], 12);
    }
    onAboutToShow: {
        if (!styles.length) styles = Api.get("nameStyles", []);
        added = ({});
        generate();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ComboBox { id: styleBox; Layout.fillWidth: true; model: dlg.styles.map(s => s.label); onActivated: dlg.generate() }
            ComboBox { id: genderBox; model: [qsTr("Any"), qsTr("Feminine"), qsTr("Masculine")]; onActivated: dlg.generate() }
            Button { text: qsTr("Generate"); highlighted: true; onClicked: dlg.generate() }
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: dlg.names
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: row
                required property string modelData
                width: ListView.view.width
                contentItem: RowLayout {
                    Label { text: row.modelData; color: Theme.text; Layout.fillWidth: true; font.pixelSize: 15 }
                    ToolButton {
                        text: dlg.added[row.modelData] ? qsTr("Added ✓") : qsTr("Add as Character")
                        enabled: !dlg.added[row.modelData]
                        onClicked: {
                            const id = Api.call("add", Api.call("rootId", "characters"), "character", row.modelData, true);
                            if (id) { const a = Object.assign({}, dlg.added); a[row.modelData] = true; dlg.added = a; Api.say(qsTr("Added %1 to Characters").arg(row.modelData)); }
                        }
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.subtext
            font.pixelSize: 11
            text: qsTr("Real-world styles pair common given names with surnames; Fantasy builds new names from syllables. Generate again for a fresh list.")
        }
    }
}
