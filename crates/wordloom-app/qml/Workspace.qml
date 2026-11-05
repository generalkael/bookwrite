import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// The main three-pane layout: binder | view | inspector, plus toolbar and
// status bar. Owns the current selection and view mode.
Item {
    id: ws

    property string currentId: ""
    property var current: null          // nodeInfo of currentId
    property string viewMode: "editor"  // editor | corkboard | outliner | timeline
    property bool focusMode: false
    property bool showBinder: true
    property bool showInspector: true
    property var stats: null

    readonly property int rev: Wordloom.revision
    onRevChanged: refresh()
    onCurrentIdChanged: refresh()

    function refresh() {
        current = currentId !== "" ? (Api.get("nodeInfo", null, currentId)) : null;
        if (currentId !== "" && current === null) currentId = "";
        stats = Api.get("stats", null);
    }

    function select(id, mode) {
        flush();
        currentId = id;
        if (mode) viewMode = mode;
        else if (viewMode === "timeline") viewMode = "editor";
        else if (current && current.kind === "folder" && viewMode === "editor" && current.child_count > 0 && current.words === 0)
            viewMode = "corkboard";
    }

    function flush() { if (editorView) editorView.flush(); }

    function target() {
        return currentId !== "" ? currentId : Api.call("rootId", "manuscript");
    }
    function addItem(kind) {
        const t = target();
        const inside = current && (current.is_root || (current.kind === "folder" && kind !== "folder"));
        const id = Api.call("add", t, kind, "", !!inside);
        if (id) { select(id, kind === "folder" ? "corkboard" : "editor"); binder.startRename(id); }
    }
    function addInSection(role) {
        const root = Api.call("rootId", role);
        const id = Api.call("add", root, "", "", true);
        if (id) { select(id, "editor"); binder.startRename(id); }
    }
    function duplicate() { if (currentId) { const id = Api.call("duplicate", currentId); if (id) select(id); } }
    function trashCurrent() {
        if (!currentId || (current && current.is_root)) return;
        Api.call("trash", currentId);
        currentId = "";
    }
    function emptyTrash() {
        const n = Api.call("emptyTrash");
        if (n !== undefined) Api.say(qsTr("Deleted %1 item(s) permanently").arg(n));
    }
    function snapshot() {
        if (!currentId) return;
        flush();
        if (Api.call("takeSnapshot", currentId, "") !== undefined) { Api.say(qsTr("Snapshot taken")); inspector.reloadSnapshots(); }
    }
    function splitAtCursor() {
        if (viewMode !== "editor" || !editorView.activeId) return;
        flush();
        const id = Api.call("split", editorView.activeId, editorView.activeCursor, "");
        if (id) { select(id, "editor"); binder.startRename(id); }
    }
    function mergeNext() { if (currentId) { flush(); Api.call("mergeWithNext", currentId); } }
    function focusSearch() { binder.focusSearch(); }
    function eventDialog() { return gantt.eventDialogRef; }
    function closePopups() { gantt.closeDialogs(); }
    function editAnEvent() { viewMode = "timeline"; gantt.editFirstEvent(); }
    function searchFor(q) { binder.searchText = q; }

    // Word counts change as the user types (text saves don't bump the
    // revision, so the caret is never disturbed); refresh the numbers gently.
    Timer {
        interval: 2500
        repeat: true
        running: Wordloom.dirty
        onTriggered: {
            ws.stats = Api.get("stats", null);
            if (ws.currentId !== "") ws.current = Api.get("nodeInfo", ws.current, ws.currentId);
        }
    }

    Component.onCompleted: {
        // Open the first scene of the manuscript.
        const ms = Api.call("rootId", "manuscript");
        let kids = Api.get("children", [], ms);
        while (kids.length && kids[0].kind === "folder" && kids[0].child_count > 0) kids = Api.get("children", [], kids[0].id);
        if (kids.length) select(kids[0].id, "editor");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- toolbar ----------------
        ToolBar {
            Layout.fillWidth: true
            visible: !ws.focusMode
            background: Rectangle { color: Theme.panel; Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border } }
            RowLayout {
                anchors.fill: parent
                spacing: 4
                ToolButton { text: "＋ " + qsTr("Document"); onClicked: ws.addItem("text"); ToolTip.visible: hovered; ToolTip.text: qsTr("New document (Ctrl+N)") }
                ToolButton { text: "＋ " + qsTr("Folder"); onClicked: ws.addItem("folder") }
                ToolSeparator {}
                Repeater {
                    model: [
                        { mode: "editor", label: qsTr("✎ Editor") },
                        { mode: "corkboard", label: qsTr("▦ Corkboard") },
                        { mode: "outliner", label: qsTr("☰ Outliner") },
                        { mode: "timeline", label: qsTr("▤ Timeline") }
                    ]
                    delegate: ToolButton {
                        required property var modelData
                        text: modelData.label
                        checkable: true
                        checked: ws.viewMode === modelData.mode
                        onClicked: ws.viewMode = modelData.mode
                    }
                }
                ToolSeparator {}
                ToolButton { text: qsTr("◎ Focus"); onClicked: ws.focusMode = true; ToolTip.visible: hovered; ToolTip.text: qsTr("Distraction-free writing (F11, Esc to leave)") }
                ToolButton { text: qsTr("⎙ Snapshot"); enabled: ws.currentId !== ""; onClicked: ws.snapshot() }
                Item { Layout.fillWidth: true }
                Label {
                    visible: ws.current !== null
                    text: ws.current ? ws.current.breadcrumbs.concat([ws.current.title]).join("  ›  ") : ""
                    color: Theme.subtext
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 420
                }
                ToolSeparator {}
                ToolButton { text: ws.showInspector ? qsTr("Hide Inspector") : qsTr("Inspector"); onClicked: ws.showInspector = !ws.showInspector }
            }
        }

        // ---------------- panes ----------------
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal
            handle: Rectangle {
                implicitWidth: 5
                color: SplitHandle.hovered || SplitHandle.pressed ? Theme.accent : Theme.border
                opacity: SplitHandle.hovered || SplitHandle.pressed ? 0.6 : 1
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 1; height: parent.height; color: Theme.border }
            }

            BinderPane {
                id: binder
                visible: ws.showBinder && !ws.focusMode
                SplitView.preferredWidth: 270
                SplitView.minimumWidth: 180
                currentId: ws.currentId
                onSelected: (id) => ws.select(id)
                onActivated: (id) => ws.select(id, "editor")
            }

            StackLayout {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 300
                currentIndex: ws.focusMode ? 0 : ["editor", "corkboard", "outliner", "timeline"].indexOf(ws.viewMode)

                EditorView {
                    id: editorView
                    nodeId: ws.currentId
                    node: ws.current
                    focusMode: ws.focusMode
                    onOpenRequested: (id) => ws.select(id, "editor")
                }
                CorkboardView {
                    nodeId: ws.currentId
                    node: ws.current
                    active: ws.viewMode === "corkboard"
                    onOpenRequested: (id) => ws.select(id, "editor")
                    onSelectRequested: (id) => ws.select(id, "corkboard")
                }
                OutlinerView {
                    nodeId: ws.currentId
                    node: ws.current
                    active: ws.viewMode === "outliner"
                    onOpenRequested: (id) => ws.select(id, "editor")
                }
                GanttView {
                    id: gantt
                    active: ws.viewMode === "timeline"
                    selectedNode: ws.currentId
                    onOpenScene: (id) => ws.select(id, "editor")
                }
            }

            InspectorPane {
                id: inspector
                visible: ws.showInspector && !ws.focusMode
                SplitView.preferredWidth: 300
                SplitView.minimumWidth: 220
                nodeId: ws.currentId
                node: ws.current
                onOpenEvent: () => ws.viewMode = "timeline"
                onFlushRequested: ws.flush()
            }
        }

        // ---------------- status bar ----------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            visible: !ws.focusMode
            color: Theme.panel
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 16
                Label {
                    color: Theme.subtext
                    text: ws.current ? qsTr("%1 words").arg(Api.fmtNumber(ws.current.total_words))
                        + (ws.current.target_words ? qsTr(" of %1").arg(Api.fmtNumber(ws.current.target_words)) : "")
                        : ""
                }
                ProgressBar {
                    visible: ws.current !== null && !!ws.current.target_words
                    from: 0; to: 1
                    value: ws.current && ws.current.target_words ? Math.min(1, ws.current.total_words / ws.current.target_words) : 0
                    Layout.preferredWidth: 100
                }
                Item { Layout.fillWidth: true }
                Label {
                    color: Theme.subtext
                    text: ws.stats ? qsTr("Manuscript: %1 words").arg(Api.fmtNumber(ws.stats.manuscript_words)) : ""
                }
                Label {
                    color: ws.stats && ws.stats.session_target && ws.stats.words_today >= ws.stats.session_target ? Theme.ok : Theme.subtext
                    text: ws.stats ? qsTr("Today: %1").arg(Api.fmtNumber(ws.stats.words_today))
                        + (ws.stats.session_target ? " / " + Api.fmtNumber(ws.stats.session_target) : "") : ""
                }
                Label {
                    color: Theme.subtext
                    text: Wordloom.dirty ? qsTr("Unsaved changes") : qsTr("All changes saved")
                }
            }
        }
    }

    // Leave focus mode with a floating button too.
    Button {
        visible: ws.focusMode
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        text: qsTr("Exit Focus (Esc)")
        flat: true
        opacity: hovered ? 1 : 0.35
        onClicked: ws.focusMode = false
    }
    Shortcut { sequence: "Escape"; enabled: ws.focusMode; onActivated: ws.focusMode = false }
}
