pragma Singleton
import QtQuick

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
    property int pageWidth: 720
    property real lineHeight: 1.45

    readonly property int gap: 8
    readonly property int radius: 5

    function kindIcon(kind, role) {
        if (role === "manuscript") return "📚";
        if (role === "characters") return "👥";
        if (role === "places") return "🗺";
        if (role === "research") return "🔬";
        if (role === "notes") return "🗒";
        if (role === "trash") return "🗑";
        switch (kind) {
        case "folder": return "📁";
        case "character": return "👤";
        case "place": return "📍";
        case "research": return "📎";
        case "note": return "📝";
        default: return "📄";
        }
    }
}
