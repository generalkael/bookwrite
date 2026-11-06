// Include through the same path as the generated bridge header so the
// header is seen once.
#include "wordloom/src/styler.h"
#include "wordloom/src/styling.cxx.h" // spell_ok(), implemented in Rust

#include <QRegularExpression>
#include <QTextCharFormat>
#include <QTextDocument>
#include <QtQml/qqml.h>
#include <algorithm>
#include <vector>

static bool isWordChar(QChar c)
{
    return c.isLetter() || c == QLatin1Char('\'') || c == QChar(0x2019);
}

// Red wavy underline under words the spell checker rejects. Words that look
// like part of a web or email address are skipped.
void MarkdownHighlighter::underlineMisspellings(const QString &text, const std::vector<char> &marker)
{
    const int n = int(text.size());
    for (int i = 0; i < n;) {
        if (!text[i].isLetter()) {
            ++i;
            continue;
        }
        int j = i;
        while (j < n && isWordChar(text[j]) && !marker[j])
            ++j;
        int end = j;
        while (end > i && !text[end - 1].isLetter()) // trailing apostrophes
            --end;
        const QChar before = i > 0 ? text[i - 1] : QChar();
        const QChar after = j < n ? text[j] : QChar();
        // Letters straight after a digit are an ordinal or unit (2nd, 10km).
        const bool address = before.isDigit() || before == QLatin1Char('/') || before == QLatin1Char('@') || before == QLatin1Char('.')
            || after == QLatin1Char('@') || after == QLatin1Char(':') || after.isDigit()
            || (after == QLatin1Char('.') && j + 1 < n && text[j + 1].isLetter());
        if (end - i > 1 && !address) {
            const QByteArray utf8 = text.mid(i, end - i).toUtf8();
            if (!spell_ok(rust::Str(utf8.constData(), size_t(utf8.size())))) {
                for (int k = i; k < end; ++k) {
                    QTextCharFormat f = format(k);
                    // Qt Quick draws underline colours unreliably (and not on
                    // bold/italic runs), so misspellings get a red tint and
                    // red text, plus the underline where it does render.
                    f.setBackground(spellTint);
                    f.setForeground(spellColor);
                    f.setUnderlineStyle(QTextCharFormat::SpellCheckUnderline);
                    f.setUnderlineColor(spellColor);
                    setFormat(k, 1, f);
                }
            }
        }
        i = j > i ? j : i + 1;
    }
}

MarkdownHighlighter::MarkdownHighlighter(QTextDocument *doc)
    : QSyntaxHighlighter(doc)
{
}

// Emphasis left open at the end of a line carries on to the next line of
// the same paragraph (compile joins a paragraph's lines). The open runs are
// packed into the block state, 2 bits each, innermost last; a blank line
// ends the paragraph and resets it.
static int packOpen(const std::vector<int> &runs)
{
    int state = 0;
    for (size_t i = 0; i < runs.size() && i < 8; ++i)
        state |= (runs[i] & 3) << (2 * i);
    return state;
}

static std::vector<int> unpackOpen(int state)
{
    std::vector<int> runs;
    if (state <= 0)
        return runs;
    for (int i = 0; i < 8; ++i) {
        const int r = (state >> (2 * i)) & 3;
        if (!r)
            break;
        runs.push_back(r);
    }
    return runs;
}

