import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Right-hand inspector: metadata, notes, snapshots and timeline links for the
// selected item.
Rectangle {
    id: ip
    color: Theme.panel

    property string nodeId: ""
    property var node: null
    property var meta: ({ labels: [], statuses: [] })
    property var snaps: []
    property int snapIndex: -1
    signal openEvent()
    signal flushRequested()

    readonly property int rev: Wordloom.revision
    onRevChanged: meta = Api.get("labels", meta)
    onNodeIdChanged: { reloadSnapshots(); meta = Api.get("labels", meta); }
    Component.onCompleted: meta = Api.get("labels", meta)

    function reloadSnapshots() { snaps = nodeId ? Api.get("snapshots", [], nodeId) : []; snapIndex = -1; }
    function set(field, value) { if (node) Api.call("setField", node.id, field, value); }

    readonly property var suggestedFields: node
        ? (node.kind === "character" ? ["Role", "Age", "Appearance", "Goal", "Motivation", "Conflict", "Arc"]
           : node.kind === "place" ? ["Region", "Era", "Atmosphere", "Significance"]
           : node.kind === "text" ? ["POV", "Setting", "Time"] : [])
        : []
    readonly property var fieldKeys: {
        if (!node) return [];
        const keys = suggestedFields.slice();
        for (const k of Object.keys(node.fields || {})) if (keys.indexOf(k) < 0) keys.push(k);
        return keys;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: ip.node !== null

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: qsTr("Info") }
            TabButton { text: qsTr("Notes") }
            TabButton { text: qsTr("Snapshots") }
            TabButton { text: qsTr("Timeline") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ---------------- Info ----------------
            ScrollView {
                id: infoScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: infoScroll.availableWidth - 20
                    x: 10
                    spacing: 6

                    Item { Layout.preferredHeight: 4 }
                    Label { text: qsTr("Title"); color: Theme.subtext; font.pixelSize: 11 }
                    TextField {
                        Layout.fillWidth: true
                        text: ip.node ? ip.node.title : ""
                        enabled: ip.node && !ip.node.is_root
                        selectByMouse: true
                        onEditingFinished: if (ip.node && text !== ip.node.title) ip.set("title", text)
                    }

                    Label { text: qsTr("Synopsis"); color: Theme.subtext; font.pixelSize: 11 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        color: Theme.card
                        border.color: Theme.border
                        radius: 3
                        ScrollView {
                            anchors.fill: parent
                            TextArea {
                                text: ip.node ? ip.node.synopsis : ""
                                wrapMode: TextEdit.Wrap
                                font.family: Theme.editorFont
                                color: Theme.ink
                                background: null
                                selectByMouse: true
                                placeholderText: qsTr("What happens here, in a line or two")
                                onActiveFocusChanged: if (!activeFocus && ip.node && text !== ip.node.synopsis) ip.set("synopsis", text)
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        Label { text: qsTr("Label"); color: Theme.subtext }
                        ComboBox {
                            Layout.fillWidth: true
                            model: [qsTr("No Label")].concat(ip.meta.labels.map(l => l.name))
                            currentIndex: ip.node ? 1 + ip.meta.labels.findIndex(l => l.id === ip.node.label) : 0
                            onActivated: (i) => ip.set("label", i === 0 ? "" : ip.meta.labels[i - 1].id)
                        }
                        Label { text: qsTr("Status"); color: Theme.subtext }
                        ComboBox {
                            Layout.fillWidth: true
                            model: [qsTr("No Status")].concat(ip.meta.statuses.map(s => s.name))
                            currentIndex: ip.node ? 1 + ip.meta.statuses.findIndex(s => s.id === ip.node.status) : 0
                            onActivated: (i) => ip.set("status", i === 0 ? "" : ip.meta.statuses[i - 1].id)
                        }
                        Label { text: qsTr("Keywords"); color: Theme.subtext }
                        TextField {
                            Layout.fillWidth: true
                            text: ip.node ? ip.node.keywords.join(", ") : ""
                            placeholderText: qsTr("comma, separated")
                            onEditingFinished: if (ip.node && text !== ip.node.keywords.join(", ")) ip.set("keywords", text)
                        }
                        Label { text: qsTr("Target"); color: Theme.subtext }
                        TextField {
                            Layout.fillWidth: true
                            text: ip.node && ip.node.target_words ? String(ip.node.target_words) : ""
                            placeholderText: qsTr("words")
                            validator: IntValidator { bottom: 0 }
                            onEditingFinished: ip.set("target_words", text)
                        }
                    }
                    CheckBox {
                        text: qsTr("Include in compile")
                        checked: ip.node ? ip.node.include_in_compile : true
                        enabled: ip.node && !ip.node.is_root
                        onToggled: ip.set("include_in_compile", checked)
                    }

                    // Custom fields: character sheets, place sheets, scene facts.
                    Label {
                        visible: ip.fieldKeys.length > 0 || (ip.node && !ip.node.is_root)
                        text: ip.node && ip.node.kind === "character" ? qsTr("Character sheet")
                            : ip.node && ip.node.kind === "place" ? qsTr("Place sheet") : qsTr("Custom fields")
                        font.bold: true
                        color: Theme.text
                        Layout.topMargin: 8
                    }
                    Repeater {
                        model: ip.fieldKeys
                        delegate: ColumnLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: modelData; color: Theme.subtext; font.pixelSize: 11 }
                            TextField {
                                Layout.fillWidth: true
                                text: ip.node && ip.node.fields[modelData] ? ip.node.fields[modelData] : ""
                                onEditingFinished: if (ip.node && text !== (ip.node.fields[modelData] || "")) ip.set("field:" + modelData, text)
                            }
                        }
                    }
                    RowLayout {
                        visible: ip.node && !ip.node.is_root
                        Layout.fillWidth: true
                        TextField { id: newKey; Layout.fillWidth: true; placeholderText: qsTr("New field name") }
                        Button { text: "＋"; enabled: newKey.text.trim().length > 0; onClicked: { ip.set("field:" + newKey.text.trim(), "—"); newKey.text = ""; } }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 6 }
                    Label {
                        Layout.fillWidth: true
                        color: Theme.subtext
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        text: ip.node ? qsTr("%1 words here · %2 including children · %3 characters\nCreated %4\nModified %5")
                            .arg(Api.fmtNumber(ip.node.words)).arg(Api.fmtNumber(ip.node.total_words)).arg(Api.fmtNumber(ip.node.chars))
                            .arg(new Date(ip.node.created).toLocaleString(Qt.locale(), Locale.ShortFormat))
                            .arg(new Date(ip.node.modified).toLocaleString(Qt.locale(), Locale.ShortFormat)) : ""
                    }
                    Item { Layout.preferredHeight: 10 }
                }
            }

            // ---------------- Notes ----------------
            ColumnLayout {
                spacing: 4
                Label { text: qsTr("Document notes"); color: Theme.subtext; Layout.margins: 8 }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 8
                    TextArea {
                        text: ip.node ? ip.node.notes : ""
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        placeholderText: qsTr("Research, reminders, things to fix…")
                        background: Rectangle { color: Theme.card; border.color: Theme.border; radius: 3 }
                        color: Theme.ink
                        onActiveFocusChanged: if (!activeFocus && ip.node && text !== ip.node.notes) ip.set("notes", text)
                    }
                }
            }

            // ---------------- Snapshots ----------------
            ColumnLayout {
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    TextField { id: snapName; Layout.fillWidth: true; placeholderText: qsTr("Snapshot name (optional)") }
                    Button {
                        text: qsTr("Take")
                        onClicked: {
                            ip.flushRequested();
                            if (Api.call("takeSnapshot", ip.nodeId, snapName.text) !== undefined) { snapName.text = ""; ip.reloadSnapshots(); Api.say(qsTr("Snapshot taken")); }
                        }
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(200, contentHeight)
                    clip: true
                    model: ip.snaps
                    delegate: ItemDelegate {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        highlighted: ip.snapIndex === index
                        onClicked: ip.snapIndex = index
                        contentItem: ColumnLayout {
                            spacing: 0
                            Label { text: modelData.title; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { text: new Date(modelData.created).toLocaleString(Qt.locale(), Locale.ShortFormat); color: Theme.subtext; font.pixelSize: 11 }
                        }
                    }
                }
                Label { visible: ip.snaps.length === 0; text: qsTr("No snapshots yet. Take one before a big revision."); color: Theme.subtext; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.margins: 8 }
                RowLayout {
                    visible: ip.snapIndex >= 0
                    Layout.leftMargin: 8
                    Button {
                        text: qsTr("Restore")
                        onClicked: {
                            ip.flushRequested();
                            if (Api.call("restoreSnapshot", ip.nodeId, ip.snaps[ip.snapIndex].id) !== undefined) { ip.reloadSnapshots(); Api.say(qsTr("Restored (previous text saved as a snapshot)")); }
                        }
                    }
                    Button { text: qsTr("Delete"); onClicked: { Api.call("deleteSnapshot", ip.nodeId, ip.snaps[ip.snapIndex].id); ip.reloadSnapshots(); } }
                }
                ScrollView {
                    visible: ip.snapIndex >= 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 8
                    TextArea {
                        readOnly: true
                        wrapMode: TextEdit.Wrap
                        text: ip.snapIndex >= 0 && ip.snaps[ip.snapIndex] ? ip.snaps[ip.snapIndex].text : ""
                        font.family: Theme.editorFont
                        color: Theme.ink
                        background: Rectangle { color: Theme.card; border.color: Theme.border; radius: 3 }
                    }
                }
                Item { Layout.fillHeight: true; visible: ip.snapIndex < 0 }
            }

            // ---------------- Timeline ----------------
            ColumnLayout {
                spacing: 6
                Label { text: qsTr("Timeline events showing this item"); color: Theme.subtext; Layout.margins: 8; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Repeater {
                    model: ip.node ? ip.node.events : []
                    delegate: ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        text: "▬ " + modelData.title + "  ·  " + Api.unitLabel(Api.get("timeline", null), modelData.start)
                        onClicked: ip.openEvent()
                    }
                }
                Label { visible: ip.node && ip.node.events.length === 0; text: qsTr("Not on the timeline yet."); color: Theme.subtext; Layout.leftMargin: 8 }
                Button {
                    Layout.margins: 8
                    text: qsTr("＋ Add to Timeline")
                    enabled: ip.node && !ip.node.is_root
                    onClicked: {
                        let tl = Api.call("timeline");
                        if (!tl) return;
                        let track = tl.tracks.length ? tl.tracks[0].id : Api.call("addTrack", qsTr("Main Plot"), "plotline");
                        const start = tl.events.length ? tl.range[1] : 0;
                        const ev = Api.call("addEvent", ip.node.title, track, start, 1);
                        if (!ev) return;
                        tl = Api.call("timeline");
                        const e = tl.events.find(x => x.id === ev);
                        e.linked_nodes.push(ip.node.id);
                        Api.call("updateEvent", e);
                        ip.openEvent();
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: ip.node === null
        text: qsTr("Nothing selected")
        color: Theme.subtext
    }
}
