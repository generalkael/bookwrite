//! The single QObject exposed to QML. It owns a [`wordloom_core::api::App`]
//! and forwards `call(method, argsJson)`; after any call that changes project
//! data it bumps `revision` so views re-query what they display.

use std::pin::Pin;

use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use wordloom_core::api::App;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, project_open)]
        #[qproperty(QString, title)]
        #[qproperty(QString, project_path)]
        #[qproperty(i32, revision)]
        #[qproperty(bool, dirty)]
        #[qproperty(QString, last_error)]
        type Wordloom = super::WordloomRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// Invoke an API method. `args` is a JSON array; the reply is
        /// `{"ok":bool,"result":…,"error":…}` as JSON.
        #[qinvokable]
        fn call(self: Pin<&mut Wordloom>, method: &QString, args: &QString) -> QString;
    }
}

pub struct WordloomRust {
    app: App,
    project_open: bool,
    title: QString,
    project_path: QString,
    revision: i32,
    dirty: bool,
    last_error: QString,
}

impl Default for WordloomRust {
    fn default() -> Self {
        let recent_file = dirs::config_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join("wordloom")
            .join("recent.json");
        Self {
            app: App::new(recent_file),
            project_open: false,
            title: QString::default(),
            project_path: QString::default(),
            revision: 0,
            dirty: false,
            last_error: QString::default(),
        }
    }
}

impl qobject::Wordloom {
    pub fn call(mut self: Pin<&mut Self>, method: &QString, args: &QString) -> QString {
        let method = method.to_string();
        let reply = self
            .as_mut()
            .rust_mut()
            .app
            .call(&method, &args.to_string());

        let (open, title, path, dirty) = {
            let app = &self.rust().app;
            (
                app.session.is_some(),
                app.title(),
                app.path()
                    .map(|p| p.display().to_string())
                    .unwrap_or_default(),
                app.dirty(),
            )
        };
        if open != *self.project_open() {
            self.as_mut().set_project_open(open);
        }
        if *self.title() != QString::from(&title) {
            self.as_mut().set_title(QString::from(&title));
        }
        if *self.project_path() != QString::from(&path) {
            self.as_mut().set_project_path(QString::from(&path));
        }
        if dirty != *self.dirty() {
            self.as_mut().set_dirty(dirty);
        }
        let err = reply.error.clone().unwrap_or_default();
        if !err.is_empty() {
            eprintln!("wordloom: {method}: {err}");
        }
        self.as_mut().set_last_error(QString::from(&err));
        if reply.mutated {
            let r = *self.revision() + 1;
            self.as_mut().set_revision(r);
        }
        QString::from(&reply.json)
    }
}
