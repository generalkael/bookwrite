import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtCore
import com.wordloom.app

// The main three-pane layout: binder | view | Details panel, plus toolbar and
// status bar. Owns the current selection and view mode, and the optional
// split editor: a second editor beside the main view that keeps showing one
// document while the binder drives the main view.
Item {
    id: ws

    property string currentId: ""
    property var current: null          // nodeInfo of currentId
    property string viewMode: "editor"  // editor | corkboard | outliner | timeline | relations | reader
    property bool focusMode: false
    property bool showBinder: true
    property bool showInspector: true
    property var stats: null
    property string splitId: ""         // document in the split editor; "" = no split
    property var splitNode: null
    signal historyRequested()
    property var sprint: null           // SprintDialog (from Main)

    // Today's words against the daily goal (0..1, or -1 without a goal).
    readonly property real goalProgress: stats && stats.session_target ? Math.min(1, Math.max(0, stats.words_today) / stats.session_target) : -1
    property bool goalCelebrated: false
    property bool goalPrimed: false
    onGoalProgressChanged: {
        // The first value comes from opening the project: no fanfare for a
        // goal that was already met.
        if (!goalPrimed) { goalPrimed = true; goalCelebrated = goalProgress >= 1; return; }
        if (goalProgress >= 1 && !goalCelebrated) {
            goalCelebrated = true;
            Api.say(qsTr("Daily goal reached: %1 words today").arg(Api.fmtNumber(stats.words_today)));
        } else if (goalProgress >= 0 && goalProgress < 1) {
            goalCelebrated = false;
        }
    }

    readonly property int rev: Wordloom.revision
    onRevChanged: refresh()
    onCurrentIdChanged: refresh()
    onSplitIdChanged: refresh()

    function refresh() {
        // The selected item can vanish (undo, empty trash); drop it quietly.
        if (currentId !== "" && !Api.get("exists", false, currentId)) { currentId = ""; return; }
        current = currentId !== "" ? (Api.get("nodeInfo", null, currentId)) : null;
        if (splitId !== "" && !Api.get("exists", false, splitId)) splitId = "";
        splitNode = splitId !== "" ? Api.get("nodeInfo", null, splitId) : null;
        stats = Api.get("stats", null);
    }

    // Select an item, in `mode` if given. Otherwise documents open in the
    // editor (a character picked on the relationship map stays there), and a
    // folder with no text of its own opens as a corkboard of its contents.
    function select(id, mode) {
        flush();
        currentId = id;
        if (mode) { viewMode = mode; return; }
        if (!current || viewMode === "reader") return;   // keep reading; the reader follows the selection
        const isGroup = current.is_root || current.kind === "folder";
        if (!isGroup) {
            if (!(viewMode === "relations" && current.kind === "character")) viewMode = "editor";
        } else if (viewMode === "timeline") {
            viewMode = "editor";
        } else if (viewMode === "editor" && current.child_count > 0 && current.words === 0) {
            viewMode = "corkboard";
        }
    }

    function flush() {
        if (editorView) editorView.flush();
        if (splitEditor) splitEditor.flush();
    }

    // Split editor. Opening it shows the current document on the right, so
    // it stays in view while you pick something else in the binder.
    function toggleSplit() {
        flush();
        splitId = splitId !== "" ? "" : (currentId !== "" ? currentId : "");
        if (splitId === "") Api.say(qsTr("Select a document to split the editor"));
    }
    function openInSplit(id) { flush(); splitId = id; }
    function swapSplit() {
        if (splitId === "") return;
        flush();
        const other = currentId;
        select(splitId, "editor");
        splitId = other !== "" ? other : splitId;
    }

    // Import files (images, PDFs, …) as research items. Into the selected
    // folder if it is in Research, otherwise into the Research section.
    function importFiles(urls) {
        flush();
        const inResearch = current && current.section === "research" && (current.is_root || current.kind === "folder");
        let last = "";
        for (const u of urls) {
            const id = Api.call("importFile", inResearch ? currentId : "", u.toString());
            if (id) last = id;
        }
        if (last) select(last, "editor");
    }

    // Close an in-progress binder rename without committing it.
    function cancelRename() { binder.renamingId = ""; }

    // Project-wide undo/redo (typing has the editor's own undo).
    function undo() {
        flush();
        const label = Api.call("undo");
        if (label) Api.say(qsTr("Undid %1").arg(label));
    }
    function redo() {
        flush();
        const label = Api.call("redo");
        if (label) Api.say(qsTr("Redid %1").arg(label));
    }

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
    // Find (and replace) in the open document: the split editor if you are
    // typing there, otherwise the main editor.
    function mainEditor() { return editorView; }
    function findInDocument(withReplace) {
        const inSplit = splitId !== "" && splitEditor.activeArea && splitEditor.activeArea.activeFocus;
        if (!inSplit && viewMode !== "editor") viewMode = "editor";
        (inSplit ? splitEditor : editorView).openFind(withReplace);
    }
    function eventDialog() { return gantt.eventDialogRef; }
    function closePopups() { gantt.closeDialogs(); compareDialog.close(); relationsView.dialogRef.close(); }
    function relationDialogRef() { return relationsView.dialogRef; }
    // Compare a snapshot of the current document with its text now (the
    // first snapshot if `snapId` is empty).
    function compareSnapshot(snapId) {
        if (!currentId) return;
        flush();
        compareDialog.openFor(currentId, snapId);
    }
    function compareDialogRef() { return compareDialog; }
    function editAnEvent() { viewMode = "timeline"; gantt.editFirstEvent(); }
    function showLanes(on, collapsed) { viewMode = "timeline"; gantt.lanes = on; gantt.collapsed = collapsed || ({}); }
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

    function openFirstScene() {
        const ms = Api.call("rootId", "manuscript");
        let kids = Api.get("children", [], ms);
        while (kids.length && kids[0].kind === "folder" && kids[0].child_count > 0) kids = Api.get("children", [], kids[0].id);
        if (kids.length) select(kids[0].id, "editor");
    }
    Component.onCompleted: openFirstScene()

    // Panel visibility is remembered between runs.
    Settings {
        category: "layout"
        property alias showBinder: ws.showBinder
        property alias showDetails: ws.showInspector
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
                ToolButton { text: "+ " + qsTr("Document"); onClicked: ws.addItem("text"); ToolTip.visible: hovered; ToolTip.text: qsTr("New document (Ctrl+N)") }
                ToolButton { text: "+ " + qsTr("Folder"); onClicked: ws.addItem("folder") }
                ToolSeparator {}
                ToolButton {
                    text: "↶"; font.pixelSize: 18; enabled: Wordloom.undoText !== ""; onClicked: ws.undo()
                    ToolTip.visible: hovered; ToolTip.text: enabled ? qsTr("Undo %1").arg(Wordloom.undoText) : qsTr("Nothing to undo")
                }
                ToolButton {
                    text: "↷"; font.pixelSize: 18; enabled: Wordloom.redoText !== ""; onClicked: ws.redo()
                    ToolTip.visible: hovered; ToolTip.text: enabled ? qsTr("Redo %1").arg(Wordloom.redoText) : qsTr("Nothing to redo")
                }
                ToolSeparator {}
                Repeater {
                    model: [
                        { mode: "editor", label: qsTr("✎ Editor") },
                        { mode: "corkboard", label: qsTr("▦ Corkboard") },
                        { mode: "outliner", label: qsTr("☰ Outliner") },
                        { mode: "timeline", label: qsTr("▤ Timeline") },
                        { mode: "relations", label: qsTr("◇ Relations") },
                        { mode: "reader", label: qsTr("❦ Read") }
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
                ToolButton { text: qsTr("Snapshot"); enabled: ws.currentId !== ""; onClicked: ws.snapshot() }
                ToolButton {
                    text: qsTr("◫ Split"); checkable: true; checked: ws.splitId !== ""; onClicked: ws.toggleSplit()
                    ToolTip.visible: hovered; ToolTip.text: qsTr("Keep this document open beside the main view (Ctrl+\\)")
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: ws.current !== null
                    text: ws.current ? ws.current.breadcrumbs.concat([ws.current.title]).join("  ›  ") : ""
                    color: Theme.subtext
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 420
                }
                ToolSeparator {}
                ToolButton { text: ws.showInspector ? qsTr("Hide Details") : qsTr("Show Details"); onClicked: ws.showInspector = !ws.showInspector }
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
                onOpenInSplit: (id) => ws.openInSplit(id)
                onFilesDropped: (urls) => ws.importFiles(urls)
            }

            SplitView {
                id: centre
                SplitView.fillWidth: true
                SplitView.minimumWidth: 300
                orientation: Qt.Horizontal
                handle: Rectangle {
                    implicitWidth: 5
                    color: SplitHandle.hovered || SplitHandle.pressed ? Theme.accent : Theme.border
                    opacity: SplitHandle.hovered || SplitHandle.pressed ? 0.6 : 1
                }

                StackLayout {
                    SplitView.fillWidth: true
                    // Small enough that two editors fit side by side in a narrow window.
                    SplitView.minimumWidth: 180
                    currentIndex: ws.focusMode ? 0 : ["editor", "corkboard", "outliner", "timeline", "relations", "reader"].indexOf(ws.viewMode)

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
                    RelationsView {
                        id: relationsView
                        active: ws.viewMode === "relations"
                        selectedNode: ws.currentId
                        onOpenRequested: (id) => ws.select(id, "editor")
                        onSelectRequested: (id) => ws.select(id, "relations")
                    }
                    // Order matches the viewMode list above.
                    ReaderView {
                        active: ws.viewMode === "reader"
                        node: ws.current
                        onEditRequested: ws.viewMode = "editor"
                    }
                }

                EditorView {
                    id: splitEditor
                    visible: ws.splitId !== "" && !ws.focusMode
                    // Opens at half the space; drag the handle to change it.
                    SplitView.preferredWidth: centre.width / 2
                    SplitView.minimumWidth: 180
                    secondary: true
                    nodeId: ws.splitId
                    node: ws.splitNode
                    onOpenRequested: (id) => ws.openInSplit(id)
                    onSwapRequested: ws.swapSplit()
                    onCloseRequested: { splitEditor.flush(); ws.splitId = ""; }
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
                onCompareRequested: (snapId) => ws.compareSnapshot(snapId)
                onOpenRelations: ws.viewMode = "relations"
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
                // Running sprint: countdown and words so far; click to open.
                Label {
                    visible: ws.sprint !== null && ws.sprint.running
                    text: ws.sprint ? "⏱ " + ws.sprint.clock + (ws.sprint.paused ? " " + qsTr("(paused)") : "") + "  ·  " + qsTr("%1 words").arg(Api.fmtNumber(ws.sprint.words)) : ""
                    color: Theme.accent
                    font.bold: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ws.sprint.open() }
                }
                // Daily goal ring: fills as you write today; click for the history.
                Item {
                    id: goalRing
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    readonly property real p: ws.goalProgress
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Theme.border; strokeWidth: 3; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 8; centerY: 8; radiusX: 6; radiusY: 6; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: goalRing.p >= 1 ? Theme.ok : Theme.accent; strokeWidth: 3; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 8; centerY: 8; radiusX: 6; radiusY: 6; startAngle: -90; sweepAngle: Math.max(0, goalRing.p) * 360 }
                        }
                    }
                    HoverHandler { id: ringHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ws.historyRequested() }
                    ToolTip.visible: ringHover.hovered
                    ToolTip.text: (ws.goalProgress < 0 ? qsTr("No daily goal set")
                        : qsTr("%1% of today's goal").arg(Math.round(ws.goalProgress * 100))) + "\n" + qsTr("Click for your word count history")
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

    CompareDialog {
        id: compareDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }
}
