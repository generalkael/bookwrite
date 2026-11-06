// Live Markdown styling (and spell-check underlines) for the editor.
//
// Documents stay plain Markdown on disk; MarkdownStyler attaches a syntax
// highlighter to a QML TextEdit's document so headings, **bold**, *italic*,
// > quotes, scene breaks and {>> comments <<} look styled while the markers themselves are
// faded. The rules mirror wordloom-core's compile (compile.rs), so what you
// see is what compiles.
#pragma once

#include <QColor>
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <vector>

class MarkdownHighlighter : public QSyntaxHighlighter
{
    Q_OBJECT
public:
    explicit MarkdownHighlighter(QTextDocument *doc);
    QColor markColor{ 150, 150, 150 };
    QColor quoteColor{ 110, 110, 110 };
    bool spellCheck = false;
    bool styling = true;
    QColor spellColor{ 190, 50, 50 };
    QColor spellTint{ 214, 69, 69, 40 };
    QColor commentTint{ 240, 200, 60, 70 };
    bool repeats = false;
    QColor repeatTint{ 80, 140, 230, 60 };

protected:
    void highlightBlock(const QString &text) override;

private:
    void underlineMisspellings(const QString &text, const std::vector<char> &marker);
    void tintRepeats(const QString &text);
};

class MarkdownStyler : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    Q_PROPERTY(QColor markColor READ markColor WRITE setMarkColor NOTIFY markColorChanged)
    Q_PROPERTY(QColor quoteColor READ quoteColor WRITE setQuoteColor NOTIFY quoteColorChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool spellCheck READ spellCheck WRITE setSpellCheck NOTIFY spellCheckChanged)
    Q_PROPERTY(QColor commentColor READ commentColor WRITE setCommentColor NOTIFY commentColorChanged)
    // Tint words used again a few words later in the same paragraph.
    Q_PROPERTY(bool repeats READ repeats WRITE setRepeats NOTIFY repeatsChanged)
    Q_PROPERTY(QColor repeatColor READ repeatColor WRITE setRepeatColor NOTIFY repeatColorChanged)

public:
    explicit MarkdownStyler(QObject *parent = nullptr);

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *document);
    QColor markColor() const { return m_markColor; }
    void setMarkColor(const QColor &c);
    QColor quoteColor() const { return m_quoteColor; }
    void setQuoteColor(const QColor &c);
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    bool spellCheck() const { return m_spellCheck; }
    void setSpellCheck(bool on);
    QColor commentColor() const { return m_commentColor; }
    void setCommentColor(const QColor &c);
    bool repeats() const { return m_repeats; }
    void setRepeats(bool on);
    QColor repeatColor() const { return m_repeatColor; }
    void setRepeatColor(const QColor &c);
    // The highlighter's background colour at a document position (for the
    // self-test); transparent where there is none.
    Q_INVOKABLE QColor backgroundAt(int position) const;
    // Redraw, e.g. after a word was added to the personal dictionary.
    Q_INVOKABLE void rehighlight();

Q_SIGNALS:
    void documentChanged();
    void markColorChanged();
    void quoteColorChanged();
    void enabledChanged();
    void spellCheckChanged();
    void commentColorChanged();
    void repeatsChanged();
    void repeatColorChanged();

private:
    void attach();

    QPointer<QQuickTextDocument> m_document;
    QPointer<MarkdownHighlighter> m_highlighter;
    QColor m_markColor{ 150, 150, 150 };
    QColor m_quoteColor{ 110, 110, 110 };
    bool m_enabled = true;
    bool m_spellCheck = false;
    QColor m_commentColor{ 240, 200, 60, 70 };
    bool m_repeats = false;
    QColor m_repeatColor{ 80, 140, 230, 60 };
};

// Registers MarkdownStyler as `import com.wordloom.styling` (called from main).
void register_styler_types();
