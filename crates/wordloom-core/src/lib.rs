//! # wordloom-core
//!
//! Everything Wordloom knows about a writing project, independent of any UI:
//! the binder tree and its metadata ([`model`]), plain-text on-disk storage
//! with snapshots and backups ([`storage`]), manuscript compilation
//! ([`compile`]), search & replace ([`search`]), writing statistics
//! ([`stats`]), snapshot comparison ([`diff`]), project-wide undo ([`history`]), and the story timeline /
//! Gantt engine ([`timeline`]).
//!
//! [`Session`] bundles an open project with its location and offers the
//! string/JSON API that the Qt front end calls.

pub mod api;
pub mod compile;
pub mod demo;
pub mod diff;
mod docx;
mod epub;
pub mod history;
pub mod model;
pub mod recent;
pub mod relations;
pub mod search;
pub mod session;
pub mod stats;
pub mod storage;
pub mod timeline;
mod zip;

pub use model::{FlatRow, Label, Node, NodeId, NodeKind, Project, RootRole, Status};
pub use session::Session;
pub use timeline::{Event, Marker, Problem, Timeline, Track, TrackKind};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("could not read project data: {0}")]
    Json(#[from] serde_json::Error),
    #[error("{} is not a Wordloom project", .0.display())]
    NotAProject(std::path::PathBuf),
    #[error("no item with id {0}")]
    NoSuchNode(NodeId),
    #[error("{0}")]
    Invalid(String),
}

pub type Result<T, E = Error> = std::result::Result<T, E>;
