// PDF export: lays out the compiled manuscript (HTML from wordloom-core's
// print.rs) with Qt's text engine and writes it with QPdfWriter, adding the
// title page, the running header (manuscript style) or page numbers (book
// style).
#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantMap>

class PdfExporter : public QObject
{
    Q_OBJECT
public:
    explicit PdfExporter(QObject *parent = nullptr);

    // Write `html` to `file`. Options: style ("book" | "manuscript"), paper
    // ("letter" | "a4"), font ("serif" | "courier"), titlePage (bool), title,
    // author, contact (multi-line), words ("about 80,000 words"), surname,
    // shortTitle. Returns {ok, pages, error}.
    Q_INVOKABLE QVariantMap write(const QUrl &file, const QString &html, const QVariantMap &options);
};
