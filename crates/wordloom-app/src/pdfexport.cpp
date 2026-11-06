#include "pdfexport.h"

#include <QAbstractTextDocumentLayout>
#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>
#include <QFont>
#include <QFontMetricsF>
#include <QPageLayout>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QTextDocument>

PdfExporter::PdfExporter(QObject *parent)
    : QObject(parent)
{
}

static QFont bodyFont(const QString &kind, double points)
{
    QFont f;
    if (kind == QLatin1String("courier"))
        f.setFamilies({ QStringLiteral("Courier Prime"), QStringLiteral("Courier New"), QStringLiteral("Courier"),
                        QStringLiteral("Liberation Mono"), QStringLiteral("Nimbus Mono PS"), QStringLiteral("DejaVu Sans Mono"),
                        QStringLiteral("monospace") });
    else
        f.setFamilies({ QStringLiteral("Times New Roman"), QStringLiteral("Liberation Serif"), QStringLiteral("Nimbus Roman"),
                        QStringLiteral("TeX Gyre Termes"), QStringLiteral("Georgia"), QStringLiteral("DejaVu Serif"),
                        QStringLiteral("Noto Serif"), QStringLiteral("serif") });
    f.setStyleHint(kind == QLatin1String("courier") ? QFont::TypeWriter : QFont::Serif);
    f.setPointSizeF(points);
    return f;
}

