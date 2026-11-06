import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import com.wordloom.app
import com.wordloom.styling

// Compile the manuscript to Markdown, HTML, plain text, EPUB, DOCX or PDF
// with a live preview. PDF comes as a book or a standard submission
// manuscript, laid out by PdfExporter (src/pdfexport.cpp).
Dialog {
    id: dlg
    title: qsTr("Compile Manuscript")
    modal: true
    width: Math.min(980, parent ? parent.width - 60 : 980)
    height: Math.min(720, parent ? parent.height - 60 : 720)
    standardButtons: Dialog.Close

    readonly property var formats: ["markdown", "html", "plain_text", "epub", "docx", "pdf"]
    readonly property var suffixes: ["md", "html", "txt", "epub", "docx", "pdf"]
    readonly property var filters: ["Markdown (*.md)", "HTML (*.html)", "Text (*.txt)", "EPUB e-book (*.epub)", "Word document (*.docx)", "PDF (*.pdf)"]
    // EPUB, DOCX and PDF preview as formatted text; the others show their source.
    readonly property bool richPreview: formatBox.currentIndex >= 3
    readonly property bool isPdf: formats[formatBox.currentIndex] === "pdf"
    readonly property bool manuscriptStyle: isPdf && pdfStyle.currentIndex === 1
    Settings {
        category: "pdf"
        property alias style: pdfStyle.currentIndex
        property alias paper: paperBox.currentIndex
        property alias font: fontBox.currentIndex
        property alias contact: contactField.text
    }
    PdfExporter { id: exporter }
    // "Quinn" from "Mara Quinn"; the header's short title ("Lighthouse
    // Keeper" from "The Lighthouse Keeper: A Novel").
    function surname() { const w = (Wordloom.title ? Api.get("meta", null).author : "").trim().split(/\s+/); return w[w.length - 1] || ""; }
    function shortTitle() {
        if (headerTitle.text.trim()) return headerTitle.text.trim();
        let t = (Wordloom.title || "").split(":")[0].replace(/\(.*\)/, "").trim();
        const w = t.split(/\s+/);
        if (w.length > 1 && /^(the|a|an)$/i.test(w[0])) w.shift();
        return w.slice(0, 3).join(" ");
    }
    function writePdf(file) {
        const meta = Api.get("meta", null);
        const stats = Api.get("stats", null);
        const r = exporter.write(file, Api.get("compile", "", options()), {
            style: manuscriptStyle ? "manuscript" : "book",
            paper: paperBox.currentIndex === 1 ? "a4" : "letter",
            font: manuscriptStyle && fontBox.currentIndex === 1 ? "serif" : (manuscriptStyle ? "courier" : "serif"),
            titlePage: titlePage.checked,
            title: meta.title, author: meta.author, contact: contactField.text,
            words: Api.get("wordEstimate", "", stats ? stats.manuscript_words : 0),
            surname: surname(), shortTitle: shortTitle()
        });
        return r;
    }
    function options() {
        return {
            format: formats[formatBox.currentIndex],
            title_page: titlePage.checked,
            folder_titles: folderTitles.checked,
            document_titles: docTitles.checked,
            number_chapters: numberChapters.checked,
            scene_separator: sepField.text,
            pdf_style: pdfStyle.currentIndex === 1 ? "manuscript" : "book"
        };
    }
    // For --selftest.
    function selectFormat(f, style) { formatBox.currentIndex = formats.indexOf(f); if (style !== undefined) pdfStyle.currentIndex = style; refresh(); }
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
            ComboBox { id: formatBox; Layout.fillWidth: true; model: ["Markdown (.md)", "HTML, print-styled (.html)", "Plain text (.txt)", "EPUB e-book (.epub)", "Word document (.docx)", "PDF, to print or submit (.pdf)"]; onActivated: dlg.refresh() }
            ColumnLayout {
                visible: dlg.isPdf
                Layout.fillWidth: true
                spacing: 4
                ComboBox {
                    id: pdfStyle
                    Layout.fillWidth: true
                    model: [qsTr("Book"), qsTr("Manuscript (submission format)")]
                    onActivated: dlg.refresh()
                }
                RowLayout {
                    Layout.fillWidth: true
                    ComboBox {
                        id: paperBox
                        Layout.fillWidth: true
                        model: [qsTr("US Letter"), qsTr("A4")]
                        currentIndex: Qt.locale().measurementSystem === Locale.ImperialUSSystem ? 0 : 1
                    }
                    ComboBox {
                        id: fontBox
                        visible: dlg.manuscriptStyle
                        Layout.fillWidth: true
                        model: [qsTr("Courier"), qsTr("Times")]
                    }
                }
                Label { visible: dlg.manuscriptStyle; text: qsTr("Your name and contact details (title page)"); font.pixelSize: 11; color: Theme.subtext }
                TextArea {
                    id: contactField
                    visible: dlg.manuscriptStyle
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    wrapMode: TextEdit.Wrap
                    placeholderText: qsTr("Legal name\nStreet address\nTown, postcode\nemail · phone")
                    background: Rectangle { color: Theme.base; border.color: Theme.border; radius: 3 }
                }
                TextField {
                    id: headerTitle
                    visible: dlg.manuscriptStyle
                    Layout.fillWidth: true
                    placeholderText: qsTr("Short title for the header: %1").arg(dlg.shortTitle())
                }
            }
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
                text: dlg.isPdf
                    ? (dlg.manuscriptStyle
                        ? qsTr("Standard manuscript format: double spaced, a title page with your contact details and the word count, each chapter a third of the way down a new page, and “%1 / %2 / page” at the top right of every page.").arg(dlg.surname() || qsTr("Surname")).arg(dlg.shortTitle().toUpperCase())
                        : qsTr("A book-style PDF: title page, justified text, each chapter on a new page, page numbers at the foot."))
                    : dlg.richPreview
                    ? qsTr("Only items with “Include in compile” checked are exported. Each chapter starts a new page (DOCX) or file (EPUB), and the e-book gets a table of contents. DOCX uses named styles, so you can restyle the whole book in Word.")
                    : qsTr("Only items with “Include in compile” checked are exported. HTML output is styled for print. For a PDF, choose the PDF format.")
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
            if (dlg.isPdf) {
                const r = dlg.writePdf(selectedFile);
                if (r.ok) Api.say(qsTr("Exported %1 to %2").arg(Api.plural(r.pages, qsTr("page"))).arg(selectedFile.toString().replace(/^file:\/\//, "")));
                else Api.say(r.error || qsTr("Couldn't write the PDF"));
                return;
            }
            const p = Api.call("export", selectedFile.toString(), dlg.options());
            if (p) Api.say(qsTr("Exported to %1").arg(p));
        }
    }
}
