//! Wordloom desktop application entry point.

mod controller;
mod styling;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

fn main() {
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut()
            .set_application_name(&QString::from("Wordloom"));
        // The screenshot tour changes window size and view options; keep those
        // out of the user's saved preferences.
        let tour = std::env::args().any(|a| {
            a.starts_with("--screenshots=") || a == "--selftest" || a.starts_with("--bench=")
        });
        let org = if tour {
            "Wordloom-screenshots"
        } else {
            "Wordloom"
        };
        app.as_mut().set_organization_name(&QString::from(org));
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

    styling::ffi::register_styler_types();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/com/wordloom/app/qml/Main.qml"));
    }
    let code = app.as_mut().map(|app| app.exec()).unwrap_or(1);
    // Tear down QML before exiting so objects such as Settings (saved
    // preferences) get to write their final state; process::exit skips drops.
    drop(engine);
    drop(app);
    std::process::exit(code);
}
