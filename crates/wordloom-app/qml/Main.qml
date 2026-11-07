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
    Settings {
        category: "bible"
        property alias folder: bibleDialog.lastFolder
    }
    Settings {
        category: "backup"
        property alias folder: backupDialog.lastFolder
        property alias autoOnClose: autoBackupDialog.closeBackups
        property alias autoFolder: autoBackupDialog.folder
        property alias autoKeep: autoBackupDialog.keep
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
        if (Wordloom.projectOpen) { autoBackupDialog.beforeClose(); Api.call("close"); }
        if (Api.call("openProject", path) !== undefined) return;
        if (Api.lastErrorKind === "damaged") restoreDialog.offer(path);
        else if (Api.lastErrorKind === "locked") lockedDialog.offer(path);
    }
    function saveNow() {
        if (!Wordloom.projectOpen) return;
        if (ws) ws.flush();
        if (Api.call("save") !== undefined) Api.say("Saved");
    }
    // View ▸ Spelling Language: switch dictionaries ("" = the system's) and
    // redraw the underlines.
    function setSpellLanguage(code) {
        Theme.spellLanguage = code;
        const r = Api.call("spellSetLanguage", code);
        Api.spellingChanged();
        if (r) Api.say(qsTr("Spelling: %1").arg(r.dictionary));
        return r;
    }
    function closeProject() {
        if (ws) ws.flush();
        autoBackupDialog.beforeClose();
        Api.call("close");
    }

    // Command line: `wordloom [PROJECT] [--sample=DIR] [--screenshots=DIR [--dark]] [--selftest] [--bench=DIR]`.
    Component.onCompleted: {
        if (Theme.spellLanguage) Api.call("spellSetLanguage", Theme.spellLanguage);
        const args = Qt.application.arguments.slice(1);
        for (const a of args) {
            if (a.startsWith("--screenshots=")) shotTour.dir = a.substring(14);
            else if (a === "--dark") shotTour.dark = true;
            else if (a.startsWith("--bench=")) { Api.call("newLargeProject", a.substring(8)); Qt.callLater(() => bench.start()); }
            else if (a === "--selftest") selfTest.pending = true;
            else if (a.startsWith("--sample=")) Api.call("newDemoProject", a.substring(9));
            else if (!a.startsWith("-")) win.openPath(a);
        }
        // --dark only applies to the tour (whose settings are kept apart).
        if (shotTour.dir) { Theme.forced = shotTour.dark ? "dark" : ""; shotTour.start(); }
        if (selfTest.pending) Qt.callLater(selfTest.start);
    }

    // Developer aid: `wordloom --bench=DIR` builds a novel-sized project in
    // DIR (demo::create_large: 40 chapters, 200 scenes, ~168,000 words),
    // times each view, prints "BENCH <step>: <ms>" lines and quits. Each
    // time includes the 50 ms between steps, so the views have laid out.
    Timer {
        id: bench
        property int step: -1
        property double t0: 0
        interval: 50
        repeat: true
        function row(title) { return (Api.get("binder", []).find(r => r.title === title) || {}).id || ""; }
        readonly property var steps: [
            ["editor: one scene", () => win.ws.select(row("Scene 1.3"), "editor")],
            ["corkboard: manuscript", () => win.ws.select(Api.call("rootId", "manuscript"), "corkboard")],
            ["outliner: manuscript", () => win.ws.select(Api.call("rootId", "manuscript"), "outliner")],
            ["outliner: filter", () => { win.ws.outlinerRef().filterText = "scene 4"; }],
            ["outliner: clear filter", () => { win.ws.outlinerRef().clearFilter(); }],
            ["reader: manuscript", () => win.ws.select(Api.call("rootId", "manuscript"), "reader")],
            ["editor: one chapter (5 scenes)", () => win.ws.select(row("Chapter 5"), "editor")],
            ["editor: whole manuscript (first parts)", () => win.ws.select(Api.call("rootId", "manuscript"), "editor")],
            ["editor: whole manuscript (the rest, at once)", () => win.ws.mainEditor().ensureBuilt()],
            ["editor: repeated words on", () => { Theme.highlightRepeats = true; }],
            ["editor: type a character", () => { const a = win.ws.mainEditor().firstArea(); a.forceActiveFocus(); a.insert(0, "x"); }],
            ["editor: back to one scene", () => { Theme.highlightRepeats = false; win.ws.select(row("Scene 1.2"), "editor"); }],
            ["text analysis", () => analysisDialog.open()],
            ["statistics", () => { analysisDialog.close(); statsDialog.open(); }],
            ["search", () => { statsDialog.close(); win.ws.searchFor("lamp"); }],
        ]
        onTriggered: {
            const now = Date.now();
            if (step >= 0) Api.call("log", "BENCH " + steps[step][0] + ": " + (now - t0) + " ms");
            step++;
            if (step >= steps.length) { stop(); Qt.quit(); return; }
            t0 = Date.now();
            steps[step][1]();
        }
    }
    SelfTest { id: selfTest; property bool pending: false; win: win; history: historyWindow; sprint: sprintDialog; analysis: analysisDialog; compile: compileDialog; goTo: goTo; autoBackup: autoBackupDialog; grid: presenceDialog }

    // Developer aid: visit every view, save a PNG of each, then quit.
    Timer {
        id: shotTour
        property string dir: ""
        property bool dark: false
        property int step: 0
        readonly property var views: ["editor", "multiselect", "corkboard", "carddrag", "outliner", "styled", "complete", "linebar", "repeats", "footnote", "timeline", "lanes", "event", "search", "goto", "compile", "pdf", "stats", "settings", "add", "undo", "split", "file", "compare", "relations", "relation", "names", "history", "sprint", "analysis", "grid", "autobackup", "newproject", "reader", "focus", "start"]
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
                const dlg = { event: win.ws ? win.ws.eventDialog() : null, compile: compileDialog, pdf: compileDialog, goto: goTo, stats: statsDialog, settings: settingsDialog, compare: win.ws ? win.ws.compareDialogRef() : null, relation: win.ws ? win.ws.relationDialogRef() : null, names: nameDialog, sprint: sprintDialog, analysis: analysisDialog, grid: presenceDialog, autobackup: autoBackupDialog, newproject: newDialog }[v];
                if (dlg && dlg.contentChildren.length) dlg.contentChildren[0].grabToImage(r => r.saveToFile(file.replace(".png", "-dialog.png")));
                if (v === "history") historyWindow.contentItem.grabToImage(r => r.saveToFile(file.replace(".png", "-window.png")));
            } else if (v === undefined) {
                stop(); Qt.quit(); return;
            } else if (win.ws) {
                compileDialog.close(); statsDialog.close(); settingsDialog.close(); nameDialog.close(); historyWindow.close(); sprintDialog.close(); analysisDialog.close(); presenceDialog.close(); autoBackupDialog.close(); newDialog.close(); goTo.close(); win.ws.closePopups();
                win.ws.searchFor(v === "search" ? "lighthouse" : "");
                { const c = win.ws.corkboardRef(); c.dragId = ""; c.dropIndex = -1; c.dropMode = ""; }
                win.ws.focusMode = v === "focus";
                Theme.lineHighlight = v === "linebar";
                Theme.highlightRepeats = v === "repeats";
                if (v !== "split") win.ws.splitId = "";
                win.ws.binderRef().clearPicks();
                // The last research item: an imported file in the sample.
                const research = Api.get("children", [], Api.call("rootId", "research"));
                const fileItem = research.length ? research[research.length - 1].id : "";
                if (v === "event") win.ws.editAnEvent();
                else if (v === "compile") { compileDialog.open(); compileDialog.selectFormat("markdown", 0); }
                else if (v === "goto") { goTo.start(); goTo.search("wa"); }
                else if (v === "pdf") { compileDialog.open(); compileDialog.selectFormat("pdf", 1); }
                else if (v === "names") nameDialog.open();
                else if (v === "history") historyWindow.show(3);
                else if (v === "sprint") sprintDialog.open();
                else if (v === "analysis") analysisDialog.open();
                else if (v === "grid") presenceDialog.open();
                else if (v === "autobackup") autoBackupDialog.open();
                else if (v === "newproject") { newDialog.open(); newTemplate.currentIndex = 1; }
                else if (v === "reader") win.ws.viewMode = "reader";
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
                if (v === "corkboard") Qt.callLater(() => { const c = win.ws.corkboardRef(); c.focusBoard(); c.highlight(1); });
                if (v === "outliner") Qt.callLater(() => {
                    const o = win.ws.outlinerRef(), log = o.rows.find(x => x.title === "The Log");
                    if (!o.hasColumn("keywords")) o.toggleColumn("keywords");
                    if (log && !o.collapsed[log.id]) o.toggle(log.id);
                    o.filterStatus = (o.meta.statuses.find(x => x.name === "To Do") || { id: "" }).id;
                });
                else if (v === "editor") { win.ws.viewMode = "editor"; }
                else if (v === "timeline") win.ws.showLanes(false);
                else if (v === "lanes") win.ws.showLanes(true, { place: true });
                else if (v === "complete") {
                    const row = Api.get("binder", []).find(r => r.title === "Night Watch");
                    if (row) win.ws.select(row.id, "editor");
                    Qt.callLater(() => { const a = win.ws.mainEditor().firstArea(); if (a) { a.forceActiveFocus(); a.cursorPosition = a.length; a.insert(a.length, "\n\nShe thought of Tob"); } });
                }
                else if (v === "linebar") {
                    const row = Api.get("binder", []).find(r => r.title === "Arrival");
                    if (row) win.ws.select(row.id, "editor");
                    Qt.callLater(() => { const a = win.ws.mainEditor().firstArea(); if (a) { a.forceActiveFocus(); a.cursorPosition = a.text.indexOf("lighthouse turned"); } });
                }
                else if (v === "multiselect") {
                    const rows = Api.get("binder", []), id = (t) => rows.find(r => r.title === t).id;
                    win.ws.select(id("Arrival"), "editor");
                    Qt.callLater(() => { const b = win.ws.binderRef(); b.togglePick(id("The Keeper")); b.togglePick(id("Night Watch")); });
                }
                else if (v === "carddrag") {
                    win.ws.select(Api.get("binder", []).find(r => r.title === "The Storm").id, "corkboard");
                    Qt.callLater(() => { const c = win.ws.corkboardRef(); const k = c.cards.find(x => x.title === "The Keeper"); if (k) { c.startDrag(k.id, k.title); c.updateDrag(c.cardPoint(0, 0.25)); } });
                }
                else if (v === "footnote") {
                    const row = Api.get("binder", []).find(r => r.title === "Arrival");
                    if (row) win.ws.select(row.id, "editor");
                    Qt.callLater(() => {
                        const a = win.ws.mainEditor().firstArea();
                        if (!a) return;
                        a.forceActiveFocus(); win.ws.mainEditor().activeArea = a;
                        a.cursorPosition = a.text.indexOf("soft.") + 5;
                        win.ws.insertFootnote();
                        a.insert(a.length, "Her father's last letter, posted from the mainland in *October*.");
                    });
                }
                else if (v === "repeats") {
                    const row = Api.get("binder", []).find(r => r.title === "Arrival");
                    if (row) win.ws.select(row.id, "editor");
                    Qt.callLater(() => { const a = win.ws.mainEditor().firstArea(); if (a) { a.forceActiveFocus(); a.insert(a.length, "\n\nShe climbed toward the lamp room, and the lamp room smelled of oil, and the stairs climbed on."); } });
                }
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
            autoBackupDialog.beforeClose();
        }
    }

    // Refresh the "project is open" lock, so other Wordlooms (another
    // computer, or another Flatpak instance) can tell it's still in use.
    Timer {
        interval: 120000
        repeat: true
        running: Wordloom.projectOpen
        onTriggered: Api.call("touchLock")
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
            Action { text: qsTr("&Back Up to Zip…"); enabled: Wordloom.projectOpen; onTriggered: backupDialog.start() }
            Action { text: qsTr("Automatic Bac&kups…"); onTriggered: autoBackupDialog.open() }
            Action { text: qsTr("Restore from &Zip Backup…"); onTriggered: restoreZipDialog.start() }
            Action { text: qsTr("Import &Manuscript…"); enabled: win.ws !== null; onTriggered: manuscriptDialog.open() }
            Action { text: qsTr("&Import File…"); shortcut: "Ctrl+Shift+I"; enabled: win.ws !== null; onTriggered: importDialog.open() }
            Action { text: qsTr("Clean Up &Unused Files…"); enabled: win.ws !== null; onTriggered: cleanupDialog.check() }
            Action { text: qsTr("Take &Snapshot"); shortcut: "Ctrl+5"; enabled: win.ws !== null; onTriggered: win.ws.snapshot() }
            MenuSeparator {}
            Action { text: qsTr("&Compile / Export…"); shortcut: "Ctrl+Shift+E"; enabled: Wordloom.projectOpen; onTriggered: compileDialog.open() }
            Action { text: qsTr("Export Story &Bible…"); enabled: Wordloom.projectOpen; onTriggered: bibleDialog.start() }
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
            MenuSeparator {}
            Action { text: qsTr("Con&vert to Smart Punctuation"); enabled: win.ws !== null; onTriggered: win.ws.smartenDocument() }
            Action { text: qsTr("Insert &Comment"); shortcut: "Ctrl+Alt+M"; enabled: win.ws !== null; onTriggered: win.ws.insertComment() }
            Action { text: qsTr("Insert &Footnote"); shortcut: "Ctrl+Alt+F"; enabled: win.ws !== null; onTriggered: win.ws.insertFootnote() }
        }
        Menu {
            title: qsTr("&Project")
            enabled: win.ws !== null
            Action { text: qsTr("New &Document"); shortcut: "Ctrl+N"; onTriggered: win.ws.addItem("text") }
            Action { text: qsTr("New &Folder"); shortcut: "Ctrl+Shift+N"; onTriggered: win.ws.addItem("folder") }
            Action { text: qsTr("New &Character"); onTriggered: win.ws.addInSection("characters") }
            Action { text: qsTr("New &Place"); onTriggered: win.ws.addInSection("places") }
            Action { text: qsTr("&Name Generator…"); shortcut: "Ctrl+Shift+G"; onTriggered: nameDialog.open() }
            MenuSeparator {}
            Action { text: qsTr("D&uplicate"); shortcut: "Ctrl+D"; onTriggered: win.ws.duplicate() }
            Action { text: qsTr("Split at Cursor"); shortcut: "Ctrl+K"; onTriggered: win.ws.splitAtCursor() }
            Action { text: qsTr("Merge with Next"); shortcut: "Ctrl+Shift+M"; onTriggered: win.ws.mergeNext() }
            Action { text: qsTr("Move to &Trash"); onTriggered: win.ws.trashCurrent() }
            Action { text: qsTr("&Empty Trash"); onTriggered: win.ws.emptyTrash() }
            MenuSeparator {}
            Action { text: qsTr("&Go to…"); shortcut: "Ctrl+P"; onTriggered: goTo.start() }
            Action { text: qsTr("&Find in Project"); shortcut: "Ctrl+Shift+F"; onTriggered: win.ws.focusSearch() }
            Action { text: qsTr("Writing &Statistics…"); shortcut: "Ctrl+Shift+T"; onTriggered: statsDialog.open() }
            Action { text: qsTr("Word Count &History…"); shortcut: "Ctrl+Shift+H"; onTriggered: historyWindow.show() }
            Action { text: qsTr("Text &Analysis…"); shortcut: "Ctrl+Shift+A"; onTriggered: analysisDialog.open() }
            Action { text: qsTr("Character &Grid…"); enabled: win.ws !== null; onTriggered: presenceDialog.open() }
            Action { text: qsTr("Writing Sp&rint…"); shortcut: "Ctrl+Shift+R"; onTriggered: sprintDialog.open() }
        }
        Menu {
            title: qsTr("&View")
            enabled: win.ws !== null
            Action { text: qsTr("&Editor"); shortcut: "Ctrl+1"; onTriggered: win.ws.viewMode = "editor" }
            Action { text: qsTr("&Corkboard"); shortcut: "Ctrl+2"; onTriggered: win.ws.viewMode = "corkboard" }
            Action { text: qsTr("&Outliner"); shortcut: "Ctrl+3"; onTriggered: win.ws.viewMode = "outliner" }
            Action { text: qsTr("&Timeline (Gantt)"); shortcut: "Ctrl+4"; onTriggered: win.ws.viewMode = "timeline" }
            Action { text: qsTr("&Relationship Map"); shortcut: "Ctrl+6"; onTriggered: win.ws.viewMode = "relations" }
            Action { text: qsTr("Rea&ding Mode"); shortcut: "Ctrl+7"; onTriggered: win.ws.viewMode = "reader" }
            MenuSeparator {}
            Action { text: qsTr("Go &Back"); shortcut: "Alt+Left"; enabled: win.ws ? win.ws.canGoBack : false; onTriggered: win.ws.goBack() }
            Action { text: qsTr("Go For&ward"); shortcut: "Alt+Right"; enabled: win.ws ? win.ws.canGoForward : false; onTriggered: win.ws.goForward() }
            MenuSeparator {}
            Action { text: qsTr("&Split Editor"); shortcut: "Ctrl+\\"; checkable: true; checked: win.ws ? win.ws.splitId !== "" : false; onTriggered: win.ws.toggleSplit() }
            Action { text: qsTr("&Focus Mode"); shortcut: "F11"; checkable: true; checked: win.ws ? win.ws.focusMode : false; onTriggered: win.ws.focusMode = !win.ws.focusMode }
            Action { text: qsTr("Show &Binder"); checkable: true; checked: win.ws ? win.ws.showBinder : true; onTriggered: win.ws.showBinder = !win.ws.showBinder }
            Action { text: qsTr("Show &Details"); shortcut: "Ctrl+Alt+I"; checkable: true; checked: win.ws ? win.ws.showInspector : true; onTriggered: win.ws.showInspector = !win.ws.showInspector }
            MenuSeparator {}
            Action { text: qsTr("Highlight Re&peated Words"); checkable: true; checked: Theme.highlightRepeats; onTriggered: Theme.highlightRepeats = !Theme.highlightRepeats }
            Action { text: qsTr("&Highlight Current Line"); checkable: true; checked: Theme.lineHighlight; onTriggered: Theme.lineHighlight = !Theme.lineHighlight }
            Menu {
                title: qsTr("Line Highlight &Colour")
                // Presets (translucent, so text stays readable in either theme).
                Repeater {
                    model: [
                        { name: qsTr("Amber"), c: "#40f2c14e" }, { name: qsTr("Blue"), c: "#3d5b9bd5" },
                        { name: qsTr("Green"), c: "#3d6abf69" }, { name: qsTr("Rose"), c: "#3de57399" },
                        { name: qsTr("Grey"), c: "#30808080" }
                    ]
                    delegate: MenuItem {
                        required property var modelData
                        text: modelData.name
                        checkable: true
                        checked: Qt.colorEqual(Theme.lineHighlightColor, modelData.c)
                        indicator: Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 3; color: modelData.c; border.color: Theme.border; border.width: parent.checked ? 2 : 1 }
                        onTriggered: { Theme.lineHighlightColor = modelData.c; Theme.lineHighlight = true; }
                    }
                }
                MenuSeparator {}
                Action { text: qsTr("Custom Colour…"); onTriggered: { lineColourDialog.selectedColor = Theme.lineHighlightColor; lineColourDialog.open(); } }
            }
            Action { text: qsTr("Complete &Names"); checkable: true; checked: Theme.completeNames; onTriggered: Theme.completeNames = !Theme.completeNames }
            Action { text: qsTr("Smart &Punctuation"); checkable: true; checked: Theme.smartPunctuation; onTriggered: Theme.smartPunctuation = !Theme.smartPunctuation }
            Action { text: qsTr("Check &Spelling"); shortcut: "F7"; checkable: true; checked: Theme.spellCheck; onTriggered: Theme.spellCheck = !Theme.spellCheck }
            Menu {
                id: spellLanguageMenu
                title: qsTr("Spelling &Language")
                // Installed dictionaries, read each time the menu opens.
                property var info: ({ chosen: "", system: "", systemName: "", list: [] })
                onAboutToShow: info = Api.call("spellLanguages") || info
                MenuItem {
                    text: spellLanguageMenu.info.system ? qsTr("Automatic: %1").arg(spellLanguageMenu.info.systemName) : qsTr("Automatic")
                    checkable: true
                    checked: Theme.spellLanguage === ""
                    onTriggered: win.setSpellLanguage("")
                }
                MenuSeparator {}
                Instantiator {
                    model: spellLanguageMenu.info.list
                    delegate: MenuItem {
                        required property var modelData
                        text: modelData.name
                        checkable: true
                        checked: Theme.spellLanguage === modelData.code
                        onTriggered: win.setSpellLanguage(modelData.code)
                    }
                    onObjectAdded: (index, object) => spellLanguageMenu.insertItem(2 + index, object)
                    onObjectRemoved: (index, object) => spellLanguageMenu.removeItem(object)
                }
            }
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
        Workspace { sprint: sprintDialog; onHistoryRequested: historyWindow.show() }
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
        // Project templates (wordloom-core's templates.rs).
        // (Api.call, not Api.get: this works with no project open.)
        property var templates: []
        readonly property string template: templates.length ? templates[Math.max(0, newTemplate.currentIndex)].id : "blank"
        onAboutToShow: { templates = Api.call("templates") || []; newTitle.text = ""; newAuthor.text = ""; newTitle.forceActiveFocus(); }
        GridLayout {
            anchors.fill: parent
            columns: 2
            Label { text: qsTr("Title") }
            TextField { id: newTitle; Layout.fillWidth: true; placeholderText: qsTr("My Novel") }
            Label { text: qsTr("Author") }
            TextField { id: newAuthor; Layout.fillWidth: true }
            Label { text: qsTr("Template") }
            ComboBox {
                id: newTemplate
                Layout.fillWidth: true
                model: newDialog.templates.map(t => t.name)
            }
            Item { width: 1; height: 1 }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.pixelSize: 12
                text: newDialog.templates.length ? newDialog.templates[Math.max(0, newTemplate.currentIndex)].description : ""
            }
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
            if (Wordloom.projectOpen) { if (ws) ws.flush(); autoBackupDialog.beforeClose(); }
            Api.call("newProject", folder.toString(), t, newAuthor.text, template);
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
    NameDialog { id: nameDialog; anchors.centerIn: parent }
    ColorDialog {
        id: lineColourDialog
        title: qsTr("Line Highlight Colour")
        options: ColorDialog.ShowAlphaChannel
        onAccepted: { Theme.lineHighlightColor = selectedColor; Theme.lineHighlight = true; }
    }
    GoToPopup {
        id: goTo
        onChosen: (id) => { Api.call("reveal", id); win.ws.select(id); }
    }
    PresenceDialog {
        id: presenceDialog
        anchors.centerIn: parent
        onMentionRequested: (docId, name) => win.ws.showMention(docId, name)
    }
    AnalysisDialog {
        id: analysisDialog
        anchors.centerIn: parent
        node: win.ws ? win.ws.current : null
        onSearchRequested: (text) => win.ws.searchFor(text)
        onSentenceRequested: (docId, text) => win.ws.showMention(docId, text)
    }
    HistoryWindow { id: historyWindow; transientParent: win }
    SprintDialog { id: sprintDialog; anchors.centerIn: parent; flush: () => { if (win.ws) win.ws.flush(); } }

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
    // File ▸ Back Up to Zip…: the whole project in one .zip, named with the
    // date, in the folder used last time (Documents at first).
    FileDialog {
        id: backupDialog
        title: qsTr("Back Up Project to Zip")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "zip"
        nameFilters: [qsTr("Zip archives (*.zip)")]
        property string lastFolder: ""
        function start() {
            if (win.ws) win.ws.flush();
            const folder = lastFolder || StandardPaths.writableLocation(StandardPaths.DocumentsLocation);
            const safe = Wordloom.title.replace(/[^\w \-]/g, "_").trim() || "Untitled";
            const when = new Date();
            const pad = (n) => (n < 10 ? "0" : "") + n;
            const stamp = when.getFullYear() + "-" + pad(when.getMonth() + 1) + "-" + pad(when.getDate()) + " " + pad(when.getHours()) + pad(when.getMinutes());
            currentFolder = folder;
            selectedFile = folder.toString().replace(/\/$/, "") + "/" + encodeURIComponent(safe + " backup " + stamp + ".zip");
            open();
        }
        onAccepted: {
            const f = selectedFile.toString();
            lastFolder = f.substring(0, f.lastIndexOf("/"));
            const r = Api.call("backupZip", f);
            if (r) Api.say(qsTr("Backed up %1 files (%2) to %3").arg(r.files).arg(Api.fmtBytes(r.bytes)).arg(r.path));
        }
    }
    // File ▸ Export Story Bible…: every character and place in one document
    // (wordloom-core's bible.rs). The format follows the chosen file type.
    FileDialog {
        id: bibleDialog
        title: qsTr("Export Story Bible")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "docx"
        nameFilters: [qsTr("Word document (*.docx)"), qsTr("Web page (*.html)"), qsTr("Markdown (*.md)"), qsTr("Plain text (*.txt)")]
        property string lastFolder: ""
        function start() {
            if (win.ws) win.ws.flush();
            const folder = lastFolder || StandardPaths.writableLocation(StandardPaths.DocumentsLocation);
            const safe = Wordloom.title.replace(/[^\w \-]/g, "_").trim() || "Untitled";
            currentFolder = folder;
            selectedFile = folder.toString().replace(/\/$/, "") + "/" + encodeURIComponent(safe + " story bible.docx");
            open();
        }
        // The file to write: the chosen type's extension unless the name
        // already ends in one Wordloom can write.
        function target(file, filterIndex) {
            if (/\.(docx|html?|md|markdown|txt)$/i.test(file)) return file;
            return file.replace(/\.[A-Za-z0-9]{1,5}$/, "") + "." + ["docx", "html", "md", "txt"][Math.max(0, filterIndex)];
        }
        function write(file) {
            const r = Api.call("exportBible", file);
            if (r !== undefined) Api.say(qsTr("Story bible saved to %1").arg(r));
            return r;
        }
        onAccepted: {
            const f = target(selectedFile.toString(), selectedNameFilter.index);
            lastFolder = f.substring(0, f.lastIndexOf("/"));
            write(f);
        }
    }
    // File ▸ Restore from Zip Backup…: pick the zip, then where to put the
    // restored project (storage::restore_zip), and open it. The zip and
    // anything already in that folder are left alone.
    FileDialog {
        id: restoreZipDialog
        title: qsTr("Restore a Project from a Zip Backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Zip backups (*.zip)")]
        function start() {
            currentFolder = autoBackupDialog.closeBackups ? autoBackupDialog.where
                : (backupDialog.lastFolder || StandardPaths.writableLocation(StandardPaths.DocumentsLocation));
            open();
        }
        onAccepted: {
            restoreWhereDialog.zip = selectedFile.toString();
            restoreWhereDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/Wordloom";
            restoreWhereDialog.open();
        }
    }
    FolderDialog {
        id: restoreWhereDialog
        title: qsTr("Restore the project into…")
        property string zip: ""
        onAccepted: win.restoreZip(zip, selectedFolder.toString())
    }
    function restoreZip(zip, folder) {
        if (Wordloom.projectOpen) { if (ws) ws.flush(); autoBackupDialog.beforeClose(); Api.call("close"); }
        const r = Api.call("restoreZip", zip, folder);
        if (r) Api.say(qsTr("Restored to %1").arg(r.path));
        return r;
    }
    // File ▸ Automatic Backups…: a zip of the project, in a folder of your
    // choice, each time it's closed (if anything changed), keeping the
    // newest few (Session::auto_backup).
    Dialog {
        id: autoBackupDialog
        title: qsTr("Automatic Backups")
        modal: true
        anchors.centerIn: parent
        width: Math.min(520, win.width - 32)
        property bool closeBackups: false
        property string folder: ""
        property int keep: 10
        readonly property string where: folder || (StandardPaths.writableLocation(StandardPaths.DocumentsLocation).toString() + "/Wordloom Backups")
        // Back up now; `quiet` leaves out the notice when nothing changed.
        function run(quiet) {
            if (!Wordloom.projectOpen) return undefined;
            if (win.ws) win.ws.flush();
            const r = Api.call("autoBackup", where, keep);
            if (r === undefined) return r;
            if (r.skipped) { if (!quiet) Api.say(qsTr("No changes since the last automatic backup")); }
            else Api.say(qsTr("Backed up automatically to %1 (%2)").arg(r.path).arg(Api.fmtBytes(r.bytes)));
            return r;
        }
        // Called just before a project closes (Close Project, opening or
        // creating another, quitting).
        function beforeClose() { if (closeBackups && Wordloom.projectOpen) run(true); }
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            CheckBox {
                id: autoOn
                text: qsTr("Back up to a zip file whenever a project is closed")
                checked: autoBackupDialog.closeBackups
                onToggled: autoBackupDialog.closeBackups = checked
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Folder") }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: decodeURIComponent(autoBackupDialog.where.replace(/^file:\/\//, ""))
                    color: Theme.subtext
                }
                Button { text: qsTr("Choose…"); onClicked: autoFolderDialog.open() }
            }
            RowLayout {
                Label { text: qsTr("Keep the newest") }
                SpinBox { id: autoKeep; from: 1; to: 100; editable: true; value: autoBackupDialog.keep; onValueModified: autoBackupDialog.keep = value }
                Label { text: qsTr("backups of each project") }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext
                text: qsTr("Backups are named like \u201cTitle autobackup 2026-11-06 1730.zip\u201d. If nothing has changed since the last one, no new zip is made. Older automatic backups beyond the number kept are deleted; other files in the folder, including ones made with Back Up to Zip, are left alone. Choose a folder on another drive or a synced cloud folder so a backup survives losing this disk.")
            }
        }
        footer: DialogButtonBox {
            Button { text: qsTr("Back Up Now"); enabled: Wordloom.projectOpen; onClicked: autoBackupDialog.run(false) }
            Button { text: qsTr("Close"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        }
    }
    FolderDialog {
        id: autoFolderDialog
        title: qsTr("Keep automatic backups in…")
        currentFolder: autoBackupDialog.where
        onAccepted: autoBackupDialog.folder = selectedFolder.toString()
    }
    // File ▸ Import Manuscript…: a whole book from Word, Markdown or text,
    // split into chapters and scenes (wordloom-core's import.rs).
    FileDialog {
        id: manuscriptDialog
        title: qsTr("Import a Manuscript")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Manuscripts (*.docx *.md *.markdown *.txt)"), qsTr("All files (*)")]
        onAccepted: win.importManuscript(selectedFile.toString())
    }
    function bibleRef() { return bibleDialog; }
    function importManuscript(file) {
        if (win.ws) win.ws.flush();
        const r = Api.call("importManuscript", file);
        if (!r) return null;
        win.ws.select(r.folder, "corkboard");
        Api.say(qsTr("Imported %1 in %2 and %3. Edit ▸ Undo removes it again.")
            .arg(Api.plural(r.words, qsTr("word"))).arg(Api.plural(r.chapters, qsTr("chapter"))).arg(Api.plural(r.scenes, qsTr("scene"))));
        return r;
    }
    FileDialog {
        id: importDialog
        title: qsTr("Import into Research")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images and PDFs (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.pdf)"), qsTr("All files (*)")]
        onAccepted: if (win.ws) win.ws.importFiles(selectedFiles)
    }
    // The project is open in another Wordloom (window or computer).
    Dialog {
        id: lockedDialog
        title: qsTr("Project already open")
        modal: true
        anchors.centerIn: parent
        width: 480
        property string path: ""
        function offer(p) { path = p; open(); }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: qsTr("This project is open in another Wordloom, in another window or on another computer that shares the folder. If both copies keep working, each will overwrite the other's changes when it saves.\n\nClose it there first. Open it here anyway only if that copy has crashed or you're sure it's closed.")
        }
        footer: DialogButtonBox {
            Button { text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: qsTr("Open Anyway"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }
        onAccepted: Api.call("openProject", path, true)
    }

    // Offered when project.json is damaged and a backup exists.
    Dialog {
        id: restoreDialog
        title: qsTr("Project file damaged")
        modal: true
        anchors.centerIn: parent
        width: 480
        property string path: ""
        function offer(p) { path = p; open(); }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: qsTr("This project's project.json can't be read: it may have been cut short or edited by hand. Wordloom can restore it from the newest backup that still opens, which may be up to ten minutes old.\n\nYour writing is kept in separate files. Documents written since that backup are put in a \u201cRecovered after restore\u201d folder, and the damaged file is kept beside the project as project.json.damaged-\u2026 for safety.")
        }
        footer: DialogButtonBox {
            Button { text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: qsTr("Restore from Backup"); highlighted: true; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }
        onAccepted: {
            const m = Api.call("restoreBackup", path);
            if (m !== undefined) Api.say(qsTr("Restored from %1").arg(String(m.restored_from).split("/").pop())
                + (m.recovered ? qsTr("; %1 newer document(s) are in “Recovered after restore”").arg(m.recovered) : ""));
        }
    }

    StatsDialog {
        id: statsDialog
        anchors.centerIn: parent
        onHistoryRequested: { close(); historyWindow.show(); }
    }
    ProjectSettingsDialog { id: settingsDialog; anchors.centerIn: parent }

    Dialog {
        id: aboutDialog
        title: qsTr("About Wordloom")
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        Label {
            text: "<h2>Wordloom</h2><p>A writing studio for long-form work:<br/>binder, corkboard, outliner, split editor,<br/>research files, snapshots, project-wide undo,<br/>spell checking, a name generator,<br/>compile to EPUB / DOCX / HTML / Markdown,<br/>and a story timeline Gantt.</p><p>Built with Rust and Qt " + "6</p>"
            textFormat: Text.RichText
        }
    }
}
