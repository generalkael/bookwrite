import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Project ▸ Character Grid…: who appears where. One row per character (or
// place), one column per top-level part of the manuscript (usually a
// chapter); each cell is shaded by how often that name comes up there
// (mentions.rs `presence`). Click a cell to open the first scene in that
// chapter that mentions them, with the name in the find bar.
Dialog {
    id: pd
    title: qsTr("Character Grid")
    modal: false
    width: Math.min(900, parent ? parent.width - 40 : 900)
    height: Math.min(600, parent ? parent.height - 40 : 600)
    standardButtons: Dialog.Close

    property string kind: "character"     // or "place"
    property var grid: ({ columns: [], rows: [] })
    property string hint: ""
    signal mentionRequested(string docId, string name)

    readonly property int maxCount: grid.rows.reduce((m, r) => Math.max(m, ...r.counts, 0), 0)
    readonly property int cell: 34
    readonly property int nameWidth: 170

    onAboutToShow: reload()
    onKindChanged: if (visible) reload()
    readonly property int rev: Wordloom.revision
    onRevChanged: if (visible) reload()

    function reload() { grid = Api.get("presence", { columns: [], rows: [] }, kind); }
    // Shade: a square-root scale, so a name mentioned twice still shows
    // next to one mentioned forty times.
    function shade(n) { return n <= 0 || maxCount <= 0 ? 0 : 0.15 + 0.85 * Math.sqrt(n / maxCount); }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            ButtonGroup { id: kindGroup }
            RadioButton { text: qsTr("Characters"); checked: pd.kind === "character"; ButtonGroup.group: kindGroup; onToggled: if (checked) pd.kind = "character" }
            RadioButton { text: qsTr("Places"); checked: pd.kind === "place"; ButtonGroup.group: kindGroup; onToggled: if (checked) pd.kind = "place" }
            Item { Layout.fillWidth: true }
            Label {
                color: Theme.subtext
                elide: Text.ElideRight
                Layout.maximumWidth: 420
                text: pd.hint || qsTr("Mentions per chapter: hover for numbers, click to go there")
            }
        }

        Label {
            Layout.fillWidth: true
            visible: pd.grid.rows.length === 0 || pd.grid.columns.length === 0
            wrapMode: Text.Wrap
            color: Theme.subtext
            text: pd.grid.columns.length === 0
                ? qsTr("The manuscript is empty.")
                : pd.kind === "character" ? qsTr("No characters yet: add them in the binder's Characters section.")
                                          : qsTr("No places yet: add them in the binder's Places section.")
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pd.grid.rows.length > 0 && pd.grid.columns.length > 0
            clip: true
            contentWidth: pd.nameWidth + (pd.grid.columns.length + 1) * pd.cell + 8
            contentHeight: (pd.grid.rows.length + 1) * pd.cell + 8
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}

            Column {
                // Column headings: chapter numbers (titles on hover), then Total.
                Row {
                    Item { width: pd.nameWidth; height: pd.cell }
                    Repeater {
                        model: pd.grid.columns
                        delegate: Label {
                            required property var modelData
                            required property int index
                            width: pd.cell; height: pd.cell
                            text: index + 1
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.subtext
                            font.bold: true
                            HoverHandler { onHoveredChanged: if (hovered) pd.hint = qsTr("%1: %2").arg(index + 1).arg(modelData.title) }
                        }
                    }
                    Label { width: pd.cell + 8; height: pd.cell; text: qsTr("All"); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: Theme.subtext; font.bold: true }
                }
                Repeater {
                    model: pd.grid.rows
                    delegate: Row {
                        id: gridRow
                        required property var modelData
                        Label {
                            width: pd.nameWidth; height: pd.cell
                            text: gridRow.modelData.title
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            color: gridRow.modelData.total ? Theme.text : Theme.subtext
                        }
                        Repeater {
                            model: gridRow.modelData.counts
                            delegate: Rectangle {
                                required property int modelData
                                required property int index
                                readonly property var first: gridRow.modelData.first[index]
                                width: pd.cell; height: pd.cell
                                color: "transparent"
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 3
                                    color: modelData > 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, pd.shade(modelData)) : Theme.panel
                                    border.width: cellHover.hovered && modelData > 0 ? 2 : 0
                                    border.color: Theme.text
                                }
                                Label {
                                    anchors.centerIn: parent
                                    visible: modelData > 0
                                    text: modelData
                                    font.pixelSize: 11
                                    color: pd.shade(modelData) > 0.6 ? "white" : Theme.text
                                }
                                HoverHandler {
                                    id: cellHover
                                    cursorShape: modelData > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onHoveredChanged: if (hovered) pd.hint = modelData > 0
                                        ? (modelData === 1 ? qsTr("%1 in %2: 1 mention") : qsTr("%1 in %2: %3 mentions")).arg(gridRow.modelData.title).arg(pd.grid.columns[index].title).arg(modelData)
                                        : qsTr("%1 isn't in %2").arg(gridRow.modelData.title).arg(pd.grid.columns[index].title)
                                }
                                TapHandler { enabled: modelData > 0 && first !== null; onTapped: pd.mentionRequested(first[0], first[1]) }
                            }
                        }
                        Label {
                            width: pd.cell + 8; height: pd.cell
                            text: gridRow.modelData.total
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.subtext
                        }
                    }
                }
            }
        }
    }
}
