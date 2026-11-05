import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import com.wordloom.app

ApplicationWindow {
    id: win
    width: 1400
    height: 880
    minimumWidth: 900
    minimumHeight: 560

    // Window size is remembered between runs.
    Settings {
        category: "window"
        property alias width: win.width
        property alias height: win.height
    }
    visible: true
    color: Theme.window
    title: (Wordloom.projectOpen ? Wordloom.title + (Wordloom.dirty ? " •" : "") + " — " : "") + "Wordloom"

    palette.window: Theme.window
    palette.base: Theme.base
    palette.alternateBase: Theme.panel
    palette.text: Theme.text
    palette.windowText: Theme.text
    palette.buttonText: Theme.text
    palette.button: Theme.panel
    palette.highlight: Theme.accent
    palette.highlightedText: "white"
    palette.placeholderText: Theme.subtext
    palette.mid: Theme.border
    palette.dark: Theme.border
    palette.light: Theme.base
    palette.toolTipBase: Theme.base
    palette.toolTipText: Theme.text

    readonly property var ws: loader.item && Wordloom.projectOpen ? loader.item : null

    function newProject() { newDialog.open(); }
    function openProject() { openDialog.open(); }
    function openPath(path) {
        if (Wordloom.projectOpen) Api.call("close");
        Api.call("openProject", path);
    }
    function saveNow() {
        if (!Wordloom.projectOpen) return;
        if (ws) ws.flush();
        if (Api.call("save") !== undefined) Api.say("Saved");
    }
    function closeProject() {
        if (ws) ws.flush();
        Api.call("close");
    }

    // Command line: `wordloom [PROJECT] [--screenshots=DIR]`.
    Component.onCompleted: {
        const args = Qt.application.arguments.slice(1);
        for (const a of args) {
            if (a.startsWith("--screenshots=")) shotTour.dir = a.substring(14);
            else if (a.startsWith("--sample=")) Api.call("newDemoProject", a.substring(9));
            else if (!a.startsWith("-")) win.openPath(a);
        }
        if (shotTour.dir) shotTour.start();
    }

    // Developer aid: visit every view, save a PNG of each, then quit.
    Timer {
        id: shotTour
        property string dir: ""
        property int step: 0
        readonly property var views: ["editor", "corkboard", "outliner", "styled", "timeline", "lanes", "event", "search", "compile", "stats", "settings", "add", "undo", "split", "file", "compare", "relations", "relation", "focus", "start"]
        interval: 700
        repeat: true
        // Even ticks switch view, odd ticks capture it.
        onTriggered: {
            const v = views[Math.floor(step / 2)];
            if (step % 2 === 1) {
                const file = dir + "/" + Math.ceil(step / 2) + "-" + v + ".png";
                loader.grabToImage(r => r.saveToFile(file));
                // Popups render in the window overlay, which can't be grabbed;
                // capture the dialog's own content instead.
                const dlg = { event: win.ws ? win.ws.eventDialog() : null, compile: compileDialog, stats: statsDialog, settings: settingsDialog, compare: win.ws ? win.ws.compareDialogRef() : null, relation: win.ws ? win.ws.relationDialogRef() : null }[v];
                if (dlg && dlg.contentChildren.length) dlg.contentChildren[0].grabToImage(r => r.saveToFile(file.replace(".png", "-dialog.png")));
            } else if (v === undefined) {
                stop(); Qt.quit(); return;
            } else if (win.ws) {
                compileDialog.close(); statsDialog.close(); settingsDialog.close(); win.ws.closePopups();
                win.ws.searchFor(v === "search" ? "lighthouse" : "");
                win.ws.focusMode = v === "focus";
                if (v !== "split") win.ws.splitId = "";
                // The last research item: an imported file in the sample.
                const research = Api.get("children", [], Api.call("rootId", "research"));
                const fileItem = research.length ? research[research.length - 1].id : "";
                if (v === "event") win.ws.editAnEvent();
                else if (v === "compile") compileDialog.open();
                else if (v === "stats") statsDialog.open();
                else if (v === "settings") settingsDialog.open();
                else if (v === "add") { win.ws.viewMode = "editor"; win.ws.addInSection("characters"); }
                else if (v === "undo") { win.ws.cancelRename(); win.ws.undo(); }
                else if (v === "split") { win.ws.openFirstScene(); win.ws.openInSplit(fileItem); }
                else if (v === "file") win.ws.select(fileItem, "editor");
                else if (v === "compare") { win.ws.openFirstScene(); win.ws.compareSnapshot(""); }
                else if (v === "relations") {
                    const cast = Api.get("children", [], Api.call("rootId", "characters"));
                    if (cast.length) win.ws.select(cast[0].id, "relations"); else win.ws.viewMode = "relations";
                }
                else if (v === "relation") { win.ws.viewMode = "relations"; const m = Api.get("relations", null); if (m && m.links.length) win.ws.relationDialogRef().openEdit(m.links[0]); }
                if (v === "corkboard" || v === "outliner") win.ws.select(Api.call("rootId", "manuscript"), v);
                else if (v === "editor") { win.ws.viewMode = "editor"; }
                else if (v === "timeline") win.ws.showLanes(false);
                else if (v === "lanes") win.ws.showLanes(true, { place: true });
                else if (v === "styled") { const row = Api.get("binder", []).find(r => r.title === "Night Watch"); if (row) win.ws.select(row.id, "editor"); }
                else if (v === "start") win.closeProject();
            }
            step++;
        }
    }

    onClosing: (close) => {
        if (Wordloom.projectOpen) {
            if (ws) ws.flush();
            Api.call("save");
        }
    }

    // Autosave a couple of seconds after the user pauses, and periodically.
    Timer {
        interval: 15000
        repeat: true
        running: Wordloom.projectOpen
        onTriggered: if (Wordloom.dirty) { if (win.ws) win.ws.flush(); Api.call("save"); }
    }

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            // Ctrl+N means New Document once a project is open; two actions on one
            // key would make Qt treat it as ambiguous and fire neither.
            Action { text: qsTr("&New Project…"); shortcut: win.ws === null ? StandardKey.New : ""; onTriggered: win.newProject() }
            Action { text: qsTr("&Open Project…"); shortcut: StandardKey.Open; onTriggered: win.openProject() }
            Menu {
                id: recentMenu
                title: qsTr("Open &Recent")
                property var items: []
                onAboutToShow: items = Api.call("recent") || []
                Instantiator {
                    model: recentMenu.items
                    delegate: MenuItem {
                        required property var modelData
                        text: modelData.title + "  —  " + modelData.path
                        onTriggered: win.openPath(modelData.path)
                    }
                    onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => recentMenu.removeItem(object)
                }
            }
            MenuSeparator {}
            Action { text: qsTr("&Save"); shortcut: StandardKey.Save; enabled: Wordloom.projectOpen; onTriggered: win.saveNow() }
            Action { text: qsTr("Save &As…"); enabled: Wordloom.projectOpen; onTriggered: saveAsDialog.open() }
            Action { text: qsTr("&Import File…"); shortcut: "Ctrl+Shift+I"; enabled: win.ws !== null; onTriggered: importDialog.open() }
            Action { text: qsTr("Clean Up &Unused Files…"); enabled: win.ws !== null; onTriggered: cleanupDialog.check() }
            Action { text: qsTr("Take &Snapshot"); shortcut: "Ctrl+5"; enabled: win.ws !== null; onTriggered: win.ws.snapshot() }
            MenuSeparator {}
            Action { text: qsTr("&Compile / Export…"); shortcut: "Ctrl+Shift+E"; enabled: Wordloom.projectOpen; onTriggered: compileDialog.open() }
            Action { text: qsTr("Project Se&ttings…"); enabled: Wordloom.projectOpen; onTriggered: settingsDialog.open() }
            MenuSeparator {}
            Action { text: qsTr("&Close Project"); enabled: Wordloom.projectOpen; onTriggered: win.closeProject() }
            Action { text: qsTr("&Quit"); shortcut: StandardKey.Quit; onTriggered: win.close() }
        }
        Menu {
            title: qsTr("&Edit")
            // In a text box Ctrl+Z undoes typing; these undo project changes.
            Action {
                text: Wordloom.undoText ? qsTr("&Undo %1").arg(Wordloom.undoText) : qsTr("&Undo")
                shortcut: StandardKey.Undo
                enabled: win.ws !== null && Wordloom.undoText !== ""
                onTriggered: win.ws.undo()
            }
            Action {
                text: Wordloom.redoText ? qsTr("&Redo %1").arg(Wordloom.redoText) : qsTr("&Redo")
                shortcut: StandardKey.Redo
                enabled: win.ws !== null && Wordloom.redoText !== ""
                onTriggered: win.ws.redo()
            }
            MenuSeparator {}
            Action { text: qsTr("&Find in Document…"); shortcut: StandardKey.Find; enabled: win.ws !== null; onTriggered: win.ws.findInDocument(false) }
            Action { text: qsTr("&Replace in Document…"); shortcut: StandardKey.Replace; enabled: win.ws !== null; onTriggered: win.ws.findInDocument(true) }
        }
        Menu {
            title: qsTr("&Project")
            enabled: win.ws !== null
            Action { text: qsTr("New &Document"); shortcut: "Ctrl+N"; onTriggered: win.ws.addItem("text") }
            Action { text: qsTr("New &Folder"); shortcut: "Ctrl+Shift+N"; onTriggered: win.ws.addItem("folder") }
            Action { text: qsTr("New &Character"); onTriggered: win.ws.addInSection("characters") }
            Action { text: qsTr("New &Place"); onTriggered: win.ws.addInSection("places") }
            MenuSeparator {}
            Action { text: qsTr("D&uplicate"); shortcut: "Ctrl+D"; onTriggered: win.ws.duplicate() }
            Action { text: qsTr("Split at Cursor"); shortcut: "Ctrl+K"; onTriggered: win.ws.splitAtCursor() }
            Action { text: qsTr("Merge with Next"); shortcut: "Ctrl+Shift+M"; onTriggered: win.ws.mergeNext() }
            Action { text: qsTr("Move to &Trash"); onTriggered: win.ws.trashCurrent() }
            Action { text: qsTr("&Empty Trash"); onTriggered: win.ws.emptyTrash() }
            MenuSeparator {}
            Action { text: qsTr("&Find in Project"); shortcut: "Ctrl+Shift+F"; onTriggered: win.ws.focusSearch() }
            Action { text: qsTr("Writing &Statistics…"); shortcut: "Ctrl+Shift+T"; onTriggered: statsDialog.open() }
        }
        Menu {
            title: qsTr("&View")
            enabled: win.ws !== null
            Action { text: qsTr("&Editor"); shortcut: "Ctrl+1"; onTriggered: win.ws.viewMode = "editor" }
            Action { text: qsTr("&Corkboard"); shortcut: "Ctrl+2"; onTriggered: win.ws.viewMode = "corkboard" }
            Action { text: qsTr("&Outliner"); shortcut: "Ctrl+3"; onTriggered: win.ws.viewMode = "outliner" }
            Action { text: qsTr("&Timeline (Gantt)"); shortcut: "Ctrl+4"; onTriggered: win.ws.viewMode = "timeline" }
            Action { text: qsTr("&Relationship Map"); shortcut: "Ctrl+6"; onTriggered: win.ws.viewMode = "relations" }
            MenuSeparator {}
            Action { text: qsTr("&Split Editor"); shortcut: "Ctrl+\\"; checkable: true; checked: win.ws ? win.ws.splitId !== "" : false; onTriggered: win.ws.toggleSplit() }
            Action { text: qsTr("&Focus Mode"); shortcut: "F11"; checkable: true; checked: win.ws ? win.ws.focusMode : false; onTriggered: win.ws.focusMode = !win.ws.focusMode }
            Action { text: qsTr("Show &Binder"); checkable: true; checked: win.ws ? win.ws.showBinder : true; onTriggered: win.ws.showBinder = !win.ws.showBinder }
            Action { text: qsTr("Show &Details"); shortcut: "Ctrl+Alt+I"; checkable: true; checked: win.ws ? win.ws.showInspector : true; onTriggered: win.ws.showInspector = !win.ws.showInspector }
            MenuSeparator {}
            Action { text: qsTr("Styled &Markdown"); checkable: true; checked: Theme.styledMarkdown; onTriggered: Theme.styledMarkdown = !Theme.styledMarkdown }
            Action { text: qsTr("Larger Text"); shortcut: StandardKey.ZoomIn; onTriggered: Theme.editorSize = Math.min(40, Theme.editorSize + 1) }
            Action { text: qsTr("Smaller Text"); shortcut: StandardKey.ZoomOut; onTriggered: Theme.editorSize = Math.max(9, Theme.editorSize - 1) }
            Menu {
                title: qsTr("Appearance")
                Action { text: qsTr("Follow System"); checkable: true; checked: Theme.forced === ""; onTriggered: Theme.forced = "" }
                Action { text: qsTr("Light"); checkable: true; checked: Theme.forced === "light"; onTriggered: Theme.forced = "light" }
                Action { text: qsTr("Dark"); checkable: true; checked: Theme.forced === "dark"; onTriggered: Theme.forced = "dark" }
            }
        }
        Menu {
            title: qsTr("&Help")
            Action { text: qsTr("&About Wordloom"); onTriggered: aboutDialog.open() }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: Wordloom.projectOpen ? workspaceComp : startComp
    }
    Component {
        id: startComp
        StartPage {
            onNewRequested: win.newProject()
            onOpenRequested: win.openProject()
            onRecentChosen: (path) => win.openPath(path)
        }
    }
    Component {
        id: workspaceComp
        Workspace { onStatsRequested: statsDialog.open() }
    }

    // ---- toast / error banner ----
    Rectangle {
        id: toast
        property bool error: false
        property alias text: toastLabel.text
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: Math.min(parent.width - 40, toastLabel.implicitWidth + 32)
        height: toastLabel.implicitHeight + 16
        radius: height / 2
        color: error ? Theme.danger : (Theme.dark ? "#444" : "#333")
        opacity: 0
        visible: opacity > 0
        z: 100
        Label { id: toastLabel; anchors.centerIn: parent; color: "white"; width: Math.min(implicitWidth, toast.width - 24); wrapMode: Text.Wrap }
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Timer { id: toastTimer; interval: 3500; onTriggered: toast.opacity = 0 }
        function show(msg, isError) { text = msg; error = isError; opacity = 0.95; toastTimer.restart(); }
    }
    Connections {
        target: Api
        function onFailed(method, message) { toast.show(message, true); }
        function onNotice(message) { toast.show(message, false); }
    }

    // ---- dialogs ----
    Dialog {
        id: newDialog
        title: qsTr("New Project")
        modal: true
        anchors.centerIn: parent
        width: 460
        standardButtons: Dialog.Ok | Dialog.Cancel
        property url folder: ""
        onAboutToShow: { newTitle.text = ""; newAuthor.text = ""; newTitle.forceActiveFocus(); }
        GridLayout {
            anchors.fill: parent
            columns: 2
            Label { text: qsTr("Title") }
            TextField { id: newTitle; Layout.fillWidth: true; placeholderText: qsTr("My Novel") }
            Label { text: qsTr("Author") }
            TextField { id: newAuthor; Layout.fillWidth: true }
            Label { text: qsTr("Location") }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: newDialog.folder.toString() === "" ? qsTr("(choose a folder)") : decodeURIComponent(newDialog.folder.toString().replace(/^file:\/\//, ""))
                    color: Theme.subtext
                }
                Button { text: qsTr("Browse…"); onClicked: newFolderDialog.open() }
            }
        }
        onAccepted: {
            if (folder.toString() === "") { Api.say(qsTr("Choose where to create the project.")); return; }
            const t = newTitle.text.trim() || "Untitled";
            Api.call("newProject", folder.toString(), t, newAuthor.text);
        }
    }
    FolderDialog {
        id: newFolderDialog
        title: qsTr("Create the project in…")
        onAccepted: newDialog.folder = selectedFolder
    }
    FolderDialog {
        id: openDialog
        title: qsTr("Open a .wordloom project folder")
        onAccepted: win.openPath(selectedFolder.toString())
    }
    Dialog {
        id: saveAsDialog
        title: qsTr("Save Project As")
        modal: true
        anchors.centerIn: parent
        width: 440
        standardButtons: Dialog.Ok | Dialog.Cancel
        property url folder: ""
        onAboutToShow: saveAsTitle.text = Wordloom.title
        ColumnLayout {
            anchors.fill: parent
            TextField { id: saveAsTitle; Layout.fillWidth: true; placeholderText: qsTr("New title") }
            Button { text: saveAsDialog.folder.toString() === "" ? qsTr("Choose folder…") : decodeURIComponent(saveAsDialog.folder.toString().replace(/^file:\/\//, "")); onClicked: saveAsFolder.open() }
        }
        onAccepted: {
            if (win.ws) win.ws.flush();
            if (folder.toString() !== "" && Api.call("saveAs", folder.toString(), saveAsTitle.text) !== undefined)
                Api.say(qsTr("Saved a copy and switched to it"));
        }
    }
    FolderDialog { id: saveAsFolder; onAccepted: saveAsDialog.folder = selectedFolder }

    CompileDialog { id: compileDialog; anchors.centerIn: parent }

    // Delete imported files that no item (trash and undo history included)
    // refers to any more.
    Dialog {
        id: cleanupDialog
        title: qsTr("Clean Up Unused Files")
        modal: true
        anchors.centerIn: parent
        width: 440
        property var found: ({ count: 0, bytes: 0 })
        function size(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB"; }
        function check() {
            const r = Api.call("unusedFiles");
            if (r === undefined) return;
            if (r.count === 0) { Api.say(qsTr("No unused files: every imported file is still in use")); return; }
            found = r;
            open();
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: qsTr("%1 imported file(s), %2 in total, are no longer used by any item, including items in the Trash and anything Undo could bring back.\n\nDelete them from the project's files folder? Older copies of project.json in backups/ may still mention them.")
                .arg(cleanupDialog.found.count).arg(cleanupDialog.size(cleanupDialog.found.bytes))
        }
        footer: DialogButtonBox {
            Button { text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: qsTr("Delete Files"); highlighted: true; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }
        onAccepted: {
            const r = Api.call("removeUnusedFiles");
            if (r !== undefined) Api.say(qsTr("Deleted %1 unused file(s), %2").arg(r.count).arg(size(r.bytes)));
        }
    }
    FileDialog {
        id: importDialog
        title: qsTr("Import into Research")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images and PDFs (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.pdf)"), qsTr("All files (*)")]
        onAccepted: if (win.ws) win.ws.importFiles(selectedFiles)
    }
    StatsDialog { id: statsDialog; anchors.centerIn: parent }
    ProjectSettingsDialog { id: settingsDialog; anchors.centerIn: parent }

    Dialog {
        id: aboutDialog
        title: qsTr("About Wordloom")
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        Label {
            text: "<h2>Wordloom</h2><p>A writing studio for long-form work:<br/>binder, corkboard, outliner, split editor,<br/>research files, snapshots, project-wide undo,<br/>compile to EPUB / DOCX / HTML / Markdown,<br/>and a story timeline Gantt.</p><p>Built with Rust and Qt " + "6</p>"
            textFormat: Text.RichText
        }
    }
}
