import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Writing statistics, targets and a 30-day history.
Dialog {
    id: dlg
    title: qsTr("Writing Statistics & Targets")
    modal: true
    width: 640
    standardButtons: Dialog.Close
    property var s: null
    onAboutToShow: load()
    function load() {
        s = Api.get("stats", null);
        if (!s) return;
        msTarget.text = s.manuscript_target ? String(s.manuscript_target) : "";
        sessTarget.text = s.session_target ? String(s.session_target) : "";
        deadline.text = s.deadline || "";
    }
    function save() {
        Api.call("setTargets", parseInt(msTarget.text) || 0, parseInt(sessTarget.text) || 0, deadline.text);
        load();
    }
    readonly property int maxDay: s ? Math.max(1, ...s.history.map(h => Math.abs(h[1]))) : 1

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        GridLayout {
            columns: 4
            columnSpacing: 24
            rowSpacing: 6
            Repeater {
                model: dlg.s ? [
                    [qsTr("Manuscript words"), Api.fmtNumber(dlg.s.manuscript_words)],
                    [qsTr("Project words"), Api.fmtNumber(dlg.s.project_words)],
                    [qsTr("Characters"), Api.fmtNumber(dlg.s.manuscript_chars)],
                    [qsTr("Documents"), Api.fmtNumber(dlg.s.documents)],
                    [qsTr("Written today"), Api.fmtNumber(dlg.s.words_today)],
                    [qsTr("Streak"), Api.plural(dlg.s.streak_days, qsTr("day"))],
                    [qsTr("Reading time"), dlg.s.reading_minutes >= 60 ? Math.floor(dlg.s.reading_minutes / 60) + "h " + (dlg.s.reading_minutes % 60) + "m" : dlg.s.reading_minutes + " min"],
                    [qsTr("Needed per day"), dlg.s.words_per_day_needed !== null ? Api.fmtNumber(dlg.s.words_per_day_needed) : "—"]
                ] : []
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 0
                    Label { text: modelData[0]; color: Theme.subtext; font.pixelSize: 11 }
                    Label { text: modelData[1]; font.pixelSize: 20; color: Theme.text }
                }
            }
        }

        ProgressBar {
            visible: dlg.s && !!dlg.s.manuscript_target
            Layout.fillWidth: true
            from: 0; to: 1
            value: dlg.s && dlg.s.manuscript_target ? Math.min(1, dlg.s.manuscript_words / dlg.s.manuscript_target) : 0
        }

        Label { text: qsTr("Last 30 days"); font.bold: true; color: Theme.text }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            Row {
                anchors.fill: parent
                spacing: 2
                Repeater {
                    model: dlg.s ? dlg.s.history : []
                    delegate: Item {
                        required property var modelData
                        width: (parent.width - 29 * 2) / 30
                        height: parent.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(1, (parent.height - 4) * Math.abs(modelData[1]) / dlg.maxDay)
                            radius: 2
                            color: modelData[1] < 0 ? Theme.danger : (dlg.s.session_target && modelData[1] >= dlg.s.session_target ? Theme.ok : Theme.accent)
                            opacity: modelData[1] === 0 ? 0.25 : 1
                        }
                        ToolTip.visible: hov.hovered
                        ToolTip.text: modelData[0] + ": " + modelData[1]
                        HoverHandler { id: hov }
                    }
                }
            }
        }

        Label { text: qsTr("Targets"); font.bold: true; color: Theme.text }
        GridLayout {
            columns: 3
            Label { text: qsTr("Manuscript target (words)") }
            TextField { id: msTarget; Layout.preferredWidth: 140; validator: IntValidator { bottom: 0 } }
            Item {}
            Label { text: qsTr("Daily session target") }
            TextField { id: sessTarget; Layout.preferredWidth: 140; validator: IntValidator { bottom: 0 } }
            Item {}
            Label { text: qsTr("Deadline (YYYY-MM-DD)") }
            TextField { id: deadline; Layout.preferredWidth: 140; placeholderText: "2027-03-31" }
            Button { text: qsTr("Save Targets"); onClicked: dlg.save() }
        }
        Label {
            visible: dlg.s && dlg.s.days_left !== null
            text: dlg.s && dlg.s.days_left !== null ? qsTr("%1 until the deadline.").arg(Api.plural(dlg.s.days_left, qsTr("day"))) : ""
            color: Theme.subtext
        }
    }
}
