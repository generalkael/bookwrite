import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import com.wordloom.app

// Shown when no project is open: create, open, or pick a recent project.
Rectangle {
    id: page
    color: Theme.window
    signal newRequested()
    signal openRequested()
    signal recentChosen(string path)

    property var recent: Api.get("recent", [])
    Component.onCompleted: recent = Api.call("recent") || []

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 80)
        spacing: 18

        Label {
            text: "Wordloom"
            font.pixelSize: 44
            font.family: Theme.editorFont
            color: Theme.text
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            text: qsTr("Weave your story — draft, structure, and plot it on a timeline.")
            color: Theme.subtext
            Layout.alignment: Qt.AlignHCenter
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            Button { text: qsTr("New Project…"); highlighted: true; onClicked: page.newRequested() }
            Button { text: qsTr("Open Project…"); onClicked: page.openRequested() }
            Button {
                text: qsTr("Explore the Sample")
                onClicked: Api.call("newDemoProject", StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/Wordloom")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("A short sample novel with characters, a timeline and conflicts")
            }
        }
        Label {
            visible: page.recent.length > 0
            text: qsTr("Recent projects")
            font.bold: true
            color: Theme.subtext
            Layout.topMargin: 16
        }
        Rectangle {
            visible: page.recent.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(320, recentList.contentHeight + 2)
            color: Theme.base
            border.color: Theme.border
            radius: Theme.radius
            ListView {
                id: recentList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: page.recent
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    contentItem: ColumnLayout {
                        spacing: 2
                        Label { text: modelData.title; font.bold: true; color: Theme.text }
                        Label { text: modelData.path; color: Theme.subtext; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                    onClicked: page.recentChosen(modelData.path)
                }
            }
        }
    }
}
