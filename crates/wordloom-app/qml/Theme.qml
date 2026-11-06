pragma Singleton
import QtQuick
import QtCore

// Colours and metrics shared by every view. Follows the system light/dark
// scheme; the user can force one with `forced`.
QtObject {
    id: theme

    property string forced: ""   // "", "light" or "dark"
    readonly property bool dark: forced === "dark"
        || (forced === "" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)

    readonly property color window: dark ? "#1f2023" : "#f3f1ec"
    readonly property color panel: dark ? "#26282c" : "#ebe8e1"
    readonly property color base: dark ? "#2d2f34" : "#ffffff"
    readonly property color text: dark ? "#e6e4df" : "#24231f"
    readonly property color subtext: dark ? "#9c9a94" : "#77746c"
    readonly property color border: dark ? "#3a3c42" : "#d6d2c8"
    readonly property color accent: "#c0703a"
    readonly property color accentSoft: dark ? "#4a3626" : "#f3dfcf"
    readonly property color selection: dark ? "#3e4a5c" : "#d7e3f4"
    readonly property color danger: "#d64545"
    readonly property color ok: "#5a9e5a"
    readonly property color cork: dark ? "#3b342b" : "#c9a97c"
    readonly property color card: dark ? "#34363b" : "#fffdf5"
    readonly property color cardLine: dark ? "#43464d" : "#e6eef7"
    readonly property color paper: dark ? "#25272b" : "#fffefb"
    readonly property color ink: dark ? "#dcd9d2" : "#1d1c19"

    property string editorFont: "Georgia"
    property int editorSize: 15
    // Text column width in pixels; 0 = fit the editor pane (the default).
    property int pageWidth: 0
    property real lineHeight: 1.45
    // Show Markdown styling (bold, headings, quotes…) while editing.
    property bool styledMarkdown: true
    // Underline misspelled words in the editor.
    property bool spellCheck: true
    // “Smart” quotes, dashes and ellipses as you type (EditorView.smartKey).
    property bool smartPunctuation: true
    // Suggest character and place names as you type (EditorView).
    property bool completeNames: true

    // Remembered between runs (~/.config/Wordloom/Wordloom.conf on Linux).
    property Settings prefs: Settings {
        category: "appearance"
        property alias theme: theme.forced
        property alias editorFont: theme.editorFont
        property alias editorSize: theme.editorSize
        property alias pageWidth: theme.pageWidth
        property alias styledMarkdown: theme.styledMarkdown
        property alias spellCheck: theme.spellCheck
        property alias smartPunctuation: theme.smartPunctuation
        property alias completeNames: theme.completeNames
    }

    readonly property int gap: 8
    readonly property int radius: 5

    // URL of the bundled SVG icon for an item kind or section root (see
    // KindIcon). Timeline track kinds (plotline, …) work too.
    function kindIcon(kind, role) {
        const roles = ["manuscript", "characters", "places", "research", "notes", "trash"];
        const kinds = { folder: "folder", character: "character", place: "place", research: "attachment", note: "note", plotline: "plotline" };
        const name = roles.indexOf(role) >= 0 ? role : (kinds[kind] || "text");
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }
}
