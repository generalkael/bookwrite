import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.wordloom.app

// Shows an imported research file: images with fit / zoom, PDFs page by
// page. Anything else (or a PDF when Qt lacks the PDF module) gets a button
// to open it in the system's default app.
Rectangle {
    id: fv
    color: Theme.window

    property var file: null          // nodeInfo.file: {url, kind, exists}
    property real zoom: 0            // 0 = fit to the pane
    onFileChanged: zoom = 0

    readonly property bool missing: !file || !file.exists
    readonly property bool isImage: !missing && file.kind === "image"
    readonly property bool isPdf: !missing && file.kind === "pdf"
    readonly property bool pdfFailed: isPdf && pdfLoader.status === Loader.Error

    function openExternally() { if (file) Qt.openUrlExternally(file.url); }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            visible: fv.isImage
            Label {
                text: img.status === Image.Ready ? qsTr("%1 × %2 px · %3%").arg(img.implicitWidth).arg(img.implicitHeight).arg(Math.round(img.scale * 100)) : ""
                color: Theme.subtext
                Layout.fillWidth: true
            }
            ToolButton { text: qsTr("Fit"); checkable: true; checked: fv.zoom === 0; onClicked: fv.zoom = 0 }
            ToolButton { text: "1:1"; onClicked: fv.zoom = 1 }
            ToolButton { text: "−"; onClicked: fv.zoom = Math.max(0.1, img.scale / 1.25) }
            ToolButton { text: "+"; onClicked: fv.zoom = Math.min(8, img.scale * 1.25) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            visible: fv.isPdf && pdfLoader.status === Loader.Ready
            Label {
                text: pdfLoader.item ? qsTr("Page %1 of %2 · %3%").arg(pdfLoader.item.currentPage + 1).arg(pdfLoader.item.pageCount).arg(Math.round(pdfLoader.item.renderScale * 100)) : ""
                color: Theme.subtext
                Layout.fillWidth: true
            }
            ToolButton { text: qsTr("Fit Width"); onClicked: pdfLoader.item.fitWidth() }
            ToolButton { text: "1:1"; onClicked: pdfLoader.item.setScale(1) }
            ToolButton { text: "−"; onClicked: pdfLoader.item.zoomBy(1 / 1.25) }
            ToolButton { text: "+"; onClicked: pdfLoader.item.zoomBy(1.25) }
        }

        // ---- image ----
        Flickable {
            id: flick
            visible: fv.isImage
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: Math.max(width, img.implicitWidth * img.scale)
            contentHeight: Math.max(height, img.implicitHeight * img.scale)
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}

            Image {
                id: img
                source: fv.isImage ? fv.file.url : ""
                asynchronous: true
                smooth: true
                mipmap: true
                transformOrigin: Item.TopLeft
                readonly property real fit: implicitWidth > 0 ? Math.min(1, (flick.width - 24) / implicitWidth, (flick.height - 24) / implicitHeight) : 1
                scale: fv.zoom === 0 ? fit : fv.zoom
                x: Math.max(0, (flick.width - implicitWidth * scale) / 2)
                y: Math.max(0, (flick.height - implicitHeight * scale) / 2)
            }
            // Ctrl+wheel zooms; plain wheel scrolls.
            WheelHandler {
                acceptedModifiers: Qt.ControlModifier
                onWheel: (e) => fv.zoom = Math.max(0.1, Math.min(8, img.scale * (e.angleDelta.y > 0 ? 1.1 : 1 / 1.1)))
            }
        }

        // ---- PDF ----
        Loader {
            id: pdfLoader
            visible: fv.isPdf && status === Loader.Ready
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: fv.isPdf
            source: "PdfViewer.qml"
            onLoaded: item.source = Qt.binding(() => fv.isPdf ? fv.file.url : "")
        }

        // ---- fallback ----
        ColumnLayout {
            visible: fv.missing || fv.pdfFailed || (!fv.isImage && !fv.isPdf) || img.status === Image.Error
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            Item { Layout.fillHeight: true }
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: fv.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.subtext
                text: fv.missing ? qsTr("The imported file is missing from the project's files folder.")
                    : fv.pdfFailed ? qsTr("This build of Qt has no PDF viewer.")
                    : img.status === Image.Error ? qsTr("This image can't be shown here.")
                    : qsTr("Wordloom can't preview this kind of file.")
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                visible: !fv.missing
                text: qsTr("Open in Default App")
                onClicked: fv.openExternally()
            }
            Item { Layout.fillHeight: true }
        }
    }
}
