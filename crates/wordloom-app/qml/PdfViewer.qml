import QtQuick
import QtQuick.Pdf

// Scrollable, zoomable PDF pages. Loaded on demand by FileViewer, so a Qt
// without the PDF module still runs (FileViewer shows a fallback instead).
PdfMultiPageView {
    id: view
    property url source
    readonly property int pageCount: doc.pageCount
    // Keep pages fitted to the pane's width (pages are often wider than a
    // split pane) until the user zooms by hand.
    property bool autoFit: true

    document: PdfDocument {
        id: doc
        source: view.source
        onStatusChanged: if (status === PdfDocument.Ready) Qt.callLater(view.refit)
    }
    onWidthChanged: Qt.callLater(refit)
    onSourceChanged: autoFit = true
    // The view sizes its page column only on layout, which a zoom change
    // doesn't trigger here, so pages stayed centred for the old size.
    onRenderScaleChanged: Qt.callLater(relayout)
    function relayout() { for (const c of children) if (typeof c.forceLayout === "function") c.forceLayout(); }

    function refit() {
        if (!autoFit || width <= 50 || doc.status !== PdfDocument.Ready) return;
        scaleToWidth(width - 24, height);
    }
    function fitWidth() { autoFit = true; refit(); }
    function setScale(s) { autoFit = false; renderScale = Math.max(0.1, Math.min(8, s)); }
    function zoomBy(f) { setScale(renderScale * f); }
}
