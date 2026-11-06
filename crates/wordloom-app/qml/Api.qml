pragma Singleton
import QtQuick
import com.wordloom.app

// Thin wrapper over the Rust controller: JSON in, JSON out.
QtObject {
    id: api

    signal failed(string method, string message)
    signal notice(string message)
    // Kind of the last failure ("damaged" when project.json can't be read
    // but a backup exists), so the UI can offer a fix.
    property string lastErrorKind: ""
    // A document's text was saved from one editor; others showing the same
    // document (split editor) reload it.
    signal textSaved(string id)
    // A word was added to the personal dictionary; editors redraw.
    signal spellingChanged()

    // Call a backend method. Returns the result, or `undefined` on failure
    // (and emits `failed`).
    function call(method, ...args) {
        const raw = Wordloom.call(method, JSON.stringify(args));
        let r;
        try {
            r = JSON.parse(raw);
        } catch (e) {
            api.failed(method, "Malformed reply: " + raw);
            return undefined;
        }
        if (!r.ok) {
            api.lastErrorKind = r.kind || "";
            api.failed(method, r.error);
            return undefined;
        }
        return r.result;
    }

    // For reads: returns `fallback` instead of the result if no project is
    // open or the call fails, without a toast. (A view can briefly ask about
    // an item that an undo just removed; that's not worth an error popup.
    // The failure is still logged to stderr by the controller.)
    function get(method, fallback, ...args) {
        if (!Wordloom.projectOpen) return fallback;
        try {
            const r = JSON.parse(Wordloom.call(method, JSON.stringify(args)));
            return r.ok ? r.result : fallback;
        } catch (e) {
            return fallback;
        }
    }

    function say(message) { api.notice(message); }

    function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }

    // 1536 → "1.5 KB"
    function fmtBytes(n) {
        const u = ["bytes", "KB", "MB", "GB"];
        let i = 0;
        while (n >= 1024 && i < u.length - 1) { n /= 1024; ++i; }
        return (i === 0 ? n : n.toFixed(1)) + " " + u[i];
    }
    function fmtNumber(n) { return Number(n || 0).toLocaleString(Qt.locale(), 'f', 0); }

    // Convert a timeline unit index into a ruler label.
    function unitLabel(tl, n) {
        if (tl && tl.calendar_start && /^day/i.test(tl.unit_name)) {
            const d = new Date(tl.calendar_start + "T00:00:00");
            d.setDate(d.getDate() + n);
            return d.toLocaleDateString(Qt.locale(), "d MMM yyyy");
        }
        return (tl ? tl.unit_name : "Day") + " " + n;
    }
}
