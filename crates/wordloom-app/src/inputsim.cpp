#include "inputsim.h"

#include <QGuiApplication>
#include <QMouseEvent>
#include <QPointingDevice>
#include <QQuickWindow>

InputSim::InputSim(QObject *parent)
    : QObject(parent)
{
}

void InputSim::drag(QQuickWindow *window, QPointF from, QPointF to, int steps)
{
    if (!window)
        return;
    const auto send = [window](QEvent::Type type, QPointF pos, Qt::MouseButton button, Qt::MouseButtons buttons) {
        const QPointF global = window->mapToGlobal(pos);
        QMouseEvent e(type, pos, pos, global, button, buttons, Qt::NoModifier, QPointingDevice::primaryPointingDevice());
        // Delivered synchronously. No processEvents(): a nested event loop
        // would let the self-test's own timer run its next step mid-drag.
        QGuiApplication::sendEvent(window, &e);
    };
    // Hover first, as a real pointer does.
    send(QEvent::MouseMove, from, Qt::NoButton, Qt::NoButton);
    send(QEvent::MouseButtonPress, from, Qt::LeftButton, Qt::LeftButton);
    steps = qMax(1, steps);
    for (int i = 1; i <= steps; ++i)
        send(QEvent::MouseMove, from + (to - from) * (qreal(i) / steps), Qt::NoButton, Qt::LeftButton);
    send(QEvent::MouseButtonRelease, to, Qt::LeftButton, Qt::NoButton);
}
