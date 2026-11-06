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
    // With the split open: this pane is the one binder picks go to.
    property bool targeted: false
    property var activeArea: null      // the TextArea being typed in
    readonly property bool hasFile: node !== null && !!node.file
    signal openRequested(string id)
    signal swapRequested()
    signal closeRequested()
    // The user started typing in (or clicked into) this editor.
    signal editorFocused()

    readonly property int rev: Wordloom.revision
    onRevChanged: { rebuild(false); reloadNames(); }
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

    // ---- Name completion: typing the start of a character or place name
    // ("Tob") offers the whole name ("Tobias Wren"); Tab takes it, ↑ ↓
    // choose, Esc dismisses. Names come from wordloom-core (mentions.rs).
    property var nameList: []
    property var completions: []
    property int completionIndex: 0
    property int completionStart: 0
    property var completionArea: null
    function reloadNames() { nameList = Theme.completeNames ? Api.get("nameList", []) : []; }
    Component.onCompleted: reloadNames()
    Connections { target: Theme; function onCompleteNamesChanged() { ev.reloadNames(); ev.hideCompletion(); } }
    function isLetter(c) { return c !== undefined && c !== "" && (c.toLowerCase() !== c.toUpperCase() || c === "'" || c === "’"); }
    function hideCompletion() { completions = []; completionArea = null; }
    function updateCompletion(a) {
        if (!Theme.completeNames || !a || !a.activeFocus || a.selectionStart !== a.selectionEnd || nameList.length === 0) { hideCompletion(); return; }
        const p = a.cursorPosition, t = a.text;
        if (isLetter(t[p])) { hideCompletion(); return; }          // in the middle of a word
        // The last few words before the caret, on this line.
        let s = p;
        while (s > 0 && isLetter(t[s - 1])) --s;
        if (p - s < 2) { hideCompletion(); return; }
        const starts = [s];
        let k = s;
        for (let w = 0; w < 2; ++w) {
            if (k < 2 || t[k - 1] !== " " || !isLetter(t[k - 2])) break;
            k -= 1;
            while (k > 0 && isLetter(t[k - 1])) --k;
            starts.push(k);
        }
        // Longest run of words that starts a name; it must begin with a capital.
        for (let i = starts.length - 1; i >= 0; --i) {
            const tail = t.substring(starts[i], p), low = tail.toLowerCase();
            if (tail[0] === tail[0].toLowerCase() || (i === 0 && tail.length < 3)) continue;
            const hits = nameList.filter(n => n.length > tail.length && n.toLowerCase().startsWith(low));
            if (hits.length) {
                hits.sort((x, y) => x.length - y.length || x.localeCompare(y));
                completions = hits.slice(0, 6);
                completionIndex = 0;
                completionStart = starts[i];
                completionArea = a;
                return;
            }
        }
        hideCompletion();
    }
    function acceptCompletion() {
        const a = completionArea;
        if (!a || !completions.length) return false;
        const name = completions[completionIndex];
        const p = a.cursorPosition;
        a.remove(completionStart, p);
        a.insert(completionStart, name);
        a.cursorPosition = completionStart + name.length;
        hideCompletion();
        return true;
    }
    // Keys the suggestion list takes while it is showing.
    function completionKey(e) {
        if (!completions.length) return false;
        if (e.key === Qt.Key_Tab) return acceptCompletion();
        if (e.key === Qt.Key_Down) { completionIndex = (completionIndex + 1) % completions.length; return true; }
        if (e.key === Qt.Key_Up) { completionIndex = (completionIndex + completions.length - 1) % completions.length; return true; }
        if (e.key === Qt.Key_Escape) { hideCompletion(); return true; }
        return false;
    }

    // ---- Smart punctuation as you type: the rules of wordloom-core's
    // smart.rs. Returns true if it handled the key.
    function opensQuote(prev, next) {
        if (prev === "") return true;
        // After a dash it opens only before a letter or digit ("Wait—" closes).
        if (prev === "—" || prev === "–" || prev === "-") return next !== "" && (/[0-9]/.test(next) || next.toLowerCase() !== next.toUpperCase());
        return /[\s(\[{“‘\/]/.test(prev);
    }
    function smartKey(a, e) {
        if (!Theme.smartPunctuation || (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return false;
        const t = e.text;
        if (t !== '"' && t !== "'" && t !== "-" && t !== ".") return false;
        const s = a.selectionStart, end = a.selectionEnd;
        const prev = s > 0 ? a.getText(s - 1, s) : "";
        const next = end < a.length ? a.getText(end, end + 1) : "";
        // Not inside a {>> comment <<} on this line.
        const ls = lineStart(a.text, s), lineBefore = a.text.substring(ls, s);
        if (lineBefore.lastIndexOf("{>>") > lineBefore.lastIndexOf("<<}")) return false;
        let ins = null, back = 0;
        if (t === '"') ins = opensQuote(prev, next) ? "“" : "”";
        else if (t === "'") ins = opensQuote(prev, next) ? "‘" : "’";
        else if (t === "-" && prev === "-") {
            // "--" in prose is an em dash; a line of dashes is a scene break.
            if (/^\s*-+$/.test(lineBefore)) return false;
            ins = "—"; back = 1;
        } else if (t === "-" && prev === "—") {
            return true;   // "---" stays one dash
        } else if (t === "." && s >= 2 && a.getText(s - 2, s) === "..") {
            ins = "…"; back = 2;
        }
        if (ins === null) return false;
        if (end > s) a.remove(s, end);
        if (back) a.remove(s - back, s);
        a.insert(s - back, ins);
        a.cursorPosition = s - back + ins.length;
        return true;
    }
    // Edit ▸ Convert to Smart Punctuation: every part of this document.
    function smartenAll() {
        let changed = 0;
        for (const a of editors()) {
            const t = Api.get("smarten", a.text, a.text);
            if (t !== a.text) { a.remove(0, a.length); a.insert(0, t); ++changed; }
        }
        return changed;
    }

    // ---- Inline comments, {>> like this <<}: notes left in the text that
    // word counts, compile and reading mode ignore (core: comments.rs).
    readonly property var commentPattern: /\{>>[^\n]*?<<\}/g
    function insertComment() {
        const a = activeArea;
        if (!a) return;
        const p = a.selectionEnd, t = a.text;
        const lead = p > 0 && !/\s/.test(t[p - 1]) ? " " : "";
        a.insert(p, lead + "{>>  <<}");
        a.select(p + lead.length + 4, p + lead.length + 4);
        a.forceActiveFocus();
    }
    // Select the `n`th comment of document `docId` (as listed in Details).
    function showComment(docId, n) {
        for (let i = 0; i < rep.count; ++i) {
            const it = rep.itemAt(i);
            if (!it || it.docId !== docId) continue;
            const a = it.editor;
            const re = new RegExp(commentPattern.source, "g");
            let m, k = 0;
            while ((m = re.exec(a.text)) !== null) {
                if (k++ === n) {
                    activeArea = a;
                    a.forceActiveFocus();
                    a.select(m.index, m.index + m[0].length);
                    Qt.callLater(revealCursor, a, true);
                    return true;
                }
            }
        }
        return false;
    }

    // Scroll so the caret in `a` is visible (or centred, in typewriter mode).
    function revealCursor(a, force) {
        if (!a || (!a.activeFocus && !force)) return;
        const f = scroller.contentItem;            // the ScrollView's Flickable
        const r = a.cursorRectangle;
        const y = a.mapToItem(f.contentItem, 0, r.y).y;
        const maxY = Math.max(0, f.contentHeight - f.height);
        if (typewriter) {
            f.contentY = Math.min(maxY, Math.max(0, y + r.height / 2 - f.height / 2));
            return;
        }
        const margin = Math.min(60, f.height / 4);
        if (y < f.contentY + margin)
            f.contentY = Math.max(0, y - margin);
        else if (y + r.height > f.contentY + f.height - margin)
            f.contentY = Math.min(maxY, y + r.height - f.height + margin);
    }

    // ---- hooks for `--selftest` ----
    function firstArea() { const e = editors(); return e.length ? e[0] : null; }
    function lineBarRef() { return lineBar; }
    function testInfo() {
        const f = scroller.contentItem, a = activeArea;
        return {
            contentY: f.contentY, viewH: f.height, pageW: page.width, paneW: scroller.width,
            caretY: a ? a.mapToItem(f.contentItem, 0, a.cursorRectangle.y).y : -1,
            caretH: a ? a.cursorRectangle.height : 0
        };
    }

    // ---- Find & replace in this document (all parts, in composite mode).
    property bool findOpen: false
    property alias findText: findField.text
    property alias replaceText: replaceField.text
    property bool replaceOpen: false
    property bool matchCase: false
    // Only whole words match by default, so replacing "the" leaves "then" alone.
    property bool wholeWords: true
    property int matchCount: 0
    property int matchNumber: 0          // 1-based index of the selected match, 0 if none
    function editors() {
        const out = [];
        for (let i = 0; i < rep.count; ++i) { const it = rep.itemAt(i); if (it && it.editor.visible) out.push(it.editor); }
        return out;
    }
    function allMatches() {
        const q = findField.text;
        const out = [];
        if (!q) return out;
        const needle = matchCase ? q : q.toLowerCase();
        // A letter has distinct cases; Qt's JS engine lacks \p{L} in regexes.
        const wordChar = { test: (c) => c.toLowerCase() !== c.toUpperCase() || /[0-9_'’]/.test(c) };
        editors().forEach((a, part) => {
            const hay = matchCase ? a.text : a.text.toLowerCase();
            for (let i = hay.indexOf(needle); i >= 0; i = hay.indexOf(needle, i + needle.length)) {
                if (wholeWords && ((i > 0 && wordChar.test(hay[i - 1])) || (i + needle.length < hay.length && wordChar.test(hay[i + needle.length]))))
                    continue;
                out.push({ part: part, start: i });
            }
        });
        return out;
    }
    function openFind(withReplace) {
        if (hasFile) return;
        if (preview) preview = false;
        findOpen = true;
        replaceOpen = withReplace;
        const a = activeArea;
        if (a && a.selectedText && a.selectedText.indexOf("\u2029") < 0 && a.selectedText.indexOf("\n") < 0)
            findField.text = a.selectedText;
        findField.forceActiveFocus();
        findField.selectAll();
        findStep(0);
    }
    function closeFind() {
        findOpen = false;
        if (activeArea) activeArea.forceActiveFocus();
    }
    // dir 1: next match after the selection; -1: previous; 0: the match at or after the caret.
    function findStep(dir) {
        const ms = allMatches();
        matchCount = ms.length;
        if (!ms.length) { matchNumber = 0; return; }
        const eds = editors();
        const cur = Math.max(0, eds.indexOf(activeArea));
        const a = eds[cur];
        const pos = !a ? 0 : dir < 0 ? a.selectionStart : dir > 0 ? a.selectionEnd : a.selectionStart;
        let i;
        if (dir < 0) {
            i = -1;
            for (let k = ms.length - 1; k >= 0; --k) if (ms[k].part < cur || (ms[k].part === cur && ms[k].start < pos)) { i = k; break; }
            if (i < 0) i = ms.length - 1;
        } else {
            i = ms.findIndex(m => m.part > cur || (m.part === cur && m.start >= pos));
            if (i < 0) i = 0;
        }
        selectMatch(ms[i], eds);
        matchNumber = i + 1;
    }
    function selectMatch(m, eds) {
        const a = eds[m.part];
        activeArea = a;
        a.select(m.start, m.start + findField.text.length);
        Qt.callLater(revealCursor, a, true);
    }
    // Replace the selected match (if the selection is one) and move on.
    function replaceOne() {
        const a = activeArea, q = findField.text;
        if (a && q && a.selectionEnd - a.selectionStart === q.length
                && (matchCase ? a.selectedText === q : a.selectedText.toLowerCase() === q.toLowerCase())) {
            const s = a.selectionStart;
            a.remove(s, s + q.length);
            a.insert(s, replaceField.text);
            a.select(s + replaceField.text.length, s + replaceField.text.length);
        }
        findStep(1);
    }
    function replaceAll() {
        const q = findField.text;
        if (!q) return;
        const ms = allMatches(), eds = editors();
        for (let k = ms.length - 1; k >= 0; --k) {
            const a = eds[ms[k].part];
            a.remove(ms[k].start, ms[k].start + q.length);
            a.insert(ms[k].start, replaceField.text);
        }
        Api.say(qsTr("Replaced %1 occurrence(s) in this document").arg(ms.length));
        findStep(0);
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

        // Editor header. When the pane is narrow, the view buttons (and, narrower
        // still, the format buttons) fold into a "⋯" menu so the title stays visible.
        Rectangle {
            id: header
            readonly property bool compact: width < 680
            readonly property bool tiny: width < 470
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            visible: !ev.focusMode && ev.node !== null
            color: Theme.window
            Rectangle {
                visible: ev.targeted
                width: parent.width; height: 2
                color: Theme.accent
                ToolTip.visible: targetHover.hovered
                ToolTip.text: qsTr("Items you pick in the binder open here")
                HoverHandler { id: targetHover }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                KindIcon { visible: ev.node !== null; kind: ev.node ? ev.node.kind : ""; role: ev.node ? (ev.node.role || "") : "" }
                Label { text: ev.node ? ev.node.title : ""; font.bold: true; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true; Layout.minimumWidth: 40 }
                Label { visible: ev.docs.length > 1 && !header.compact; text: qsTr("Composite · %1 parts").arg(ev.docs.length); color: Theme.subtext }
                ToolButton { visible: ev.hasFile; text: qsTr("Open in Default App"); onClicked: fileViewer.openExternally() }
                // Format bar
                Repeater {
                    model: ev.hasFile || ev.preview || header.tiny ? [] : [
                        { label: "B", tip: qsTr("Bold (Ctrl+B)"), act: () => ev.toggleEmphasis(2), bold: true },
                        { label: "I", tip: qsTr("Italic (Ctrl+I)"), act: () => ev.toggleEmphasis(1), italic: true },
                        { label: "H", tip: qsTr("Heading: none → # → ## → ###"), act: () => ev.cycleHeading(), bold: true },
                        { label: "“", tip: qsTr("Block quote"), act: () => ev.toggleQuote() },
                        { label: "* * *", tip: qsTr("Scene break"), act: () => ev.sceneBreak() },
                        { label: "{ }", tip: qsTr("Comment: a note to yourself that isn't exported or counted (Ctrl+Alt+M)"), act: () => ev.insertComment() }
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
                ToolSeparator { visible: !ev.hasFile && !ev.preview && !header.tiny }
                ToolButton { visible: !ev.hasFile && !header.compact; text: qsTr("Preview"); checkable: true; checked: ev.preview; onToggled: { ev.flush(); ev.preview = checked; } ToolTip.visible: hovered; ToolTip.text: qsTr("Render Markdown formatting") }
                ToolButton { visible: !ev.hasFile && !header.compact; text: qsTr("Typewriter"); checkable: true; checked: ev.typewriter; onToggled: ev.typewriter = checked; ToolTip.visible: hovered; ToolTip.text: qsTr("Keep the current line centred") }
                ToolButton { visible: !ev.hasFile && !header.compact; text: "A−"; onClicked: Theme.editorSize = Math.max(9, Theme.editorSize - 1) }
                ToolButton { visible: !ev.hasFile && !header.compact; text: "A+"; onClicked: Theme.editorSize = Math.min(40, Theme.editorSize + 1) }
                ToolButton {
                    visible: !ev.hasFile && !header.compact; text: "⇔"
                    // Fit → 560 → 740 → 920 → 1100 → Fit
                    onClicked: Theme.pageWidth = Theme.pageWidth === 0 ? 560 : Theme.pageWidth >= 1100 ? 0 : Theme.pageWidth + 180
                    ToolTip.visible: hovered
                    ToolTip.text: Theme.pageWidth === 0 ? qsTr("Page width: fit the window (click for a fixed width)") : qsTr("Page width: %1 px (click to change)").arg(Theme.pageWidth)
                }
                ToolButton {
                    id: moreButton
                    visible: !ev.hasFile && header.compact
                    text: "⋯"
                    focusPolicy: Qt.NoFocus
                    onClicked: moreMenu.popup(moreButton, 0, moreButton.height)
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("More editor options")
                    Menu {
                        id: moreMenu
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Bold"); enabled: ev.activeArea !== null; onTriggered: ev.toggleEmphasis(2) }
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Italic"); enabled: ev.activeArea !== null; onTriggered: ev.toggleEmphasis(1) }
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Heading"); enabled: ev.activeArea !== null; onTriggered: ev.cycleHeading() }
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Block Quote"); enabled: ev.activeArea !== null; onTriggered: ev.toggleQuote() }
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Scene Break"); enabled: ev.activeArea !== null; onTriggered: ev.sceneBreak() }
                        MenuItem { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0; text: qsTr("Comment"); enabled: ev.activeArea !== null; onTriggered: ev.insertComment() }
                        MenuSeparator { visible: header.tiny && !ev.preview; height: visible ? implicitHeight : 0 }
                        MenuItem { text: qsTr("Preview"); checkable: true; checked: ev.preview; onTriggered: { ev.flush(); ev.preview = !ev.preview; } }
                        MenuItem { text: qsTr("Typewriter Scrolling"); checkable: true; checked: ev.typewriter; onTriggered: ev.typewriter = !ev.typewriter }
                        MenuSeparator {}
                        MenuItem { text: qsTr("Larger Text"); onTriggered: Theme.editorSize = Math.min(40, Theme.editorSize + 1) }
                        MenuItem { text: qsTr("Smaller Text"); onTriggered: Theme.editorSize = Math.max(9, Theme.editorSize - 1) }
                        MenuItem {
                            text: Theme.pageWidth === 0 ? qsTr("Page Width: Fit (click to change)") : qsTr("Page Width: %1 px (click to change)").arg(Theme.pageWidth)
                            onTriggered: Theme.pageWidth = Theme.pageWidth === 0 ? 560 : Theme.pageWidth >= 1100 ? 0 : Theme.pageWidth + 180
                        }
                    }
                }
                ToolSeparator { visible: ev.secondary }
                ToolButton { visible: ev.secondary; text: "⇄"; onClicked: ev.swapRequested(); ToolTip.visible: hovered; ToolTip.text: qsTr("Swap with the main editor") }
                ToolButton { visible: ev.secondary; text: "✕"; onClicked: ev.closeRequested(); ToolTip.visible: hovered; ToolTip.text: qsTr("Close split (Ctrl+\\)") }
            }
        }

        // Find / replace bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: findCol.implicitHeight + 10
            visible: ev.findOpen && !ev.hasFile && !ev.focusMode
            color: Theme.panel
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
            ColumnLayout {
                id: findCol
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 12
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        id: findField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Find in this document")
                        selectByMouse: true
                        onTextEdited: ev.findStep(0)
                        Keys.onReturnPressed: (e) => ev.findStep(e.modifiers & Qt.ShiftModifier ? -1 : 1)
                        Keys.onEnterPressed: (e) => ev.findStep(e.modifiers & Qt.ShiftModifier ? -1 : 1)
                        Keys.onEscapePressed: ev.closeFind()
                    }
                    Label {
                        color: findField.text && ev.matchCount === 0 ? Theme.danger : Theme.subtext
                        text: !findField.text ? "" : ev.matchCount === 0 ? qsTr("No matches") : qsTr("%1 of %2").arg(ev.matchNumber).arg(ev.matchCount)
                    }
                    ToolButton { text: "▲"; focusPolicy: Qt.NoFocus; enabled: ev.matchCount > 0; onClicked: ev.findStep(-1); ToolTip.visible: hovered; ToolTip.text: qsTr("Previous (Shift+Enter, Shift+F3)") }
                    ToolButton { text: "▼"; focusPolicy: Qt.NoFocus; enabled: ev.matchCount > 0; onClicked: ev.findStep(1); ToolTip.visible: hovered; ToolTip.text: qsTr("Next (Enter, F3)") }
                    ToolButton { text: qsTr("Whole words"); checkable: true; checked: ev.wholeWords; focusPolicy: Qt.NoFocus; onToggled: { ev.wholeWords = checked; ev.findStep(0); } ToolTip.visible: hovered; ToolTip.text: qsTr("Match whole words only (so “the” doesn’t match “then”)") }
                    ToolButton { text: "Aa"; checkable: true; checked: ev.matchCase; focusPolicy: Qt.NoFocus; onToggled: { ev.matchCase = checked; ev.findStep(0); } ToolTip.visible: hovered; ToolTip.text: qsTr("Match case") }
                    ToolButton { text: ev.replaceOpen ? qsTr("Hide Replace") : qsTr("Replace…"); focusPolicy: Qt.NoFocus; onClicked: ev.replaceOpen = !ev.replaceOpen }
                    ToolButton { text: "✕"; focusPolicy: Qt.NoFocus; onClicked: ev.closeFind(); ToolTip.visible: hovered; ToolTip.text: qsTr("Close (Esc)") }
                }
                RowLayout {
                    visible: ev.replaceOpen
                    Layout.fillWidth: true
                    TextField {
                        id: replaceField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Replace with")
                        selectByMouse: true
                        Keys.onReturnPressed: ev.replaceOne()
                        Keys.onEnterPressed: ev.replaceOne()
                        Keys.onEscapePressed: ev.closeFind()
                    }
                    Button { text: qsTr("Replace"); focusPolicy: Qt.NoFocus; enabled: ev.matchCount > 0; onClicked: ev.replaceOne() }
                    Button { text: qsTr("Replace All"); focusPolicy: Qt.NoFocus; enabled: ev.matchCount > 0; onClicked: ev.replaceAll() }
                }
            }
            Shortcut { sequences: ["F3"]; enabled: ev.findOpen; onActivated: ev.findStep(1) }
            Shortcut { sequences: ["Shift+F3"]; enabled: ev.findOpen; onActivated: ev.findStep(-1) }
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
                    // Fills the pane unless a fixed page width is chosen (⇔). In focus
                    // mode "fit" keeps a readable column instead of the whole screen.
                    width: Theme.pageWidth > 0 ? Math.min(Theme.pageWidth + 2 * pad, parent.width - 24)
                        : ev.focusMode ? Math.min(860 + 2 * pad, parent.width - 24)
                        : parent.width - 24
                    // At least as tall as the visible area, so the paper fills the pane.
                    height: Math.max(col.height + 2 * pad, scroller.height - 48)
                    // Inner margin; smaller on a narrow page so the text column isn't a sliver.
                    readonly property int pad: width < 520 ? 20 : 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    color: Theme.paper
                    border.color: Theme.border
                    radius: 3
                    visible: ev.node !== null

                    // The current-line bar (View ▸ Highlight Current Line): behind
                    // the text, across the page, on the caret's visual line.
                    Rectangle {
                        id: lineBar
                        readonly property var a: ev.activeArea
                        visible: Theme.lineHighlight && !ev.preview && a !== null && a.activeFocus && a.visible
                        x: 1
                        width: page.width - 2
                        // mapToItem isn't a live binding: depend on col.height so the bar
                        // moves when text above it (another composite part) grows.
                        y: { col.height; return a ? a.mapToItem(page, 0, a.cursorRectangle.y).y : 0; }
                        height: a ? a.cursorRectangle.height : 0
                        color: Theme.lineHighlightColor
                    }
                    Column {
                        id: col
                        x: page.pad
                        y: page.pad
                        width: page.width - 2 * page.pad
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

    // The name suggestions, just under the caret. Not a Popup, so typing
    // carries on in the editor.
    Rectangle {
        id: completionBox
        visible: ev.completions.length > 0 && ev.completionArea !== null
        z: 50
        readonly property point at: {
            const a = ev.completionArea;
            if (!a) return Qt.point(0, 0);
            const r = a.cursorRectangle;
            return a.mapToItem(ev, r.x, r.y + r.height + 4);
        }
        x: Math.max(4, Math.min(at.x, ev.width - width - 4))
        y: at.y + height > ev.height - 4 ? at.y - height - (ev.completionArea ? ev.completionArea.cursorRectangle.height + 8 : 0) : at.y
        TextMetrics { id: widest; font.bold: true; text: ev.completions.reduce((w, n) => n.length > w.length ? n : w, "") }
        width: Math.max(160, widest.advanceWidth + 64)
        height: completionCol.implicitHeight + 8
        radius: 4
        color: Theme.panel
        border.color: Theme.border
        Column {
            id: completionCol
            x: 4; y: 4
            Repeater {
                model: ev.completions
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: completionBox.width - 8
                    height: 24
                    radius: 3
                    color: index === ev.completionIndex ? Theme.accentSoft : "transparent"
                    Label { anchors.verticalCenter: parent.verticalCenter; x: 6; text: modelData; textFormat: Text.PlainText; color: Theme.text; font.bold: index === ev.completionIndex }
                    Label { visible: index === ev.completionIndex; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 6; text: qsTr("Tab"); color: Theme.subtext; font.pixelSize: 10 }
                    TapHandler { onTapped: { ev.completionIndex = index; ev.acceptCompletion(); } }
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
        readonly property alias editor: area
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
            function tintAt(pos) { return styler.backgroundAt(pos); }
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
            onTextChanged: { if (!de.loading) { saveTimer.restart(); if (activeFocus) ev.updateCompletion(area); } }
            onActiveFocusChanged: { if (activeFocus) { ev.activeId = de.docId; ev.activeArea = area; ev.editorFocused(); } else { de.flush(); if (ev.completionArea === area) ev.hideCompletion(); } }

            // ---- right-click menu with spelling suggestions. Qt 6.9+ has a
            // built-in context menu, which we replace with ours; older Qt has
            // none, so a right-click handler opens it instead.
            property bool nativeMenu: false
            property int wordStart: 0
            property int wordEnd: 0
            property string word: ""
            property bool misspelled: false
            property var suggestions: []
            Component.onCompleted: { try { area.ContextMenu.menu = editMenu; area.nativeMenu = true; } catch (e) {} }
            HoverHandler { id: areaHover }
            TapHandler {
                acceptedButtons: Qt.RightButton
                enabled: !area.nativeMenu
                onTapped: (ep) => { area.prepareMenu(ep.position); editMenu.popup(); }
            }
            function prepareMenu(pos) {
                const p = area.positionAt(pos.x, pos.y);
                const t = area.text;
                const isWord = (c) => c !== undefined && (c.toLowerCase() !== c.toUpperCase() || c === "'" || c === "’");
                let s = p, e = p;
                while (s > 0 && isWord(t[s - 1])) --s;
                while (e < t.length && isWord(t[e])) ++e;
                while (s < e && !(t[s].toLowerCase() !== t[s].toUpperCase())) ++s;   // no leading apostrophes
                while (e > s && !(t[e - 1].toLowerCase() !== t[e - 1].toUpperCase())) --e;
                wordStart = s; wordEnd = e;
                word = t.substring(s, e);
                misspelled = Theme.spellCheck && word.length > 1 && !Api.get("spellCheck", true, word);
                suggestions = misspelled ? Api.get("spellSuggest", [], word).slice(0, 6) : [];
            }
            function replaceWord(w) {
                area.remove(wordStart, wordEnd);
                area.insert(wordStart, w);
            }
            Menu {
                id: editMenu
                onAboutToShow: if (area.nativeMenu) area.prepareMenu(areaHover.point.position)
                Repeater {
                    model: 6
                    delegate: MenuItem {
                        required property int index
                        visible: index < area.suggestions.length
                        height: visible ? implicitHeight : 0
                        text: visible ? area.suggestions[index] : ""
                        font.bold: true
                        onTriggered: area.replaceWord(area.suggestions[index])
                    }
                }
                MenuItem { visible: area.misspelled && area.suggestions.length === 0; height: visible ? implicitHeight : 0; text: qsTr("No suggestions"); enabled: false }
                MenuItem {
                    visible: area.misspelled
                    height: visible ? implicitHeight : 0
                    text: qsTr("Add “%1” to Dictionary").arg(area.word)
                    onTriggered: { Api.call("spellAdd", area.word); Api.spellingChanged(); }
                }
                MenuSeparator { visible: area.misspelled; height: visible ? implicitHeight : 0 }
                MenuItem { text: qsTr("Cut"); enabled: area.selectedText.length > 0; onTriggered: area.cut() }
                MenuItem { text: qsTr("Copy"); enabled: area.selectedText.length > 0; onTriggered: area.copy() }
                MenuItem { text: qsTr("Paste"); enabled: area.canPaste; onTriggered: area.paste() }
                MenuSeparator {}
                MenuItem { text: qsTr("Select All"); onTriggered: area.selectAll() }
            }
            Connections { target: Api; function onSpellingChanged() { styler.rehighlight(); } }
            Keys.onPressed: (e) => {
                if (ev.completionKey(e)) { e.accepted = true; return; }
                if (ev.smartKey(area, e)) { e.accepted = true; return; }
                if ((e.modifiers & Qt.ControlModifier) && !(e.modifiers & (Qt.ShiftModifier | Qt.AltModifier))) {
                    if (e.key === Qt.Key_B) { ev.activeArea = area; ev.toggleEmphasis(2); e.accepted = true; }
                    else if (e.key === Qt.Key_I) { ev.activeArea = area; ev.toggleEmphasis(1); e.accepted = true; }
                }
            }
            MarkdownStyler {
                id: styler
                document: area.textDocument
                enabled: Theme.styledMarkdown
                spellCheck: Theme.spellCheck
                repeats: Theme.highlightRepeats
                repeatColor: Theme.dark ? Qt.rgba(0.35, 0.6, 1, 0.26) : Qt.rgba(0.3, 0.55, 0.95, 0.22)
                markColor: Theme.dark ? "#6f6d68" : "#b3afa6"
                quoteColor: Theme.subtext
                commentColor: Theme.dark ? Qt.rgba(0.85, 0.68, 0.2, 0.24) : Qt.rgba(0.96, 0.78, 0.2, 0.34)
            }
            onCursorPositionChanged: if (activeFocus) {
                ev.activeCursor = cursorPosition;
                // Moving away (click, arrow keys) closes the suggestions.
                if (ev.completionArea === area && (cursorPosition < ev.completionStart || ev.isLetter(text[cursorPosition]))) ev.hideCompletion();
            }
            // Keep the caret on screen as you type, move or the text reflows.
            // Deferred so the page has grown to fit a new line first.
            onCursorRectangleChanged: if (activeFocus) Qt.callLater(ev.revealCursor, area)
            onHeightChanged: if (activeFocus) Qt.callLater(ev.revealCursor, area)
        }
        Text {
            visible: ev.preview
            Layout.fillWidth: true
            text: area.text.replace(ev.commentPattern, "")
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
