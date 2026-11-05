import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Reading mode: the manuscript (or the selected folder) as a read-only book
// page, built by the same compile step as export, so you read what you
// would publish. Double-click to go back to editing the selected item.
Rectangle {
    id: rv
    color: Theme.dark ? "#1b1c1f" : "#e9e5dc"

    property bool active: false
    property var node: null              // the selected item (nodeInfo)
    property bool wholeBook: true
    property int fontSize: Theme.editorSize + 2
    property int columnWidth: 680
    property string html: ""
    property bool empty: true
    property var stats: null
    signal editRequested()

    // A folder (or document) inside the manuscript can be read on its own.
    readonly property bool canScope: node !== null && node.section === "manuscript" && !node.is_root
    readonly property int rev: Wordloom.revision
    onRevChanged: if (active) reload()
    onActiveChanged: if (active) reload()
    onWholeBookChanged: reload()
    onFontSizeChanged: if (active) reload()
    onNodeChanged: if (active && !wholeBook) reload()

    function reload() {
        const opts = {
            format: "html", title_page: wholeBook || !canScope, folder_titles: true,
            document_titles: false, number_chapters: false, scene_separator: "* * *"
        };
        if (!wholeBook && canScope) opts.root = node.id;
        const full = Api.get("compile", "", opts);
        // Keep the body; our own style suits Qt's rich text and the theme.
        const m = /<body>([\s\S]*)<\/body>/.exec(full);
        const body = (m ? m[1] : full)
            .replace(/<section class="title-page">/, "<div class='title'>")
            .replace(/<\/section>/, "</div><hr/>")
            .replace(/<p class="sep">/g, "<p class='sep' align='center'>")
            // Book style: no indent after a heading or scene break (Qt's rich
            // text has no "h2 + p" selector, so mark those paragraphs).
            .replace(/(<\/h[2-6]>\s*|<p class='sep'[^>]*>[^<]*<\/p>\s*)<p>/g, "$1<p style='text-indent:0px'>");
        empty = body.replace(/<[^>]*>/g, "").trim() === "";
        const ink = Theme.ink, sub = Theme.subtext;
        html = "<style>"
            + "body{color:" + ink + ";}"
            // Qt's rich text wants pixels for indents (it ignores em here).
            + "p{margin-top:0;margin-bottom:0;text-indent:" + Math.round(fontSize * 1.6) + "px;line-height:150%;}"
            + "h2{text-align:center;font-size:x-large;margin-top:48px;margin-bottom:24px;}"
            + "h3{text-align:center;font-size:large;margin-top:24px;margin-bottom:12px;}"
            + "p.sep{text-indent:0;color:" + sub + ";margin-top:14px;margin-bottom:14px;}"
            + "blockquote{margin-left:32px;margin-right:32px;font-style:italic;}"
            + ".title{text-align:center;margin-top:60px;margin-bottom:40px;}"
            + ".title h1{font-size:xx-large;} .author{text-indent:0;font-size:large;color:" + sub + ";}"
            + "</style>" + body;
        stats = Api.get("stats", null);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- header ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: Theme.panel
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 6
                Label { text: qsTr("Reading"); font.bold: true; color: Theme.text }
                ButtonGroup { id: scopeGroup }
                RadioButton { text: qsTr("Whole manuscript"); checked: rv.wholeBook; ButtonGroup.group: scopeGroup; onClicked: rv.wholeBook = true }
                RadioButton {
                    text: rv.canScope ? qsTr("Only “%1”").arg(rv.node.title) : qsTr("Selected item")
                    enabled: rv.canScope
                    checked: !rv.wholeBook
                    ButtonGroup.group: scopeGroup
                    onClicked: rv.wholeBook = false
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: rv.stats !== null && rv.wholeBook
                    text: rv.stats ? qsTr("%1 words · about %2 to read").arg(Api.fmtNumber(rv.stats.manuscript_words))
                        .arg(rv.stats.reading_minutes >= 60 ? Math.floor(rv.stats.reading_minutes / 60) + " h " + (rv.stats.reading_minutes % 60) + " min" : rv.stats.reading_minutes + " min") : ""
                    color: Theme.subtext
                }
                ToolSeparator {}
                ToolButton { text: "A−"; onClicked: rv.fontSize = Math.max(10, rv.fontSize - 1) }
                ToolButton { text: "A+"; onClicked: rv.fontSize = Math.min(36, rv.fontSize + 1) }
                ToolButton {
                    text: "⇔"
                    onClicked: rv.columnWidth = rv.columnWidth >= 980 ? 520 : rv.columnWidth + 160
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Column width: %1 px").arg(rv.columnWidth)
                }
                ToolButton { text: qsTr("Edit"); onClicked: rv.editRequested(); ToolTip.visible: hovered; ToolTip.text: qsTr("Back to the editor (or double-click the page)") }
            }
        }

        // ---- page ----
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: pageRect.height + 64
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Keys.onPressed: (e) => {
                const page = flick.height - 60;
                if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) flick.contentY = Math.min(flick.contentHeight - flick.height, flick.contentY + page);
                else if (e.key === Qt.Key_PageUp) flick.contentY = Math.max(0, flick.contentY - page);
                else if (e.key === Qt.Key_Home) flick.contentY = 0;
                else if (e.key === Qt.Key_End) flick.contentY = Math.max(0, flick.contentHeight - flick.height);
                else return;
                e.accepted = true;
            }

            Rectangle {
                id: pageRect
                x: (flick.width - width) / 2
                y: 32
                width: Math.min(rv.columnWidth + 120, flick.width - 32)
                height: Math.max(text.implicitHeight + 120, flick.height - 64)
                color: Theme.paper
                border.color: Theme.border
                radius: 3
                Text {
                    id: text
                    x: 60
                    y: 60
                    width: parent.width - 120
                    text: rv.html
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    font.family: Theme.editorFont
                    font.pixelSize: rv.fontSize
                    color: Theme.ink
                }
                TapHandler { onDoubleTapped: rv.editRequested(); onTapped: flick.forceActiveFocus() }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: rv.empty
        text: qsTr("Nothing to read yet: write something in the Manuscript.")
        color: Theme.subtext
    }
}
