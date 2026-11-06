#include "inputsim.h"

#include <QGuiApplication>
#include <QContextMenuEvent>
#include <QKeyEvent>
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

void InputSim::key(QQuickWindow *window, int key, int modifiers)
{
    if (!window)
        return;
    const auto mods = Qt::KeyboardModifiers(modifiers);
    QKeyEvent press(QEvent::KeyPress, key, mods);
    QGuiApplication::sendEvent(window, &press);
    QKeyEvent release(QEvent::KeyRelease, key, mods);
    QGuiApplication::sendEvent(window, &release);
}

void InputSim::click(QQuickWindow *window, QPointF at, int button, int modifiers)
{
    if (!window)
        return;
    const auto b = Qt::MouseButton(button);
    const auto mods = Qt::KeyboardModifiers(modifiers);
    const auto send = [window, mods](QEvent::Type type, QPointF pos, Qt::MouseButton btn, Qt::MouseButtons buttons) {
        QMouseEvent e(type, pos, pos, window->mapToGlobal(pos), btn, buttons, mods, QPointingDevice::primaryPointingDevice());
        QGuiApplication::sendEvent(window, &e);
    };
    send(QEvent::MouseMove, at, Qt::NoButton, Qt::NoButton);
    send(QEvent::MouseButtonPress, at, b, b);
    send(QEvent::MouseButtonRelease, at, b, Qt::NoButton);
    // Qt 6.9+ opens context menus from a QContextMenuEvent.
    if (b == Qt::RightButton) {
        QContextMenuEvent e(QContextMenuEvent::Mouse, at.toPoint(), window->mapToGlobal(at).toPoint());
        QGuiApplication::sendEvent(window, &e);
    }
}
