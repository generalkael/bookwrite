import QtQuick
import com.wordloom.app
import com.wordloom.styling

// `wordloom --sample=DIR --selftest`: drives the real UI through checks for
// bugs fixed in the past, prints PASS / FAIL lines and exits with status 1
// if anything failed. CI runs it on every push.
Item {
    id: st
    property var win                     // the ApplicationWindow
    property var history                 // HistoryWindow
    property var sprint                  // SprintDialog
    property var analysis                // AnalysisDialog
    property var compile                 // CompileDialog
    property var goTo                    // GoToPopup
    property var autoBackup              // Main.qml's Automatic Backups dialog
    property int step: 0
    InputSim { id: input }
    property int failures: 0
    property int passes: 0
    property string current: ""

    function log(s) { Api.call("log", s); }
    function check(ok, what) {
        if (ok) { passes++; log("PASS  " + current + ": " + what); }
        else { failures++; log("FAIL  " + current + ": " + what); }
    }
    function rowId(title) { const r = Api.get("binder", []).find(x => x.title === title); return r ? r.id : ""; }
    function ws() { return win.ws; }
    function ed() { return win.ws.mainEditor(); }

    // Each step runs after the previous one has had time to lay out.
    readonly property var steps: [
        ["select opens editor", () => { ws().select(rowId("The Storm")); }],
        ["select opens editor", () => {
            check(ws().viewMode === "corkboard", "a folder without text opens the corkboard");
            ws().select(rowId("Arrival"));
            check(ws().viewMode === "editor", "a document clicked from the corkboard opens the editor");
            ws().viewMode = "outliner"; ws().select(rowId("The Keeper"));
            check(ws().viewMode === "editor", "a document clicked from the outliner opens the editor");
        }],
        ["page fills pane", () => {
            Theme.pageWidth = 0;
            const i = ed().testInfo();
            // Pane minus the scroll-bar gutter (14) and the page margin (24).
            check(Math.abs(i.pageW - (i.paneW - 38)) <= 1, "the page fills the pane (" + Math.round(i.pageW) + " of " + Math.round(i.paneW) + ")");
        }],
        ["caret stays visible", () => {
            const a = ed().firstArea();
            a.forceActiveFocus(); a.cursorPosition = a.length;
            for (let k = 0; k < 60; ++k) a.insert(a.cursorPosition, "\nline " + k);
        }],
        ["caret stays visible", () => {
            const i = ed().testInfo();
            check(i.contentY > 0, "the editor scrolled while typing past the bottom");
            check(i.caretY >= i.contentY && i.caretY + i.caretH <= i.contentY + i.viewH, "the caret is inside the visible area");
        }],
        ["formatting", () => {
            const a = ed().firstArea();
            a.text = "one two three";
            a.select(4, 7); ed().activeArea = a; ed().toggleEmphasis(2);
            check(a.text === "one **two** three", "Ctrl+B wraps the selection: " + JSON.stringify(a.text));
            ed().toggleEmphasis(2);
            check(a.text === "one two three", "Ctrl+B again unwraps it");
            a.cursorPosition = 2; ed().cycleHeading();
            check(a.text.startsWith("# "), "the heading button adds #");
        }],
        ["comments", () => {
            const a = ed().firstArea();
            a.text = "one two";
            a.cursorPosition = 7; ed().activeArea = a; ed().insertComment();
            a.insert(a.cursorPosition, "fix");
            check(a.text === "one two {>> fix <<}", "the comment button inserts {>> <<} with the caret inside: " + JSON.stringify(a.text));
            ed().flush();
            const id = ws().currentId;
            check(Api.get("nodeInfo", null, id).words === 2, "a comment isn't counted as words");
            const cs = Api.get("comments", [], id);
            check(cs.length === 1 && cs[0].text === "fix", "Details lists the comment");
            a.cursorPosition = 0;
            check(ed().showComment(id, 0) && a.selectedText === "{>> fix <<}", "clicking it selects the comment in the editor");
        }],
        ["repeated words", () => {
            const a = ed().firstArea();
            a.text = "The window was dark. Beyond the window, a lantern swung.";
            Theme.highlightRepeats = true;
        }],
        ["repeated words", () => {
            const a = ed().firstArea(), t = a.text;
            const tinted = (word, nth) => { let i = -1; for (let n = 0; n <= nth; n++) i = t.indexOf(word, i + 1); const c = a.tintAt(i + 1); return c.a > 0 && c.b > c.r; }; // the blue repeat tint, not spelling's red
            check(tinted("window", 0) && tinted("window", 1), "both uses of a repeated word are tinted");
            check(!tinted("lantern", 0) && !tinted("dark", 0), "words used once are not");
            Theme.highlightRepeats = false;
        }],
        ["repeated words", () => {
            const a = ed().firstArea();
            check(a.tintAt(a.text.indexOf("window") + 1).a === 0, "it can be switched off (" + a.tintAt(a.text.indexOf("window") + 1) + ")");
            a.text = "";
        }],
        ["footnotes", () => {
            const a = ed().firstArea();
            a.text = "The log lied.\n\n";
            a.forceActiveFocus(); ed().activeArea = a;
            a.cursorPosition = a.text.indexOf(".") + 1;
            ws().insertFootnote();
            check(a.text === "The log lied.[^1]\n\n[^1]: " && a.cursorPosition === a.length, "Insert Footnote adds [^1] and its note at the end (" + JSON.stringify(a.text) + ")");
            a.insert(a.length, "Pages were cut.");
            a.cursorPosition = a.text.indexOf("lied") + 4;
            ws().insertFootnote();
            check(a.text === "The log lied[^2].[^1]\n\n[^1]: Pages were cut.\n\n[^2]: ", "the next one is numbered 2 (" + JSON.stringify(a.text) + ")");
            a.text = "";
        }],
        ["line highlight", () => {
            const a = ed().firstArea();
            a.text = "First line\nSecond line\nThird line";
            Theme.lineHighlight = true;
            Theme.lineHighlightColor = "#40112233";
            a.forceActiveFocus(); ed().activeArea = a;
            a.cursorPosition = a.text.indexOf("Third");
        }],
        ["line highlight", () => {
            const a = ed().firstArea(), bar = ed().lineBarRef();
            const caretY = a.mapToItem(bar.parent, 0, a.cursorRectangle.y).y;
            check(bar.visible && Math.abs(bar.y - caretY) < 1 && bar.height === a.cursorRectangle.height,
                  "the bar sits on the caret's line (bar " + Math.round(bar.y) + ", caret " + Math.round(caretY) + ")");
            check(Qt.colorEqual(bar.color, "#40112233"), "the bar uses the chosen colour");
            a.cursorPosition = 0;
            check(Math.abs(bar.y - a.mapToItem(bar.parent, 0, a.cursorRectangle.y).y) < 1, "it follows the caret to another line");
            Theme.lineHighlight = false;
            check(!bar.visible, "it can be switched off");
            Theme.lineHighlightColor = "#40f2c14e";
            a.text = "";
        }],
        ["name completion", () => {
            const a = ed().firstArea();
            a.forceActiveFocus(); ed().activeArea = a;
            a.text = "Then ";
            a.cursorPosition = 5;
            a.insert(5, "Tob");
            check(ed().completions.length > 0 && ed().completions.indexOf("Tobias Wren") >= 0, "typing 'Tob' suggests Tobias Wren (" + JSON.stringify(ed().completions) + ")");
            ed().completionIndex = ed().completions.indexOf("Tobias Wren");
            ed().completionKey({ key: Qt.Key_Tab });
            check(a.text === "Then Tobias Wren" && ed().completions.length === 0, "Tab completes it: " + JSON.stringify(a.text));
            a.insert(a.cursorPosition, " met mara");
            check(ed().completions.length === 0, "lower-case words aren't completed");
            a.text = "";
        }],
        ["smart punctuation", () => {
            const a = ed().firstArea();
            a.text = "";
            a.forceActiveFocus(); ed().activeArea = a;
            const type = (s) => { for (const ch of s) if (!ed().smartKey(a, { text: ch, modifiers: 0 })) a.insert(a.cursorPosition, ch); };
            type("\"Don't--\" she said... \"Wait.\"\n\n---");
            check(a.text === "“Don’t—” she said… “Wait.”\n\n---", "typing gives curly quotes, dashes and ellipses, and keeps --- as a scene break: " + JSON.stringify(a.text));
            a.text = "\"Plain\" -- text...";
            ed().smartenAll();
            check(a.text === "“Plain” — text…", "Convert to Smart Punctuation fixes existing text: " + JSON.stringify(a.text));
        }],
        ["split editor follows focus", () => {
            ws().select(rowId("Arrival"), "editor");
            ws().openInSplit(rowId("The Keeper"));
        }],
        ["split editor follows focus", () => {
            const main = ws().currentId;
            ws().splitEditorRef().firstArea().forceActiveFocus();
            ws().binderRef().selected(rowId("Night Watch"));    // as a click in the binder does
            check(ws().splitId === rowId("Night Watch") && ws().currentId === main,
                  "with the split editor focused, a binder pick opens there and the main editor keeps its document");
            check(ws().binderRef().currentId === ws().splitId && ws().inspectorRef().nodeId === ws().splitId,
                  "the binder highlight and Details follow the focused split editor");
            ed().firstArea().forceActiveFocus();
            ws().binderRef().selected(rowId("The Week Before"));
            check(ws().currentId === rowId("The Week Before") && ws().splitId === rowId("Night Watch"),
                  "with the main editor focused, a binder pick opens in the main editor");
            ws().splitId = "";
        }],
        ["find & replace", () => {
            const a = ed().firstArea();
            a.text = "the cat and then the dog";
            ws().findInDocument(true);
            ed().findText = "the"; ed().findStep(0);
            check(ed().matchCount === 2, "whole words: 'the' matches twice, not inside 'then' (" + ed().matchCount + ")");
            ed().replaceText = "a"; ed().replaceAll();
            check(a.text === "a cat and then a dog", "replace all leaves 'then' alone: " + JSON.stringify(a.text));
            ed().closeFind();
        }],
        ["spelling", () => {
            const a = ed().firstArea();
            a.text = "The lantren was lit by Tobias.";
            const r = a.positionToRectangle(6);
            a.prepareMenu(Qt.point(r.x + 1, r.y + r.height / 2));
            check(a.word === "lantren" && a.misspelled, "'lantren' is flagged");
            check(a.suggestions.indexOf("lantern") >= 0, "'lantern' is suggested");
            ed().menuArea = a;
            const m = ed().menuRef();
            check(m.misspelled && m.suggestions.indexOf("lantern") >= 0, "the shared right-click menu shows them for the area clicked");
            ed().menuArea = null; a.prepareMenu(Qt.point(0, 0));
            input.click(win, a.mapToItem(null, r.x + 1, r.y + r.height / 2), Qt.RightButton);
            check(m.opened && m.a === a && m.suggestions.indexOf("lantern") >= 0, "a real right-click on the word opens the menu with suggestions (" + m.opened + ")");
            m.close();
            check(Api.get("spellCheck", false, "Tobias"), "character names are accepted");
        }],
        ["views", () => {
            ws().viewMode = "relations";
        }],
        ["views", () => {
            check(Api.get("relations", null).people.length === 3, "the map lists the sample's three characters");
            ws().viewMode = "reader";
        }],
        ["views", () => {
            check(ws().viewMode === "reader", "reading mode opens");
            ws().viewMode = "editor";
            history.show(0);
        }],
        ["history window", () => {
            check(history.hist !== null && history.hist.buckets.length === 30, "the Daily preset shows 30 days");
            history.applyPreset(1);
            check(history.hist.bucket === "week", "Weekly groups by week");
            check(Qt.colorEqual(history.palette.base, Theme.base) && Qt.colorEqual(history.palette.text, Theme.text),
                  "the window's controls use the app theme, not the system colours");
            history.close();
        }],
        ["appearances", () => {
            ws().select(rowId("Tobias Wren"));
        }],
        ["appearances", () => {
            const ap = ws().inspectorRef().appearances;
            check(ap !== null && ap.total > 0 && ap.documents.length > 0, "Details lists the scenes that mention Tobias (" + (ap ? ap.total : "none") + ")");
            if (ap && ap.documents.length) ws().showMention(ap.documents[0].id, ap.documents[0].name);
        }],
        ["appearances", () => {
            check(ws().viewMode === "editor" && ed().findOpen && ed().matchCount > 0, "clicking one opens the scene with the name found (" + ed().matchCount + ")");
            ed().closeFind();
        }],
        ["text analysis", () => {
            analysis.wholeBook = true;
            analysis.open();
        }],
        ["text analysis", () => {
            const r = analysis.r;
            check(r !== null && r.words === Api.get("stats", null).manuscript_words, "Text Analysis counts the same words as the statistics (" + (r ? r.words : "none") + ")");
            check(r !== null && r.top_words.length > 0 && r.top_words.every(w => w.text !== "the"), "most used words leave out common words");
            analysis.close();
        }],
        ["go to", () => {
            goTo.start();
            const recent = goTo.hits.length;
            goTo.hits = Api.get("goTo", [], "nght wtch");
            check(recent > 0 && goTo.hits.length > 0 && goTo.hits[0].title === "Night Watch", "Go to finds 'Night Watch' from 'nght wtch'");
            goTo.choose(0);
            check(!goTo.opened && ws().current && ws().current.title === "Night Watch" && ws().viewMode === "editor", "choosing it opens the document");
        }],
        ["pdf export", () => {
            const dir = Api.get("meta", null).path;
            const base = "file://" + dir.substring(0, dir.lastIndexOf("/"));
            compile.selectFormat("pdf", 0);
            const book = compile.writePdf(base + "/selftest-book.pdf");
            check(book.ok && book.pages >= 3, "a book PDF is written (" + book.pages + " pages)");
            compile.selectFormat("pdf", 1);
            const ms = compile.writePdf(base + "/selftest-manuscript.pdf");
            check(ms.ok && ms.pages >= 4, "a manuscript PDF is written (" + ms.pages + " pages)");
            check(compile.shortTitle() === "Lighthouse Keeper", "the header uses a short title: " + compile.shortTitle());
            // A long chapter runs on over many pages.
            const para = "The keeper climbed the hundred and twelve steps again, counting each one under his breath, and the lamp waited at the top as it always had. ";
            Api.call("setText", rowId("Arrival"), Array(60).fill(para + para).join("\n\n"));
            const longPdf = compile.writePdf(base + "/selftest-long.pdf");
            check(longPdf.ok && longPdf.pages >= ms.pages + 10, "a long chapter continues over many pages (" + longPdf.pages + ")");
            compile.selectFormat("markdown", 0);
        }],
        ["import manuscript", () => {
            // Round trip: export the manuscript as Markdown, import it back.
            const meta = Api.get("meta", null), dir = meta.path.substring(0, meta.path.lastIndexOf("/"));
            const before = Api.get("stats", null).manuscript_words;
            const file = Api.call("export", "file://" + dir + "/selftest-export.md", { format: "markdown" });
            const r = file ? win.importManuscript("file://" + file) : null;
            check(r !== null && r.chapters === 3 && r.scenes >= 4 && r.words === before, "an exported manuscript imports back: " + JSON.stringify(r) + " of " + before + " words");
            check(ws().viewMode === "corkboard" && ws().current && ws().current.title === meta.title, "the imported book opens on the corkboard, named after its title (" + ws().viewMode + ", " + (ws().current ? ws().current.title : "none") + ")");
        }],
        ["zip backup", () => {
            const dir = Api.get("meta", null).path;
            const r = Api.call("backupZip", dir.substring(0, dir.lastIndexOf("/")) + "/selftest-backup.zip");
            check(r && r.files >= 5 && r.bytes > 1000, "Back Up to Zip packs the project (" + (r ? r.files + " files, " + r.bytes + " bytes" : "failed") + ")");
        }],
        ["hidden editor", () => {
            ws().select(rowId("Arrival"), "editor");
            const ms = Api.call("rootId", "manuscript");
            ws().select(ms, "corkboard");
            check(ed().stale && !ed().docs.some(d => d.id === ms), "a hidden editor doesn't build what's selected (a whole manuscript would take seconds)");
            ws().viewMode = "editor";
            check(!ed().stale && ed().docs.length > 0 && ed().docs[0].id === ms, "it catches up when shown (" + (ed().docs.length ? ed().docs[0].title : "none") + ")");
            ws().select(rowId("Arrival"), "editor");
        }],
        ["binder multi-select", () => {
            const b = ws().binderRef(), click = (t, m) => input.click(win, b.rowPoint(rowId(t)), Qt.LeftButton, m || 0);
            click("Arrival");
            click("The Keeper", Qt.ControlModifier);
            click("Night Watch", Qt.ControlModifier);
            check(b.pickCount === 3 && ws().current.title === "Arrival", "Ctrl+click picks items and keeps the open one (" + b.pickCount + ")");
            const done = Api.get("labels", null).statuses.find(x => x.name === "Done");
            b.setPicked("status", done.id);
            check(["Arrival", "The Keeper", "Night Watch"].every(t => Api.get("nodeInfo", {}, rowId(t)).status === done.id), "a status is set on all of them");
            Api.call("undo");
            check(["Arrival", "The Keeper", "Night Watch"].every(t => Api.get("nodeInfo", {}, rowId(t)).status !== done.id), "and one Undo takes it off all of them");
            click("Arrival");
            check(b.pickCount === 0, "a plain click goes back to one item");
            click("Night Watch", Qt.ShiftModifier);
            check(b.pickedIds().map(id => b.rows[b.rowIndex(id)].title).join(",") === "Arrival,The Keeper,The Log,Night Watch", "Shift+click picks a range (" + b.pickedIds().length + ")");
            input.key(win, Qt.Key_Escape);
            check(b.pickCount === 0, "Esc clears it");
            click("Arrival"); click("The Keeper", Qt.ControlModifier);
            input.key(win, Qt.Key_Delete);
            check(Api.get("children", [], rowId("The Storm")).length === 0, "Delete moves all the picked items to the Trash");
            Api.call("undo");
            check(Api.get("children", [], rowId("The Storm")).map(x => x.title).join(",") === "Arrival,The Keeper", "one Undo brings them both back");
        }],
        ["binder multi-select", () => {
            // Drag two picked scenes into The Return, by the second one.
            const b = ws().binderRef(), at = (t) => b.rowPoint(rowId(t));
            input.click(win, at("Arrival"));
            input.click(win, at("Night Watch"), Qt.LeftButton, Qt.ControlModifier);
            input.drag(win, at("Night Watch"), at("The Return"));
            const kids = Api.get("children", [], rowId("The Return")).map(x => x.title).join(",");
            check(kids === "Confession,Arrival,Night Watch", "dragging picked items moves them all, in binder order (" + kids + ")");
            check(Api.call("history").undo === "Move 2 Items", "as one undo step");
            Api.call("undo");
            check(Api.get("children", [], rowId("The Storm")).map(x => x.title).join(",") === "Arrival,The Keeper", "Undo puts them back");
        }],
        ["corkboard drag", () => { ws().select(rowId("The Storm"), "corkboard"); }],
        ["corkboard drag", () => {
            const c = ws().corkboardRef(), titles = () => c.cards.map(x => x.title).join(",");
            check(titles() === "Arrival,The Keeper", "the corkboard shows The Storm's scenes (" + titles() + ")");
            c.startDrag(rowId("The Keeper"), "The Keeper");
            c.updateDrag(c.cardPoint(1, 0.5));
            check(c.dropMode === "", "dropping a card on itself does nothing");
            c.updateDrag(c.cardPoint(0, 0.2));
            check(c.dropMode === "before" && c.dropIndex === 0, "the left half of a card drops before it (" + c.dropMode + " " + c.dropIndex + ")");
            check(c.finishDrag() && titles() === "The Keeper,Arrival", "dragging a card reorders the scenes (" + titles() + ")");
            Api.call("undo");
            check(titles() === "Arrival,The Keeper", "Undo puts it back (" + titles() + ")");
        }],
        // Steps of their own: after Undo the cards are rebuilt on the next layout.
        ["corkboard drag", () => {
            // The same with real mouse events, starting on the card's edge.
            const c = ws().corkboardRef(), titles = () => c.cards.map(x => x.title).join(",");
            const from = c.cardGrip(1), to = c.cardPoint(0, 0.2);
            if (from && to) input.drag(win, from, to);
            check(titles() === "The Keeper,Arrival", "a mouse drag moves the card (" + titles() + ")");
            if (titles() === "The Keeper,Arrival") Api.call("undo");
        }],
        // Its own step: after Undo the cards are rebuilt on the next layout.
        ["corkboard drag", () => {
            const c = ws().corkboardRef(), titles = () => c.cards.map(x => x.title).join(",");
            const from = c.cardPoint(1, 0.5), to = c.cardPoint(0, 0.2);
            check(from !== null && to !== null, "the cards are laid out");
            if (from && to) input.drag(win, from, to);
            check(titles() === "Arrival,The Keeper" && c.dragId === "", "dragging across the synopsis text selects it instead of moving the card (" + titles() + ", drag " + c.dragId + " " + c.dropMode + ")");
            ws().select(Api.call("rootId", "manuscript"), "corkboard");
        }],
        ["corkboard drag", () => {
            const c = ws().corkboardRef(), ret = rowId("The Return"), log = rowId("The Log");
            const iLog = c.cards.findIndex(x => x.id === log);
            c.startDrag(ret, "The Return");
            c.updateDrag(c.cardPoint(iLog, 0.5));
            check(c.dropMode === "inside", "the middle of a folder card drops into the folder (" + c.dropMode + ")");
            c.finishDrag();
            check(Api.get("children", [], log).some(x => x.id === ret), "the card moves into the folder");
            Api.call("undo");
            check(c.cards.some(x => x.id === ret), "Undo brings it back");
        }],
        ["corkboard keys", () => { ws().select(rowId("The Storm"), "corkboard"); }],
        ["corkboard keys", () => {
            const c = ws().corkboardRef(), titles = () => c.cards.map(x => x.title).join(",");
            const key = (k, m) => input.key(win, k, m || 0);
            c.focusBoard();
            c.keyId = c.cards[0].id;
            key(Qt.Key_Right);
            check(c.keyIndex === 1, "→ highlights the next card (" + c.keyIndex + ")");
            key(Qt.Key_Left, Qt.ControlModifier);
            check(titles() === "The Keeper,Arrival" && c.cards[c.keyIndex].title === "The Keeper", "Ctrl+← moves the card earlier and keeps it highlighted (" + titles() + ")");
            Api.call("undo");
            key(Qt.Key_Backspace);
        }],
        ["corkboard keys", () => {
            const c = ws().corkboardRef(), key = (k, m) => input.key(win, k, m || 0);
            check(c.containerTitle === "Manuscript" && c.cards[c.keyIndex].title === "The Storm", "Backspace goes up a folder, highlighting where you were (" + c.containerTitle + ", " + (c.keyIndex >= 0 ? c.cards[c.keyIndex].title : "none") + ")");
            key(Qt.Key_Return);
        }],
        ["corkboard keys", () => {
            const c = ws().corkboardRef(), key = (k, m) => input.key(win, k, m || 0);
            check(c.containerTitle === "The Storm" && ws().viewMode === "corkboard", "Enter on a folder card shows its cards (" + c.containerTitle + ")");
            key(Qt.Key_End);
            check(c.cards[c.keyIndex].title === "The Keeper", "End highlights the last card");
            key(Qt.Key_Delete);
            check(c.cards.map(x => x.title).join(",") === "Arrival" && c.cards[c.keyIndex].title === "Arrival", "Delete trashes the card and highlights its neighbour");
            Api.call("undo");
            key(Qt.Key_End);
            key(Qt.Key_Return);
            check(ws().viewMode === "editor" && ws().current && ws().current.title === "The Keeper", "Enter on a document opens it in the editor (" + ws().viewMode + ")");
        }],
        ["outliner", () => {
            Api.call("setField", rowId("Arrival"), "field:POV", "Mara");
            ws().select(Api.call("rootId", "manuscript"), "outliner");
        }],
        ["outliner", () => {
            const o = ws().outlinerRef(), all = o.rows.length, storm = o.rows.find(x => x.title === "The Storm");
            check(storm && all > storm.child_count, "the outliner lists the manuscript (" + all + " rows)");
            o.toggle(storm.id);
            check(o.rows.length === all - storm.child_count && !o.rows.some(x => x.title === "Arrival"), "collapsing a folder hides what's inside it");
            o.setAllCollapsed(false);
            check(o.rows.length === all, "Expand All shows everything again");
            check(o.fieldKeys.indexOf("POV") >= 0, "custom fields used below are offered as columns (" + o.fieldKeys + ")");
            o.toggleColumn("field:POV");
            check(o.hasColumn("field:POV") && o.cellText(o.rows.find(x => x.title === "Arrival"), "field:POV") === "Mara", "a field column shows each item's value");
            o.setCell(o.rows.find(x => x.title === "The Keeper"), "field:POV", "Tobias");
            check(Api.get("nodeInfo", {}, rowId("The Keeper")).fields.POV === "Tobias", "editing a field cell saves it");
            o.setCell(o.rows.find(x => x.title === "The Keeper"), "keywords", "storm, arrival");
            check(Api.get("nodeInfo", {}, rowId("The Keeper")).keywords.join("|") === "storm|arrival", "keywords are edited comma separated");
            o.toggleColumn("field:POV");
            check(!o.hasColumn("field:POV"), "the column can be hidden again");
            o.filterText = "mara";
            const titles = o.rows.map(x => x.title + (x.context ? "*" : ""));
            check(titles.indexOf("Arrival") >= 0 && titles.indexOf("The Storm*") >= 0 && titles.indexOf("The Keeper") < 0,
                  "a text filter shows matching items under their folders (" + titles + ")");
            o.clearFilter();
            Api.call("setField", rowId("Confession"), "field:POV", "Zed");
            o.filterText = "zed";
            check(o.matchCount === 1 && o.rows.some(x => x.title === "Confession" && !x.context), "it matches custom field values (" + o.rows.map(x => x.title) + ")");
            Api.call("setField", rowId("Confession"), "field:POV", "");
            o.clearFilter();
            const todo = o.meta.statuses.find(x => x.name === "To Do");
            o.filterStatus = todo.id;
            check(o.rows.filter(x => !x.context).every(x => x.status === todo.id) && o.matchCount >= 2, "a status filter shows only those items (" + o.matchCount + ")");
            o.filterLabel = "none";
            check(o.rows.filter(x => !x.context).every(x => !x.label && x.status === todo.id), "label and status filters combine");
            o.clearFilter();
            check(!o.filtering && o.rows.length === all, "clearing the filter shows everything again");
            Api.call("setField", rowId("Arrival"), "field:POV", ""); Api.call("setField", rowId("The Keeper"), "field:POV", ""); Api.call("setField", rowId("The Keeper"), "keywords", "");
        }],
        ["templates", () => {
            const t = Api.call("templates") || [];
            check(t.map(x => x.id).join(",") === "blank,novel,short-story,nonfiction", "New Project offers the templates (" + t.map(x => x.name) + ")");
            // Build one beside the sample and look at its shape, then go back.
            const meta = Api.get("meta", null), dir = meta.path.substring(0, meta.path.lastIndexOf("/"));
            Api.call("close");
            const made = Api.call("newProject", "file://" + dir, "Template Test", "", "novel");
            const acts = made !== undefined ? Api.get("children", [], Api.call("rootId", "manuscript")).map(x => x.title).join(",") : "";
            check(acts === "Act I,Act II,Act III", "a Novel starts with three acts (" + acts + ")");
            Api.call("close");
            win.openPath(meta.path);
            check(Api.get("meta", null).title === meta.title, "the sample opens again");
        }],
        ["spelling language", () => {
            const info = Api.call("spellLanguages");
            check(info && info.list.some(x => x.code === "en_US" && x.name === "English (US)"), "the installed dictionaries are listed, with names");
            const r = win.setSpellLanguage("en_US");
            check(Theme.spellLanguage === "en_US" && r && r.dictionary.indexOf("en_US") === 0, "choosing a language loads it (" + (r ? r.dictionary : "") + ")");
            check(Api.call("spellCheck", "colour") === false && Api.call("spellCheck", "Mara") === true, "US English rejects “colour” and still knows the project's names");
            const missing = win.setSpellLanguage("zz_ZZ");
            check(missing && missing.dictionary.length > 0, "a language that isn't installed falls back (" + (missing ? missing.dictionary : "") + ")");
            win.setSpellLanguage("");
            check(Theme.spellLanguage === "", "Automatic follows the system again");
        }],
        ["story bible", () => {
            const dir = Api.get("meta", null).path, base = "file://" + dir.substring(0, dir.lastIndexOf("/")) + "/selftest-bible";
            const bible = win.bibleRef();
            check(bible.target(base, 1) === base + ".html" && bible.target(base + ".md", 0) === base + ".md", "the file type picks the extension");
            const docx = bible.write(base + ".docx"), md = bible.write(base + ".md");
            check(docx && docx.endsWith(".docx") && md && md.endsWith(".md"), "the story bible exports as Word and Markdown (" + docx + ", " + md + ")");
        }],
        ["automatic backup", () => {
            const dir = Api.get("meta", null).path, folder = dir.substring(0, dir.lastIndexOf("/")) + "/selftest-auto";
            autoBackup.folder = folder; autoBackup.keep = 2; autoBackup.closeBackups = true;
            const r1 = autoBackup.run(true);
            check(r1 && !r1.skipped && /autobackup \d{4}-\d\d-\d\d \d{4}\.zip$/.test(r1.path), "an automatic backup is written (" + (r1 ? r1.path : "failed") + ")");
            const r2 = autoBackup.run(true);
            check(r2 && r2.skipped === true, "an unchanged project isn't backed up again");
            const k = rowId("The Keeper"), old = Api.call("text", k);
            Api.call("setText", k, old + " One more line.");
            const r3 = autoBackup.run(true);
            Api.call("setText", k, old);
            check(r3 && !r3.skipped, "a change makes a new automatic backup");
            autoBackup.closeBackups = false; autoBackup.folder = ""; autoBackup.keep = 10;
        }],
        ["restore zip", () => {
            const meta = Api.get("meta", null), dir = meta.path.substring(0, meta.path.lastIndexOf("/"));
            const zip = Api.call("backupZip", dir + "/selftest-restore.zip");
            const r = zip ? win.restoreZip("file://" + zip.path, "file://" + dir + "/restored") : null;
            check(r && r.path.indexOf("/restored/") > 0 && r.title === meta.title, "a zip backup restores into the chosen folder and opens (" + (r ? r.path : "failed") + ")");
            check(Api.get("binder", []).some(x => x.title === "Arrival"), "the restored project has its documents");
            win.openPath(meta.path);
            check(Api.get("meta", null).path === meta.path, "the original opens again");
        }],
        ["sprint", () => {
            ws().select(rowId("Arrival"), "editor");
            sprint.durationMin = 1; sprint.goal = 3; sprint.start();
        }],
        ["sprint", () => {
            const a = ed().firstArea();
            a.forceActiveFocus(); a.insert(a.length, " alpha beta gamma delta");
        }],
        ["sprint", () => {
            sprint.finish(false);
            check(sprint.lastSprint !== null && sprint.lastSprint.words === 4, "a sprint counts the words typed (" + (sprint.lastSprint ? sprint.lastSprint.words : "none") + ")");
            check(Api.get("sprints", null).count >= 1, "the sprint is saved");
            sprint.close();
        }],
        // Last: it adds a folder of twelve scenes to the sample.
        ["long composite", () => {
            const ms = Api.call("rootId", "manuscript"), f = Api.call("add", ms, "folder", "Many Scenes", true);
            for (let i = 1; i <= 12; ++i) {
                const d = Api.call("add", f, "text", "Part " + i, true);
                Api.call("setText", d, "Words of part " + i + ".");
            }
            ws().select(f, "editor");
            check(ed().docs.length === 13 && !ed().built && ed().firstArea() !== null, "a long composite shows its first parts at once and builds the rest after");
            check(ed().built, "anything that needs every part (find, word lists) builds the rest first");
        }],
        ["long composite", () => {
            ws().select(rowId("Many Scenes"), "corkboard");
            ws().viewMode = "editor";
        }],
        ["long composite", () => {
            const ed2 = ed();
            check(ed2.built && ed2.editors().length === 12 && ed2.editors()[11].text === "Words of part 12.", "and the rest arrive by themselves (the folder itself has no text) (" + ed2.editors().length + ")");
        }]
    ]

    Timer {
        id: runner
        interval: 700
        repeat: true
        onTriggered: {
            if (st.step >= st.steps.length) {
                stop();
                st.log((st.failures ? "SELFTEST FAILED: " : "SELFTEST OK: ") + st.passes + " passed, " + st.failures + " failed");
                Qt.exit(st.failures ? 1 : 0);
                return;
            }
            const s = st.steps[st.step++];
            st.current = s[0];
            try { s[1](); } catch (e) { st.check(false, "threw " + e); }
        }
    }
    function start() { runner.start(); }
}
