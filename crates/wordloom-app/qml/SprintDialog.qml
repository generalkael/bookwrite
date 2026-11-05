import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Writing sprint: write for a set time (optionally toward a word goal).
// The dialog can be closed while a sprint runs; the status bar shows the
// countdown and reopens it. Finished sprints are kept in the project.
Dialog {
    id: sd
    title: qsTr("Writing Sprint")
    modal: false
    width: 480
    standardButtons: Dialog.Close

    // ---- state ----
    property bool running: false
    property bool paused: false
    property int durationMin: 25
    property int goal: 0
    property int startWords: 0
    property real elapsedMs: 0
    property real lastTick: 0
    property int words: 0
    // The last finished sprint. (Not "result": Dialog already has one.)
    property var lastSprint: null
    property var summary: null
    readonly property real totalMs: durationMin * 60000
    readonly property real remainingMs: Math.max(0, totalMs - elapsedMs)
    readonly property string clock: {
        const s = Math.ceil(remainingMs / 1000);
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }
    // Set by Main: flushes the editors before words are counted.
    property var flush: function () {}

    function manuscriptWords() { flush(); const s = Api.get("stats", null); return s ? s.manuscript_words : 0; }
    function reloadSummary() { summary = Api.get("sprints", null); }
    onAboutToShow: reloadSummary()

    function start() {
        startWords = manuscriptWords();
        words = 0;
        elapsedMs = 0;
        lastTick = Date.now();
        paused = false;
        lastSprint = null;
        running = true;
        close();   // get out of the way; the status bar shows the countdown
        Api.say(qsTr("Sprint started: %1 minutes. Go!").arg(durationMin));
    }
    function togglePause() {
        paused = !paused;
        lastTick = Date.now();
    }
    // Finish (and save) the sprint, or with `discard` throw it away.
    function finish(discard) {
        if (!running) return;
        tick();
        running = false;
        if (discard) { Api.say(qsTr("Sprint cancelled")); return; }
        words = manuscriptWords() - startWords;
        const minutes = Math.max(1 / 60, elapsedMs / 60000);
        Api.call("recordSprint", minutes, words, goal);
        lastSprint = { minutes: minutes, words: words, goal: goal };
        reloadSummary();
        Api.say(goal > 0 && words >= goal ? qsTr("Sprint done: %1 words. Goal reached!").arg(words)
                                          : qsTr("Sprint done: %1 words in %2").arg(words).arg(duration(minutes)));
        open();
    }
    function tick() {
        const now = Date.now();
        if (!paused) elapsedMs += now - lastTick;
        lastTick = now;
    }
    Timer {
        interval: 500
        repeat: true
        running: sd.running
        onTriggered: {
            sd.tick();
            sd.words = sd.manuscriptWords() - sd.startWords;
            if (sd.remainingMs <= 0) sd.finish(false);
        }
    }

    function pace(words, minutes) { return minutes > 0 ? (words / minutes).toFixed(1) : "0"; }
    // "25 min", "2 min 30 s", "40 s"
    function duration(minutes) {
        const secs = Math.round(minutes * 60);
        if (secs < 60) return qsTr("%1 s").arg(secs);
        const m = Math.floor(secs / 60), s = secs % 60;
        return m >= 10 || s === 0 ? qsTr("%1 min").arg(Math.round(minutes)) : qsTr("%1 min %2 s").arg(m).arg(s);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ---- setup ----
        ColumnLayout {
            visible: !sd.running
            Layout.fillWidth: true
            spacing: 8
            Label { text: qsTr("Length"); font.bold: true; color: Theme.text }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [5, 10, 15, 20, 25, 30, 45, 60]
                    delegate: Button {
                        required property int modelData
                        text: qsTr("%1 min").arg(modelData)
                        checkable: true
                        checked: sd.durationMin === modelData
                        flat: !checked
                        onClicked: sd.durationMin = modelData
                    }
                }
            }
            RowLayout {
                Label { text: qsTr("Minutes") }
                SpinBox { from: 1; to: 240; value: sd.durationMin; editable: true; onValueModified: sd.durationMin = value }
                Item { Layout.preferredWidth: 16 }
                Label { text: qsTr("Word goal") }
                SpinBox { from: 0; to: 20000; stepSize: 50; value: sd.goal; editable: true; onValueModified: sd.goal = value }
                Label { text: sd.goal === 0 ? qsTr("(none)") : ""; color: Theme.subtext }
            }
            Button {
                text: qsTr("Start Sprint")
                highlighted: true
                Layout.alignment: Qt.AlignRight
                onClicked: sd.start()
            }
        }

        // ---- running ----
        ColumnLayout {
            visible: sd.running
            Layout.fillWidth: true
            spacing: 6
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: sd.clock
                font.pixelSize: 56
                font.bold: true
                color: sd.paused ? Theme.subtext : Theme.text
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: (sd.paused ? qsTr("Paused · ") : "") + qsTr("%1 words so far").arg(Api.fmtNumber(sd.words))
                      + (sd.goal > 0 ? qsTr(" of %1").arg(Api.fmtNumber(sd.goal)) : "")
                color: Theme.subtext
            }
            ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 1
                value: sd.goal > 0 ? Math.min(1, Math.max(0, sd.words) / sd.goal) : sd.elapsedMs / sd.totalMs
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Button { text: sd.paused ? qsTr("Resume") : qsTr("Pause"); onClicked: sd.togglePause() }
                Button { text: qsTr("Finish Now"); highlighted: true; onClicked: sd.finish(false) }
                Button { text: qsTr("Cancel Sprint"); flat: true; onClicked: sd.finish(true) }
            }
        }

        // ---- last result ----
        Rectangle {
            visible: !sd.running && sd.lastSprint !== null
            Layout.fillWidth: true
            Layout.preferredHeight: resultLabel.implicitHeight + 16
            radius: 4
            color: sd.lastSprint && sd.lastSprint.goal > 0 && sd.lastSprint.words >= sd.lastSprint.goal ? Qt.rgba(0.35, 0.62, 0.35, 0.18) : Theme.accentSoft
            Label {
                id: resultLabel
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.text
                text: !sd.lastSprint ? "" : qsTr("%1 words in %2 (%3 per minute)").arg(Api.fmtNumber(sd.lastSprint.words)).arg(sd.duration(sd.lastSprint.minutes)).arg(sd.pace(sd.lastSprint.words, sd.lastSprint.minutes))
                      + (sd.lastSprint.goal > 0 ? (sd.lastSprint.words >= sd.lastSprint.goal ? qsTr(" · goal reached!") : qsTr(" · goal was %1").arg(Api.fmtNumber(sd.lastSprint.goal))) : "")
            }
        }

        // ---- history ----
        ColumnLayout {
            visible: !sd.running && sd.summary !== null && sd.summary.count > 0
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: !sd.summary ? "" : qsTr("%1 sprints · %2 words · best %3 words · best pace %4 / min")
                    .arg(sd.summary.count).arg(Api.fmtNumber(sd.summary.total_words))
                    .arg(sd.summary.best_words !== null ? Api.fmtNumber(sd.summary.best_words) : "—")
                    .arg(sd.summary.best_pace !== null ? sd.summary.best_pace.toFixed(1) : "—")
                color: Theme.subtext
                font.pixelSize: 11
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Repeater {
                model: sd.summary ? sd.summary.recent.slice(0, 6) : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: new Date(modelData.started).toLocaleString(Qt.locale(), Locale.ShortFormat); color: Theme.subtext; Layout.preferredWidth: 150 }
                    Label { text: sd.duration(modelData.minutes); color: Theme.text; Layout.preferredWidth: 80 }
                    Label { text: qsTr("%1 words").arg(Api.fmtNumber(modelData.words)); color: Theme.text; Layout.fillWidth: true }
                    Label { visible: !!modelData.goal && modelData.words >= modelData.goal; text: "✓"; color: Theme.ok }
                }
            }
        }
    }
}
