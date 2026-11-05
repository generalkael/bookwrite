//! Wordloom desktop application entry point.

mod controller;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

fn main() {
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut()
            .set_application_name(&QString::from("Wordloom"));
        app.as_mut()
            .set_organization_name(&QString::from("Wordloom"));
        app.as_mut()
            .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    }
    // Matches packaging/linux/<id>.desktop, so Wayland compositors and
    // Flatpak tie windows to the right launcher and icon.
    QGuiApplication::set_desktop_file_name(&QString::from("io.github.generalkael.Wordloom"));
    // Fusion renders consistently on Linux, Windows and macOS and follows the
    // system light/dark palette. Users can override with QT_QUICK_CONTROLS_STYLE.
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        QQuickStyle::set_style(&QString::from("Fusion"));
    }

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/com/wordloom/app/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        std::process::exit(app.exec());
    }
}
