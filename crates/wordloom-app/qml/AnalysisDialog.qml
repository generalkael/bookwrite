import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Text Analysis (Project ▸ Text Analysis…): habits worth a look when
// revising: your most used words and phrases, -ly adverbs, long sentences,
// and how much is dialogue. For the whole manuscript or the selected item.
Dialog {
    id: ad
    title: qsTr("Text Analysis")
    modal: false
    width: Math.min(760, parent ? parent.width - 40 : 760)
    height: Math.min(640, parent ? parent.height - 40 : 640)
    standardButtons: Dialog.Close

    property var node: null              // the selected item (nodeInfo)
    property bool wholeBook: true
    property var r: null
    signal searchRequested(string text)
    signal sentenceRequested(string docId, string text)

    readonly property bool canScope: node !== null && !node.is_root && node.section !== "trash"
    onAboutToShow: reload()
    onWholeBookChanged: if (visible) reload()
    onNodeChanged: if (visible && !wholeBook) reload()

    function reload() { r = Api.get("analyse", null, wholeBook || !canScope ? "" : node.id); }
    function pct(x) { return Math.round(x * 100) + "%"; }
    // "per 1,000 words"
    function per1000(n) { return r && r.words ? (n * 1000 / r.words).toFixed(1) : "0"; }
    // The first words of a sentence, to find it in its document.
    function opening(s) { return s.replace(/…$/, "").split(" ").slice(0, 6).join(" ").replace(/[,;:]$/, ""); }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            ButtonGroup { id: scopeGroup }
            RadioButton { text: qsTr("Whole manuscript"); checked: ad.wholeBook; ButtonGroup.group: scopeGroup; onClicked: ad.wholeBook = true }
            RadioButton {
                text: ad.canScope ? qsTr("Only “%1”").arg(ad.node.title) : qsTr("Selected item")
                enabled: ad.canScope
                checked: !ad.wholeBook
                ButtonGroup.group: scopeGroup
                onClicked: ad.wholeBook = false
            }
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Refresh"); flat: true; onClicked: ad.reload() }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 24
            rowSpacing: 6
            Repeater {
                model: ad.r ? [
                    [qsTr("Words"), Api.fmtNumber(ad.r.words), qsTr("in %1").arg(Api.plural(ad.r.documents, qsTr("document")))],
                    [qsTr("Different words"), Api.fmtNumber(ad.r.unique_words), ""],
                    [qsTr("Sentences"), Api.fmtNumber(ad.r.sentences), qsTr("%1 paragraphs").arg(Api.fmtNumber(ad.r.paragraphs))],
                    [qsTr("Average sentence"), qsTr("%1 words").arg(ad.r.avg_sentence_words.toFixed(1)), ""],
                    [qsTr("Dialogue"), ad.pct(ad.r.dialogue_share), qsTr("of the words are in quotes")],
                    [qsTr("-ly adverbs"), Api.fmtNumber(ad.r.ly_words), qsTr("%1 per 1,000 words").arg(ad.per1000(ad.r.ly_words))]
                ] : []
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    Label { text: modelData[0]; color: Theme.subtext; font.pixelSize: 11 }
                    Label { text: modelData[1]; font.pixelSize: 20; color: Theme.text }
                    Label { visible: modelData[2] !== ""; text: modelData[2]; color: Theme.subtext; font.pixelSize: 11 }
                }
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: qsTr("Most used words") }
            TabButton { text: qsTr("Repeated phrases") }
            TabButton { text: qsTr("-ly adverbs") }
            TabButton { text: qsTr("Long sentences") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            CountList { items: ad.r ? ad.r.top_words : []; empty: qsTr("Not enough text yet.") }
            CountList { items: ad.r ? ad.r.phrases : []; empty: qsTr("No three-word phrase is used twice.") }
            CountList { items: ad.r ? ad.r.top_ly : []; empty: qsTr("No -ly adverbs.") }
            ListView {
                clip: true
                model: ad.r ? ad.r.longest : []
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    onClicked: ad.sentenceRequested(modelData.node, ad.opening(modelData.text))
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Open “%1” at this sentence").arg(modelData.title)
                    contentItem: ColumnLayout {
                        spacing: 1
                        Label { text: qsTr("%1 words · %2").arg(modelData.words).arg(modelData.title); color: Theme.subtext; font.pixelSize: 11 }
                        Label { text: modelData.text; textFormat: Text.PlainText; color: Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: qsTr("No sentences of 25 words or more.")
                    color: Theme.subtext
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Click a word or phrase to find it in the project. Common words (the, and, said…) are left out, and comments aren't counted.")
            color: Theme.subtext
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }

    // A ranked list with a bar for each count.
    component CountList: ListView {
        id: cl
        property var items: []
        property string empty: ""
        readonly property int maxCount: items.length ? items[0].count : 1
        clip: true
        model: items
        ScrollBar.vertical: ScrollBar {}
        delegate: ItemDelegate {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 28
            onClicked: ad.searchRequested(modelData.text)
            contentItem: RowLayout {
                spacing: 8
                Label { text: (index + 1) + "."; color: Theme.subtext; Layout.preferredWidth: 26; horizontalAlignment: Text.AlignRight }
                Label { text: modelData.text; textFormat: Text.PlainText; color: Theme.text; Layout.preferredWidth: 220; elide: Text.ElideRight }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    color: "transparent"
                    Rectangle { width: parent.width * modelData.count / cl.maxCount; height: parent.height; radius: 3; color: Theme.accent; opacity: 0.7 }
                }
                Label { text: Api.fmtNumber(modelData.count); color: Theme.subtext; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
            }
        }
        Label {
            anchors.centerIn: parent
            visible: cl.count === 0
            text: cl.empty
            color: Theme.subtext
        }
    }
}
