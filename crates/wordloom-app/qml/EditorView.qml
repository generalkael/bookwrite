import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app
import com.wordloom.styling

// The writing surface. A single document is edited on its own; selecting a
// folder shows all of its documents stitched together as one continuous,
// editable manuscript ("composite" mode), each piece saving independently.
// An item with an imported file (image, PDF) shows the file instead.
//
// Workspace can show a second EditorView beside the first (split editor);
// that one is `secondary` and offers swap / close buttons.
Rectangle {
    id: ev
    color: focusMode ? (Theme.dark ? "#141517" : "#e9e5dc") : Theme.window

    property string nodeId: ""
    property var node: null
    property bool focusMode: false
    property bool typewriter: false
    property bool preview: false
    property var docs: []          // [{id, title, depth, folder}]
    property string activeId: ""
    property int activeCursor: 0
    property bool secondary: false
    property var activeArea: null      // the TextArea being typed in
    readonly property bool hasFile: node !== null && !!node.file
    signal openRequested(string id)
    signal swapRequested()
    signal closeRequested()

    readonly property int rev: Wordloom.revision
    onRevChanged: rebuild(false)
    onNodeIdChanged: rebuild(true)

    function flush() {
        for (let i = 0; i < rep.count; ++i) { const it = rep.itemAt(i); if (it) it.flush(); }
    }

    // ---- Markdown formatting (Ctrl+B / Ctrl+I and the format bar). Edits go
    // through the TextArea, so its own undo (Ctrl+Z) reverses them.
    function starsBefore(t, i) { let k = 0; while (i - k - 1 >= 0 && t[i - k - 1] === "*") ++k; return k; }
    function starsAfter(t, i) { let k = 0; while (i + k < t.length && t[i + k] === "*") ++k; return k; }
    // n = 1: italic, 2: bold. Wraps the selection, or unwraps it if already styled.
    function toggleEmphasis(n) {
        const a = activeArea;
        if (!a) return;
        const mark = n === 2 ? "**" : "*";
        const s = a.selectionStart, e = a.selectionEnd, t = a.text;
        if (s === e) { a.insert(s, mark + mark); a.cursorPosition = s + n; return; }
        const r = Math.min(starsBefore(t, s), starsAfter(t, e));
        const has = n === 1 ? (r === 1 || r >= 3) : r >= 2;
        if (has) { a.remove(e, e + n); a.remove(s - n, s); a.select(s - n, e - n); }
        else { a.insert(e, mark); a.insert(s, mark); a.select(s + n, e + n); }
    }
    function lineStart(t, i) { return t.lastIndexOf("\n", i - 1) + 1; }
    // No heading → # → ## → ### → none, on the caret's line.
    function cycleHeading() {
        const a = activeArea;
        if (!a) return;
        const ls = lineStart(a.text, a.cursorPosition);
        const m = /^(#{1,6}) /.exec(a.text.substring(ls));
        const level = m ? m[1].length : 0;
        const keep = a.cursorPosition - ls - (m ? m[0].length : 0);
        if (m) a.remove(ls, ls + m[0].length);
        const next = level >= 3 ? 0 : level + 1;
        if (next) a.insert(ls, "#".repeat(next) + " ");
        a.cursorPosition = ls + Math.max(0, keep) + (next ? next + 1 : 0);
    }
    // Quote or unquote every line the selection touches.
    function toggleQuote() {
        const a = activeArea;
        if (!a) return;
        const t = a.text;
        const starts = [];
        for (let i = lineStart(t, a.selectionStart); i <= a.selectionEnd; i = t.indexOf("\n", i) + 1) {
            starts.push(i);
            if (t.indexOf("\n", i) < 0) break;
        }
        const quoted = starts.every(i => t.startsWith(">", i));
        for (let k = starts.length - 1; k >= 0; --k) {
            const i = starts[k];
            if (quoted) a.remove(i, i + (t.startsWith("> ", i) ? 2 : 1));
            else a.insert(i, "> ");
        }
    }
    function sceneBreak() {
        const a = activeArea;
        if (!a) return;
        const p = a.cursorPosition, head = a.text.substring(0, p);
        // Start on a fresh paragraph.
        const before = p === 0 || head.endsWith("\n\n") ? "" : head.endsWith("\n") ? "\n" : "\n\n";
        a.insert(p, before + "* * *\n\n");
    }

    function collect(id, depth, out) {
        const kids = Api.get("children", [], id);
        for (const k of kids) {
            out.push({ id: k.id, title: k.title, depth: depth, folder: k.kind === "folder" });
            if (k.child_count > 0) collect(k.id, depth + 1, out);
        }
    }

    function rebuild(force) {
        if (!node || node.file) { docs = []; return; }
        const out = [{ id: node.id, title: node.title, depth: 0, folder: node.kind === "folder" }];
        if (node.child_count > 0) collect(node.id, 1, out);
        const sig = out.map(d => d.id + d.title).join("|");
        const old = docs.map(d => d.id + d.title).join("|");
        if (force || sig !== old) {
            flush();
            docs = out;
            if (force) scroller.contentItem.contentY = 0;
        } else {
            for (let i = 0; i < rep.count; ++i) { const it = rep.itemAt(i); if (it) it.syncFromStore(); }
        }
        if (docs.length) activeId = activeId && docs.some(d => d.id === activeId) ? activeId : docs[docs.length > 1 && docs[0].folder ? 1 : 0].id;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Editor header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            visible: !ev.focusMode && ev.node !== null
            color: Theme.window
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                KindIcon { visible: ev.node !== null; kind: ev.node ? ev.node.kind : ""; role: ev.node ? (ev.node.role || "") : "" }
                Label { text: ev.node ? ev.node.title : ""; font.bold: true; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { visible: ev.docs.length > 1; text: qsTr("Composite · %1 parts").arg(ev.docs.length); color: Theme.subtext }
                ToolButton { visible: ev.hasFile; text: qsTr("Open in Default App"); onClicked: fileViewer.openExternally() }
                // Format bar
                Repeater {
                    model: ev.hasFile || ev.preview ? [] : [
                        { label: "B", tip: qsTr("Bold (Ctrl+B)"), act: () => ev.toggleEmphasis(2), bold: true },
                        { label: "I", tip: qsTr("Italic (Ctrl+I)"), act: () => ev.toggleEmphasis(1), italic: true },
                        { label: "H", tip: qsTr("Heading: none → # → ## → ###"), act: () => ev.cycleHeading(), bold: true },
                        { label: "“", tip: qsTr("Block quote"), act: () => ev.toggleQuote() },
                        { label: "* * *", tip: qsTr("Scene break"), act: () => ev.sceneBreak() }
                    ]
                    delegate: ToolButton {
                        required property var modelData
                        text: modelData.label
                        font.bold: !!modelData.bold
                        font.italic: !!modelData.italic
                        focusPolicy: Qt.NoFocus
                        enabled: ev.activeArea !== null
                        onClicked: modelData.act()
                        ToolTip.visible: hovered
                        ToolTip.text: modelData.tip
                    }
                }
                ToolSeparator { visible: !ev.hasFile && !ev.preview }
                ToolButton { visible: !ev.hasFile; text: qsTr("Preview"); checkable: true; checked: ev.preview; onToggled: { ev.flush(); ev.preview = checked; } ToolTip.visible: hovered; ToolTip.text: qsTr("Render Markdown formatting") }
                ToolButton { visible: !ev.hasFile; text: qsTr("Typewriter"); checkable: true; checked: ev.typewriter; onToggled: ev.typewriter = checked; ToolTip.visible: hovered; ToolTip.text: qsTr("Keep the current line centred") }
                ToolButton { visible: !ev.hasFile; text: "A−"; onClicked: Theme.editorSize = Math.max(9, Theme.editorSize - 1) }
                ToolButton { visible: !ev.hasFile; text: "A+"; onClicked: Theme.editorSize = Math.min(40, Theme.editorSize + 1) }
                ToolButton { visible: !ev.hasFile; text: "⇔"; onClicked: Theme.pageWidth = Theme.pageWidth >= 1100 ? 560 : Theme.pageWidth + 180; ToolTip.visible: hovered; ToolTip.text: qsTr("Page width") }
                ToolSeparator { visible: ev.secondary }
                ToolButton { visible: ev.secondary; text: "⇄"; onClicked: ev.swapRequested(); ToolTip.visible: hovered; ToolTip.text: qsTr("Swap with the main editor") }
                ToolButton { visible: ev.secondary; text: "✕"; onClicked: ev.closeRequested(); ToolTip.visible: hovered; ToolTip.text: qsTr("Close split (Ctrl+\\)") }
            }
        }

        FileViewer {
            id: fileViewer
            visible: ev.hasFile
            Layout.fillWidth: true
            Layout.fillHeight: true
            file: ev.hasFile ? ev.node.file : null
        }

        ScrollView {
            id: scroller
            visible: !ev.hasFile
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Don't let content size feed back into the layout (binding loop).
            Layout.preferredHeight: 100
            Layout.preferredWidth: 100
            clip: true
            contentWidth: scroller.width - 14
            contentHeight: page.height + 48

            Item {
                width: scroller.width - 14
                height: page.height + 48

                Rectangle {
                    id: page
                    width: Math.min(Theme.pageWidth + 96, parent.width - 24)
                    height: Math.max(col.height + 96, 640)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    color: Theme.paper
                    border.color: Theme.border
                    radius: 3
                    visible: ev.node !== null

                    Column {
                        id: col
                        x: 48
                        y: 48
                        width: page.width - 96
                        spacing: 6

                        Repeater {
                            id: rep
                            model: ev.docs
                            delegate: DocEditor {
                                required property var modelData
                                required property int index
                                width: col.width
                                docId: modelData.id
                                docTitle: modelData.title
                                depth: modelData.depth
                                isFolder: modelData.folder
                                composite: ev.docs.length > 1
                                first: index === 0
                            }
                        }
                    }
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: ev.node === null
        text: qsTr("Select a document in the binder, or press Ctrl+N to create one.")
        color: Theme.subtext
    }

    component DocEditor: ColumnLayout {
        id: de
        property string docId
        property string docTitle
        property int depth: 0
        property bool isFolder: false
        property bool composite: false
        property bool first: false
        property string saved: ""
        property bool loading: false
        spacing: 2

        Component.onCompleted: load()
        onDocIdChanged: load()

        function load() {
            loading = true;
            saved = Api.get("text", "", docId);
            area.text = saved;
            loading = false;
        }
        function flush() {
            saveTimer.stop();
            if (!loading && area.text !== saved) {
                Api.call("setText", docId, area.text);
                saved = area.text;
                Api.textSaved(docId);
            }
        }
        Connections {
            target: Api
            function onTextSaved(id) { if (id === de.docId) de.syncFromStore(); }
        }
        // Pick up external changes (snapshot restore, replace-all) unless the
        // user is mid-edit here.
        function syncFromStore() {
            if (area.activeFocus || saveTimer.running) return;
            const t = Api.get("text", "", docId);
            if (t !== saved) { loading = true; saved = t; area.text = t; loading = false; }
        }

        // Section heading between parts in composite mode.
        RowLayout {
            visible: de.composite
            Layout.fillWidth: true
            Layout.topMargin: de.first ? 0 : 18
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; visible: !de.first }
            Label {
                text: de.docTitle
                color: de.isFolder ? Theme.accent : Theme.subtext
                font.pixelSize: de.isFolder ? 13 : 11
                font.bold: de.isFolder
                font.capitalization: Font.AllUppercase
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ev.openRequested(de.docId) }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        }

        TextArea {
            id: area
            visible: !ev.preview && !(de.composite && de.isFolder && text.length === 0 && !activeFocus)
            Layout.fillWidth: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            selectByMouse: true
            persistentSelection: true
            font.family: Theme.editorFont
            font.pixelSize: Theme.editorSize
            color: Theme.ink
            selectionColor: Theme.selection
            selectedTextColor: Theme.ink
            placeholderText: de.composite ? "" : qsTr("Begin writing…")
            background: null
            leftPadding: 0
            rightPadding: 0
            topPadding: 2
            bottomPadding: 2
            onTextChanged: if (!de.loading) saveTimer.restart()
            onActiveFocusChanged: { if (activeFocus) { ev.activeId = de.docId; ev.activeArea = area; } else de.flush(); }
            Keys.onPressed: (e) => {
                if ((e.modifiers & Qt.ControlModifier) && !(e.modifiers & (Qt.ShiftModifier | Qt.AltModifier))) {
                    if (e.key === Qt.Key_B) { ev.activeArea = area; ev.toggleEmphasis(2); e.accepted = true; }
                    else if (e.key === Qt.Key_I) { ev.activeArea = area; ev.toggleEmphasis(1); e.accepted = true; }
                }
            }
            MarkdownStyler {
                document: area.textDocument
                enabled: Theme.styledMarkdown
                markColor: Theme.dark ? "#6f6d68" : "#b3afa6"
                quoteColor: Theme.subtext
            }
            onCursorPositionChanged: {
                if (activeFocus) ev.activeCursor = cursorPosition;
                if (ev.typewriter && activeFocus) {
                    const p = area.mapToItem(scroller.contentItem.contentItem, 0, cursorRectangle.y);
                    scroller.contentItem.contentY = Math.max(0, p.y - scroller.height / 2);
                }
            }
        }
        Text {
            visible: ev.preview
            Layout.fillWidth: true
            text: area.text
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap
            font.family: Theme.editorFont
            font.pixelSize: Theme.editorSize
            color: Theme.ink
            lineHeight: Theme.lineHeight
        }
        Timer { id: saveTimer; interval: 800; onTriggered: de.flush() }
    }
}
