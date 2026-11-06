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
};