QVariantMap PdfExporter::write(const QUrl &file, const QString &html, const QVariantMap &o)
{
    QVariantMap result{ { QStringLiteral("ok"), false }, { QStringLiteral("pages"), 0 } };
    const QString path = file.isLocalFile() ? file.toLocalFile() : file.toString();
    const bool manuscript = o.value(QStringLiteral("style")).toString() == QLatin1String("manuscript");
    const QString fontKind = o.value(QStringLiteral("font"), manuscript ? QStringLiteral("courier") : QStringLiteral("serif")).toString();
    const QString title = o.value(QStringLiteral("title")).toString();
    const QString author = o.value(QStringLiteral("author")).toString();

    QPdfWriter writer(path);
    writer.setResolution(300);
    writer.setPageSize(QPageSize(o.value(QStringLiteral("paper")).toString() == QLatin1String("a4") ? QPageSize::A4 : QPageSize::Letter));
    // Margins are drawn by hand so the header can sit in the top margin.
    writer.setPageMargins(QMarginsF(0, 0, 0, 0), QPageLayout::Point);
    writer.setTitle(title);
    writer.setCreator(QStringLiteral("Wordloom"));

    QPainter p;
    if (!p.begin(&writer)) {
        result[QStringLiteral("error")] = tr("Can't write %1").arg(path);
        return result;
    }
    const double dpi = writer.resolution();
    const double inch = dpi;
    const QRectF page(0, 0, writer.width(), writer.height());
    // One-inch margins (book style: a little wider at the sides).
    const double side = manuscript ? inch : 1.1 * inch;
    const QRectF body(side, inch, page.width() - 2 * side, page.height() - 2 * inch);
    const QFont font = bodyFont(fontKind, manuscript ? 12 : 11.5);

    // The compiled body, cut into chapters (print.rs marks each start).
    // Every chapter is laid out on its own pages: Qt's own page breaks
    // would add the title's top margin twice.
    QString inner = html;
    const int bodyAt = inner.indexOf(QLatin1String("<body>"));
    const int bodyEnd = inner.lastIndexOf(QLatin1String("</body>"));
    if (bodyAt >= 0 && bodyEnd > bodyAt)
        inner = inner.mid(bodyAt + 6, bodyEnd - bodyAt - 6);
    const QStringList parts = inner.split(QStringLiteral("<!--wordloom:chapter-->"));
    std::vector<std::unique_ptr<QTextDocument>> docs;
    int bodyPages = 0;
    for (int k = 0; k < parts.size(); ++k) {
        if (parts[k].trimmed().isEmpty())
            continue;
        auto doc = std::make_unique<QTextDocument>();
        doc->documentLayout()->setPaintDevice(&writer);
        doc->setDefaultFont(font);
        doc->setDocumentMargin(0);
        doc->setHtml(QStringLiteral("<html><body>") + parts[k] + QStringLiteral("</body></html>"));
        doc->setPageSize(body.size());
        bodyPages += doc->pageCount();
        docs.push_back(std::move(doc));
    }

    p.setFont(font);
    p.setPen(Qt::black);
    const QFontMetricsF fm(font, &writer);
    const double line = fm.lineSpacing();
    bool first = true;
    auto newPage = [&]() {
        if (!first)
            writer.newPage();
        first = false;
    };

    // ---- title page ----
    const bool titlePage = o.value(QStringLiteral("titlePage"), true).toBool();
    if (titlePage) {
        newPage();
        if (manuscript) {
            // Contact details top left, word count top right, title and
            // byline centred halfway down (the standard manuscript layout).
            QString contact = o.value(QStringLiteral("contact")).toString().trimmed();
            if (contact.isEmpty())
                contact = author;
            p.drawText(QRectF(body.left(), body.top(), body.width() * 0.6, body.height() / 2), Qt::AlignLeft | Qt::AlignTop, contact);
            p.drawText(QRectF(body.left(), body.top(), body.width(), line * 2), Qt::AlignRight | Qt::AlignTop,
                       o.value(QStringLiteral("words")).toString());
            const double mid = page.height() / 2 - line;
            p.drawText(QRectF(body.left(), mid, body.width(), line * 4), Qt::AlignHCenter | Qt::AlignTop | Qt::TextWordWrap,
                       title.toUpper());
            p.drawText(QRectF(body.left(), mid + 2 * line * std::max(1.0, std::ceil(fm.horizontalAdvance(title.toUpper()) / body.width())),
                              body.width(), line * 2),
                       Qt::AlignHCenter | Qt::AlignTop, tr("by %1").arg(author));
        } else {
            QFont big = font;
            big.setPointSizeF(26);
            p.setFont(big);
            const QRectF t(body.left(), page.height() / 3, body.width(), page.height() / 4);
            QRectF used;
            p.drawText(t, Qt::AlignHCenter | Qt::AlignTop | Qt::TextWordWrap, title, &used);
            QFont by = font;
            by.setPointSizeF(14);
            p.setFont(by);
            p.drawText(QRectF(body.left(), used.bottom() + inch * 0.5, body.width(), inch), Qt::AlignHCenter | Qt::AlignTop, author);
            p.setFont(font);
        }
    }

    // ---- body pages ----
    const QString surname = o.value(QStringLiteral("surname")).toString();
    const QString shortTitle = o.value(QStringLiteral("shortTitle")).toString();
    QFont small = font;
    small.setPointSizeF(manuscript ? 12 : 9.5);
    int number = 0;
    for (const auto &doc : docs) {
        for (int i = 0; i < doc->pageCount(); ++i) {
            newPage();
            ++number;
            p.setFont(small);
            if (manuscript) {
                // "Surname / TITLE / 3", half an inch from the top, flush right.
                const QString head = QStringLiteral("%1 / %2 / %3").arg(surname, shortTitle.toUpper()).arg(number);
                p.drawText(QRectF(body.left(), inch * 0.5, body.width(), line * 1.5), Qt::AlignRight | Qt::AlignTop, head);
            } else {
                p.drawText(QRectF(body.left(), page.height() - inch * 0.65, body.width(), line * 1.5), Qt::AlignHCenter | Qt::AlignTop,
                           QString::number(number));
            }
            p.setFont(font);
            p.save();
            p.translate(body.left(), body.top() - i * body.height());
            doc->drawContents(&p, QRectF(0, i * body.height(), body.width(), body.height()));
            p.restore();
        }
    }
    if (first) // nothing at all: still a valid one-page PDF
        newPage();
    p.end();
    result[QStringLiteral("ok")] = true;
    result[QStringLiteral("pages")] = bodyPages + (titlePage ? 1 : 0);
    return result;
}
