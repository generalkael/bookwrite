pragma Singleton
import QtQuick
import com.wordloom.app

// Thin wrapper over the Rust controller: JSON in, JSON out.
QtObject {
    id: api

    signal failed(string method, string message)
    signal notice(string message)

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
            api.failed(method, r.error);
            return undefined;
        }
        return r.result;
    }

    // Same, but quietly returns `fallback` if no project is open.
    function get(method, fallback, ...args) {
        if (!Wordloom.projectOpen) return fallback;
        const v = call(method, ...args);
        return v === undefined ? fallback : v;
    }

    function say(message) { api.notice(message); }

    function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }

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
