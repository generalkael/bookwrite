#include "styler.h"

#include <QRegularExpression>
#include <QTextCharFormat>
#include <QTextDocument>
#include <QtQml/qqml.h>
#include <vector>

MarkdownHighlighter::MarkdownHighlighter(QTextDocument *doc)
    : QSyntaxHighlighter(doc)
{
}

void MarkdownHighlighter::highlightBlock(const QString &text)
{
    QTextCharFormat mark;
    mark.setForeground(markColor);

    // Scene break: a line of only *, - or _ (at least three), as in compile.
    static const QRegularExpression rule(QStringLiteral("^\\s*([*_-]\\s*){3,}$"));
    if (rule.match(text).hasMatch()) {
        QTextCharFormat f = mark;
        f.setFontWeight(QFont::Bold);
        setFormat(0, int(text.size()), f);
        return;
    }

    int body = 0; // where inline text starts
    QTextCharFormat base;

    // Heading: "# Title" … "###### Title".
    static const QRegularExpression heading(QStringLiteral("^(#{1,6})\\s+"));
    const auto h = heading.match(text);
    if (h.hasMatch()) {
        const int level = int(h.capturedLength(1));
        base.setFontWeight(QFont::Bold);
        base.setProperty(QTextFormat::FontSizeAdjustment, level == 1 ? 2 : level == 2 ? 1 : 0);
        setFormat(0, int(text.size()), base);
        QTextCharFormat m = base;
        m.setForeground(markColor);
        setFormat(0, int(h.capturedLength(0)), m);
        body = int(h.capturedLength(0));
    } else if (text.startsWith(QLatin1Char('>'))) {
        // Block quote.
        base.setFontItalic(true);
        base.setForeground(quoteColor);
        setFormat(0, int(text.size()), base);
        int n = 1;
        while (n < text.size() && (text[n] == QLatin1Char('>') || text[n] == QLatin1Char(' ')))
            ++n;
        setFormat(0, n, mark);
        body = n;
    }

    // Inline emphasis: same pairing rules as compile::spans. Runs of up to
    // three * or _ open a style; the same run length closes it; unclosed
    // markers style to the end of the line; _ inside a word is literal.
    const int n = int(text.size());
    std::vector<char> bold(n, 0), italic(n, 0), marker(n, 0);
    struct Open { int run; int pos; };
    std::vector<Open> open;
    for (int i = body; i < n;) {
        const QChar c = text[i];
        if (c != QLatin1Char('*') && c != QLatin1Char('_')) {
            ++i;
            continue;
        }
        int run = 0;
        while (i + run < n && text[i + run] == c && run < 3)
            ++run;
        const bool insideWord = c == QLatin1Char('_') && i > 0 && text[i - 1].isLetterOrNumber()
            && i + run < n && text[i + run].isLetterOrNumber();
        if (insideWord) {
            ++i;
            continue;
        }
        for (int k = 0; k < run; ++k)
            marker[i + k] = 1;
        if (!open.empty() && open.back().run == run) {
            const Open o = open.back();
            open.pop_back();
            for (int k = o.pos + o.run; k < i; ++k) {
                if (run >= 2) bold[k] = 1;
                if (run != 2) italic[k] = 1;
            }
        } else {
            open.push_back({ run, i });
        }
        i += run;
    }
    for (const Open &o : open)
        for (int k = o.pos + o.run; k < n; ++k) {
            if (o.run >= 2) bold[k] = 1;
            if (o.run != 2) italic[k] = 1;
        }

    for (int i = body; i < n;) {
        int j = i;
        while (j < n && bold[j] == bold[i] && italic[j] == italic[i] && marker[j] == marker[i])
            ++j;
        if (bold[i] || italic[i] || marker[i]) {
            QTextCharFormat f = base;
            if (bold[i]) f.setFontWeight(QFont::Bold);
            if (italic[i]) f.setFontItalic(true);
            if (marker[i]) f.setForeground(markColor);
            setFormat(i, j - i, f);
        }
        i = j;
    }
}

MarkdownStyler::MarkdownStyler(QObject *parent)
    : QObject(parent)
{
}

void MarkdownStyler::setDocument(QQuickTextDocument *document)
{
    if (m_document == document)
        return;
    m_document = document;
    attach();
    Q_EMIT documentChanged();
}

void MarkdownStyler::setMarkColor(const QColor &c)
{
    if (m_markColor == c)
        return;
    m_markColor = c;
    attach();
    Q_EMIT markColorChanged();
}

void MarkdownStyler::setQuoteColor(const QColor &c)
{
    if (m_quoteColor == c)
        return;
    m_quoteColor = c;
    attach();
    Q_EMIT quoteColorChanged();
}

void MarkdownStyler::setEnabled(bool on)
{
    if (m_enabled == on)
        return;
    m_enabled = on;
    attach();
    Q_EMIT enabledChanged();
}

void MarkdownStyler::attach()
{
    QTextDocument *doc = m_document ? m_document->textDocument() : nullptr;
    if (!m_enabled || !doc) {
        if (m_highlighter) {
            m_highlighter->setDocument(nullptr);
            delete m_highlighter;
        }
        return;
    }
    if (!m_highlighter || m_highlighter->document() != doc) {
        delete m_highlighter;
        m_highlighter = new MarkdownHighlighter(doc);
    }
    m_highlighter->markColor = m_markColor;
    m_highlighter->quoteColor = m_quoteColor;
    m_highlighter->rehighlight();
}

void register_styler_types()
{
    qmlRegisterType<MarkdownStyler>("com.wordloom.styling", 1, 0, "MarkdownStyler");
}
