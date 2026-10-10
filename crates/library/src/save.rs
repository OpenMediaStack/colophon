use std::fs;
use std::io;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::thread;

use colophon_tags::{Metadata, TagVersions, Tags, WriteError};

/// A file to write, and the tags to write into it, in which versions.
#[derive(Debug, Clone)]
pub struct SaveJob {
    /// The track's place in the library, handed back with the outcome.
    pub track: usize,
    pub path: PathBuf,
    pub tags: Tags,
    pub versions: TagVersions,
}

/// What a save reports: each file written or not, in order, then its end.
#[derive(Debug)]
pub enum SaveEvent {
    Written {
        track: usize,
        result: Result<Box<Written>, WriteError>,
    },
    Finished,
}

/// A file as it is once written.
#[derive(Debug)]
pub struct Written {
    pub metadata: Metadata,
    pub size: u64,
}

/// A save running on its own thread. Dropping the handle stops it after the file being written.
#[derive(Debug)]
pub struct SaveHandle {
    stop: Arc<AtomicBool>,
    events: Receiver<SaveEvent>,
}

impl SaveHandle {
    /// The events of the save, in order. The channel closes after [`SaveEvent::Finished`].
    pub fn events(&self) -> &Receiver<SaveEvent> {
        &self.events
    }
}

impl Drop for SaveHandle {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// Writes each job's tags into its file, one file after the other, on a new thread, so that the
/// UI thread never waits for the disk.
pub fn spawn_save(jobs: Vec<SaveJob>) -> io::Result<SaveHandle> {
    let stop = Arc::new(AtomicBool::new(false));
    let (sender, events) = mpsc::channel();
    let thread_stop = Arc::clone(&stop);
    thread::Builder::new()
        .name("library save".to_string())
        .spawn(move || {
            for job in jobs {
                if thread_stop.load(Ordering::Relaxed) {
                    return;
                }
                let result =
                    colophon_tags::write(&job.path, &job.tags, job.versions).map(|metadata| {
                        let size = fs::metadata(&job.path).map_or(0, |file| file.len());
                        Box::new(Written { metadata, size })
                    });
                let event = SaveEvent::Written {
                    track: job.track,
                    result,
                };
                // A closed channel means nobody listens any more: the rest of the save is not needed.
                if sender.send(event).is_err() {
                    return;
                }
            }
            let _ = sender.send(SaveEvent::Finished);
        })?;
    Ok(SaveHandle { stop, events })
}
