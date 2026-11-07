// Self-test aid: real mouse events for the QML self-test (SelfTest.qml), so
// drag and drop is checked through Qt's own event delivery rather than by
// calling the view's functions directly.
#pragma once

#include <QObject>
#include <QPointF>
#include <QString>
#include <QtGui/qtguiglobal.h>

class QQuickWindow;

// Exported by QtGui (QTest uses it the same way): offers a key press to the
// shortcut map, as the platform does for a real one; true if a shortcut took it.
Q_GUI_EXPORT bool qt_sendShortcutOverrideEvent(QObject *o, ulong timestamp, int k, Qt::KeyboardModifiers mods,
                                               const QString &text = QString(), bool autorep = false, ushort count = 1);

class InputSim : public QObject
{
    Q_OBJECT
public:
    explicit InputSim(QObject *parent = nullptr);

    // Hover over `from`, press the left button there (window coordinates), move to `to` in
    // `steps` steps, and release there.
    Q_INVOKABLE void drag(QQuickWindow *window, QPointF from, QPointF to, int steps = 12);
    // Hover over `at`, then press and release `button` (Qt.LeftButton,
    // Qt.RightButton, …) there, holding `modifiers` (Qt.ControlModifier, …).
    Q_INVOKABLE void click(QQuickWindow *window, QPointF at, int button = Qt::LeftButton, int modifiers = 0);
    // Press and release `key` (a Qt.Key_… value) with `modifiers`
    // (Qt.ControlModifier, …): to a matching shortcut, as a real key press
    // would be, or else to the window's focused item.
    Q_INVOKABLE void key(QQuickWindow *window, int key, int modifiers = 0);
};
