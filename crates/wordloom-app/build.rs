use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

const QML: &[&str] = &[
    "qml/Main.qml",
    "qml/StartPage.qml",
    "qml/Workspace.qml",
    "qml/BinderPane.qml",
    "qml/EditorView.qml",
    "qml/FileViewer.qml",
    "qml/PdfViewer.qml",
    "qml/CorkboardView.qml",
    "qml/OutlinerView.qml",
    "qml/InspectorPane.qml",
    "qml/GanttView.qml",
    "qml/RelationsView.qml",
    "qml/ReaderView.qml",
    "qml/EventDialog.qml",
    "qml/TrackDialog.qml",
    "qml/CompileDialog.qml",
    "qml/CompareDialog.qml",
    "qml/StatsDialog.qml",
    "qml/HistoryWindow.qml",
    "qml/SprintDialog.qml",
    "qml/SelfTest.qml",
    "qml/NameDialog.qml",
    "qml/AnalysisDialog.qml",
    "qml/ProjectSettingsDialog.qml",
    "qml/SearchPane.qml",
    "qml/KindIcon.qml",
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

    // Item icons (SVG), served next to the QML at qrc:/qt/qml/com/wordloom/app/qml/icons/.
    let icons: Vec<String> = std::fs::read_dir("qml/icons")
        .expect("qml/icons")
        .filter_map(|e| e.ok()?.path().to_str().map(String::from))
        .filter(|p| p.ends_with(".svg"))
        .collect();
    println!("cargo:rerun-if-changed=qml/icons");

    CxxQtBuilder::new_qml_module(QmlModule::new("com.wordloom.app").qml_files(files))
        .qrc_resources(icons)
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .files(["src/controller.rs", "src/styling.rs"])
        // Live Markdown styling in the editor (a QSyntaxHighlighter), and
        // PDF export (QPdfWriter).
        .cpp_files([
            "src/styler.h",
            "src/styler.cpp",
            "src/pdfexport.h",
            "src/pdfexport.cpp",
        ])
        .build();
}
