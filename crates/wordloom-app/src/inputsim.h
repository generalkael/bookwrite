// Self-test aid: real mouse events for the QML self-test (SelfTest.qml), so
// drag and drop is checked through Qt's own event delivery rather than by
// calling the view's functions directly.
#pragma once

#include <QObject>
#include <QPointF>

class QQuickWindow;

class InputSim : public QObject
{
    Q_OBJECT
public:
    explicit InputSim(QObject *parent = nullptr);

    // Hover over `from`, press the left button there (window coordinates), move to `to` in
    // `steps` steps, and release there.
    Q_INVOKABLE void drag(QQuickWindow *window, QPointF from, QPointF to, int steps = 12);
    // Hover over `at`, then press and release `button` (Qt.LeftButton,
    // Qt.RightButton, …) there.
    Q_INVOKABLE void click(QQuickWindow *window, QPointF at, int button = Qt::LeftButton);
    // Press and release `key` (a Qt.Key_… value) with `modifiers`
    // (Qt.ControlModifier, …), delivered to the window's focused item.
    Q_INVOKABLE void key(QQuickWindow *window, int key, int modifiers = 0);
};
