use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

const QML: &[&str] = &[
    "qml/Main.qml",
    "qml/StartPage.qml",
    "qml/Workspace.qml",
    "qml/BinderPane.qml",
    "qml/EditorView.qml",
    "qml/CorkboardView.qml",
    "qml/OutlinerView.qml",
    "qml/InspectorPane.qml",
    "qml/GanttView.qml",
    "qml/EventDialog.qml",
    "qml/TrackDialog.qml",
    "qml/CompileDialog.qml",
    "qml/StatsDialog.qml",
    "qml/ProjectSettingsDialog.qml",
    "qml/SearchPane.qml",
];

/// `pragma Singleton` QML files.
const SINGLETONS: &[&str] = &["qml/Theme.qml", "qml/Api.qml"];

fn main() {
    let mut files: Vec<QmlFile> = QML.iter().map(QmlFile::from).collect();
    for f in SINGLETONS {
        files.push(QmlFile::from(f).singleton(true));
    }
    for f in QML.iter().chain(SINGLETONS) {
        println!("cargo:rerun-if-changed={f}");
    }

    CxxQtBuilder::new_qml_module(QmlModule::new("com.wordloom.app").qml_files(files))
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .files(["src/controller.rs"])
        .build();
}
