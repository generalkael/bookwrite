import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import com.wordloom.app

// Compile the manuscript to Markdown, HTML, plain text, EPUB or DOCX with a
// live preview.
Dialog {
    id: dlg
    title: qsTr("Compile Manuscript")
    modal: true
    width: Math.min(980, parent ? parent.width - 60 : 980)
    height: Math.min(720, parent ? parent.height - 60 : 720)
    standardButtons: Dialog.Close

    readonly property var formats: ["markdown", "html", "plain_text", "epub", "docx"]
    readonly property var suffixes: ["md", "html", "txt", "epub", "docx"]
    readonly property var filters: ["Markdown (*.md)", "HTML (*.html)", "Text (*.txt)", "EPUB e-book (*.epub)", "Word document (*.docx)"]
    // EPUB and DOCX preview as formatted text; the others show their source.
    readonly property bool richPreview: formatBox.currentIndex >= 3
    function options() {
        return {
            format: formats[formatBox.currentIndex],
            title_page: titlePage.checked,
            folder_titles: folderTitles.checked,
            document_titles: docTitles.checked,
            number_chapters: numberChapters.checked,
            scene_separator: sepField.text
        };
    }
    function refresh() { preview.text = Api.get("compile", "", options()); }
    onAboutToShow: refresh()

    RowLayout {
        anchors.fill: parent
        spacing: 16
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            spacing: 6
            Label { text: qsTr("Format"); font.bold: true }
            ComboBox { id: formatBox; Layout.fillWidth: true; model: ["Markdown (.md)", "HTML, print-styled (.html)", "Plain text (.txt)", "EPUB e-book (.epub)", "Word document (.docx)"]; onActivated: dlg.refresh() }
            CheckBox { id: titlePage; text: qsTr("Title page"); checked: true; onToggled: dlg.refresh() }
            CheckBox { id: folderTitles; text: qsTr("Folder titles as chapter headings"); checked: true; onToggled: dlg.refresh() }
            CheckBox { id: numberChapters; text: qsTr("Number chapters"); onToggled: dlg.refresh() }
            CheckBox { id: docTitles; text: qsTr("Document titles as scene headings"); onToggled: dlg.refresh() }
            Label { text: qsTr("Scene separator") }
            TextField { id: sepField; Layout.fillWidth: true; text: "* * *"; onEditingFinished: dlg.refresh() }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.pixelSize: 11
                text: dlg.richPreview
                    ? qsTr("Only items with “Include in compile” checked are exported. Each chapter starts a new page (DOCX) or file (EPUB), and the e-book gets a table of contents. DOCX uses named styles, so you can restyle the whole book in Word.")
                    : qsTr("Only items with “Include in compile” checked are exported. HTML output is styled for print; use Print to PDF in a browser for a PDF.")
            }
            Item { Layout.fillHeight: true }
            Button { text: qsTr("Export…"); highlighted: true; Layout.fillWidth: true; onClicked: saveDialog.open() }
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                id: preview
                readOnly: true
                wrapMode: TextEdit.Wrap
                textFormat: dlg.richPreview ? TextEdit.RichText : TextEdit.PlainText
                font.family: dlg.richPreview ? "serif" : "monospace"
                leftPadding: dlg.richPreview ? 24 : 6
                rightPadding: leftPadding
                background: Rectangle { color: Theme.base; border.color: Theme.border }
            }
        }
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        title: qsTr("Export manuscript")
        defaultSuffix: dlg.suffixes[formatBox.currentIndex]
        nameFilters: [dlg.filters[formatBox.currentIndex]]
        currentFile: "file:///" + (Wordloom.title || "manuscript") + "." + defaultSuffix
        onAccepted: {
            const p = Api.call("export", selectedFile.toString(), dlg.options());
            if (p) Api.say(qsTr("Exported to %1").arg(p));
        }
    }
}
