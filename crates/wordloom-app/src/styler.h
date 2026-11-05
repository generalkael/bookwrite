// Live Markdown styling for the editor.
//
// Documents stay plain Markdown on disk; MarkdownStyler attaches a syntax
// highlighter to a QML TextEdit's document so headings, **bold**, *italic*,
// > quotes and scene breaks look styled while the markers themselves are
// faded. The rules mirror wordloom-core's compile (compile.rs), so what you
// see is what compiles.
#pragma once

#include <QColor>
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>

class MarkdownHighlighter : public QSyntaxHighlighter
{
    Q_OBJECT
public:
    explicit MarkdownHighlighter(QTextDocument *doc);
    QColor markColor{ 150, 150, 150 };
    QColor quoteColor{ 110, 110, 110 };

protected:
    void highlightBlock(const QString &text) override;
};

class MarkdownStyler : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    Q_PROPERTY(QColor markColor READ markColor WRITE setMarkColor NOTIFY markColorChanged)
    Q_PROPERTY(QColor quoteColor READ quoteColor WRITE setQuoteColor NOTIFY quoteColorChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

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

Q_SIGNALS:
    void documentChanged();
    void markColorChanged();
    void quoteColorChanged();
    void enabledChanged();

private:
    void attach();

    QPointer<QQuickTextDocument> m_document;
    QPointer<MarkdownHighlighter> m_highlighter;
    QColor m_markColor{ 150, 150, 150 };
    QColor m_quoteColor{ 110, 110, 110 };
    bool m_enabled = true;
};

// Registers MarkdownStyler as `import com.wordloom.styling` (called from main).
void register_styler_types();