void MarkdownHighlighter::highlightBlock(const QString &text)
{
    QTextCharFormat mark;
    mark.setForeground(markColor);
    if (text.trimmed().isEmpty()) {
        setCurrentBlockState(0);
        return;
    }
    if (!styling) { // spell checking only
        if (spellCheck)
            underlineMisspellings(text, std::vector<char>(size_t(text.size()), 0));
        setCurrentBlockState(0);
        return;
    }
    const std::vector<int> carried = unpackOpen(previousBlockState());

    // Scene break: a line of only *, - or _ (at least three), as in compile.
    static const QRegularExpression rule(QStringLiteral("^\\s*([*_-]\\s*){3,}$"));
    if (rule.match(text).hasMatch()) {
        QTextCharFormat f = mark;
        f.setFontWeight(QFont::Bold);
        setFormat(0, int(text.size()), f);
        setCurrentBlockState(0);
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

    // Inline comments, {>> … <<} on one line (as in comments.rs): no
    // emphasis inside, tinted, with faded markers.
    const int n = int(text.size());
    std::vector<char> comment(n, 0);
    static const QString cOpen = QStringLiteral("{>>"), cClose = QStringLiteral("<<}");
    std::vector<std::pair<int, int>> comments;
    for (int from = 0;;) {
        const int s = int(text.indexOf(cOpen, from));
        if (s < 0)
            break;
        const int c = int(text.indexOf(cClose, s + 3));
        if (c < 0)
            break;
        comments.push_back({ s, c + 3 });
        std::fill(comment.begin() + s, comment.begin() + c + 3, 1);
        from = c + 3;
    }

    // Inline emphasis: same pairing rules as compile::spans. Runs of up to
    // three * or _ open a style; the same run length closes it; unclosed
    // markers style to the end of the line; _ inside a word is literal.
    std::vector<char> bold(n, 0), italic(n, 0), marker(n, 0);
    struct Open { int run; int pos; };
    std::vector<Open> open;
    // Runs still open from earlier lines start "before" this one.
    for (int r : carried)
        open.push_back({ r, body - r });
    for (int i = body; i < n;) {
        const QChar c = text[i];
        if (comment[i] || (c != QLatin1Char('*') && c != QLatin1Char('_'))) {
            ++i;
            continue;
        }
        int run = 0;
        while (i + run < n && text[i + run] == c && run < 3 && !comment[i + run])
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
            for (int k = std::max(body, o.pos + o.run); k < i; ++k) {
                if (comment[k]) continue;
                if (run >= 2) bold[k] = 1;
                if (run != 2) italic[k] = 1;
            }
        } else {
            open.push_back({ run, i });
        }
        i += run;
    }
    std::vector<int> stillOpen;
    for (const Open &o : open) {
        stillOpen.push_back(o.run);
        for (int k = std::max(body, o.pos + o.run); k < n; ++k) {
            if (comment[k]) continue;
            if (o.run >= 2) bold[k] = 1;
            if (o.run != 2) italic[k] = 1;
        }
    }
    setCurrentBlockState(packOpen(stillOpen));

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

    for (const auto &[s, e] : comments) {
        for (int k = s; k < e; ++k) {
            QTextCharFormat f = format(k);
            f.setBackground(commentTint);
            f.setFontItalic(false);
            f.setFontWeight(QFont::Normal);
            if (k < s + 3 || k >= e - 3) {
                f.setForeground(markColor);
                marker[k] = 1;
            } else {
                f.clearForeground();
            }
            setFormat(k, 1, f);
        }
    }

    // Last, so the styling above doesn't overwrite the marks.
    if (spellCheck)
        underlineMisspellings(text, marker);
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

void MarkdownStyler::setSpellCheck(bool on)
{
    if (m_spellCheck == on)
        return;
    m_spellCheck = on;
    attach();
    Q_EMIT spellCheckChanged();
}

void MarkdownStyler::setCommentColor(const QColor &c)
{
    if (m_commentColor == c)
        return;
    m_commentColor = c;
    attach();
    Q_EMIT commentColorChanged();
}

void MarkdownStyler::rehighlight()
{
    if (m_highlighter)
        m_highlighter->rehighlight();
}

void MarkdownStyler::attach()
{
    QTextDocument *doc = m_document ? m_document->textDocument() : nullptr;
    // Styling or spell checking needs the highlighter.
    if ((!m_enabled && !m_spellCheck) || !doc) {
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
    m_highlighter->styling = m_enabled;
    m_highlighter->spellCheck = m_spellCheck;
    m_highlighter->markColor = m_markColor;
    m_highlighter->quoteColor = m_quoteColor;
    m_highlighter->commentTint = m_commentColor;
    m_highlighter->rehighlight();
}

void register_styler_types()
{
    qmlRegisterType<MarkdownStyler>("com.wordloom.styling", 1, 0, "MarkdownStyler");
}
