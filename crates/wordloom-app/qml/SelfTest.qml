import QtQuick
import com.wordloom.app

// `wordloom --sample=DIR --selftest`: drives the real UI through checks for
// bugs fixed in the past, prints PASS / FAIL lines and exits with status 1
// if anything failed. CI runs it on every push.
Item {
    id: st
    property var win                     // the ApplicationWindow
    property var history                 // HistoryWindow
    property var sprint                  // SprintDialog
    property int step: 0
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
