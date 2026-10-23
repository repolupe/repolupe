//! Combines the packs of a repository into one. gitoxide writes a pack per fetch and, unlike
//! git, never repacks, so they would pile up and slow down every object lookup.

use super::{failed, pack_dir};
use crate::config::error::AppError;
use gix::hash::Kind;
use gix::odb::pack::data::output::{self, count, entry};
use gix::parallel::InOrderIter;
use gix::progress::Discard;
use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use uuid::Uuid;

/// Packs kept before they are combined, like git's `gc.autoPackLimit`.
pub(super) const MAX_PACKS: usize = 50;

/// Combines the packs and loose objects of the repository at `git_dir` into one pack if it has
/// more than `max_packs`. Keeps every object, also unreachable ones, since answers may still
/// refer to commits the remote branch no longer contains.
///
/// Readers can keep reading meanwhile: gitoxide finds the new pack when an old one is gone.
pub(super) fn consolidate_packs(
    git_dir: &Path,
    max_packs: usize,
    should_interrupt: &AtomicBool,
) -> Result<(), AppError> {
    let pack_dir = pack_dir(git_dir);
    let packs = list_packs(&pack_dir).map_err(|e| failed("repack", e))?;
    if packs.len() <= max_packs {
        return Ok(());
    }

    let objects_dir = git_dir.join("objects");
    // Listed first, so objects written meanwhile, e.g. by `commit_file`, stay loose.
    let loose = list_loose_objects(&objects_dir).map_err(|e| failed("repack", e))?;
    let mut db = gix::odb::at(&objects_dir, Kind::Sha1).map_err(|e| failed("repack", e))?;
    // Entries are copied from the packs by their location, which must stay valid.
    db.prevent_pack_unload();
    let ids = db.iter().map_err(|e| failed("repack", e))?;
    let (counts, _) = count::objects(
        db.clone(),
        Box::new(ids.map(|id| id.map_err(gix::Error::from_error))),
        &Discard,
        should_interrupt,
        count::objects::Options {
            input_object_expansion: count::objects::ObjectExpansion::AsIs,
            ..Default::default()
        },
    )
    .map_err(|e| failed("repack", e))?;
    let num_entries = u32::try_from(counts.len()).map_err(|e| failed("repack", e))?;
    // Copies the entries of the existing packs, deltas included, so nothing is recompressed.
    let entries = entry::iter_from_counts(
        counts,
        db,
        Box::new(Discard),
        entry::iter_from_counts::Options::default(),
    )
    .map_err(|e| failed("repack", e))?;

    let temp = pack_dir.join(format!("tmp_repack_{}", Uuid::now_v7()));
    let result = write_and_index(&temp, &pack_dir, entries, num_entries, should_interrupt);
    let _ = std::fs::remove_file(&temp);
    let new_pack = result?;

    // Everything is in the new pack now.
    for pack in packs.iter().filter(|pack| **pack != new_pack) {
        for extension in ["keep", "idx", "rev", "bitmap", "mtimes", "promisor", "pack"] {
            remove_if_exists(&pack.with_extension(extension))?;
        }
    }
    // It would list the packs that are gone.
    remove_if_exists(&pack_dir.join("multi-pack-index"))?;
    for object in &loose {
        remove_if_exists(object)?;
    }
    Ok(())
}

/// Writes the pack to `temp`, then indexes it into `pack_dir`, which verifies it. Returns the
/// path of the pack.
fn write_and_index(
    temp: &Path,
    pack_dir: &Path,
    entries: impl Iterator<Item = gix::error::Result<(gix::parallel::SequenceId, Vec<output::Entry>)>>,
    num_entries: u32,
    should_interrupt: &AtomicBool,
) -> Result<PathBuf, AppError> {
    let file = File::create(temp).map_err(|e| failed("repack", e))?;
    let mut writer = output::bytes::FromEntriesIter::new(
        InOrderIter::from(entries),
        BufWriter::new(file),
        num_entries,
        gix::odb::pack::data::Version::V2,
        Kind::Sha1,
    );
    for written in &mut writer {
        written.map_err(|e| failed("repack", e))?;
    }
    writer
        .into_write()
        .into_inner()
        .map_err(|e| failed("repack", e.into_error()))?
        .sync_all()
        .map_err(|e| failed("repack", e))?;

    let mut pack = BufReader::new(File::open(temp).map_err(|e| failed("repack", e))?);
    let outcome = gix::odb::pack::Bundle::write_to_directory(
        &mut pack,
        Some(pack_dir),
        &mut Discard,
        should_interrupt,
        None::<gix::odb::Handle>,
        Kind::Sha1,
        Default::default(),
    )
    .map_err(|e| failed("repack", e))?;
    if let Some(keep) = &outcome.keep_path {
        remove_if_exists(keep)?;
    }
    outcome
        .data_path
        .ok_or_else(|| failed("repack", "the pack was not written"))
}

/// The `.pack` files in `pack_dir`.
fn list_packs(pack_dir: &Path) -> std::io::Result<Vec<PathBuf>> {
    let entries = match std::fs::read_dir(pack_dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(e),
    };
    let mut packs = Vec::new();
    for entry in entries {
        let path = entry?.path();
        if path.extension().is_some_and(|e| e == "pack") {
            packs.push(path);
        }
    }
    Ok(packs)
}

/// The files of the loose objects, in directories named after the first two hex digits of
/// their id. The directories are kept, git leaves them empty too.
fn list_loose_objects(objects_dir: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut objects = Vec::new();
    for entry in std::fs::read_dir(objects_dir)? {
        let entry = entry?;
        let name = entry.file_name();
        let is_fanout = name
            .to_str()
            .is_some_and(|n| n.len() == 2 && n.bytes().all(|b| b.is_ascii_hexdigit()));
        if is_fanout && entry.file_type()?.is_dir() {
            for object in std::fs::read_dir(entry.path())? {
                objects.push(object?.path());
            }
        }
    }
    Ok(objects)
}

fn remove_if_exists(path: &Path) -> Result<(), AppError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(failed("repack", format!("{}: {e}", path.display()))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mirror::git::tests::Fixture;
    use crate::service::mirror::git::{list_blobs, read_blobs};

    #[tokio::test]
    async fn combines_packs_and_loose_objects() {
        let fixture = Fixture::new();
        let mut commits = Vec::new();
        for i in 0..3 {
            let content = format!("version {i}\n").repeat(50);
            commits.push(fixture.commit(&[("doc.md", content.as_bytes())]));
            // Packs the loose objects of this commit only.
            fixture.git(&["repack", "-q"]);
        }
        // Left loose.
        let last = fixture.commit(&[("new.md", b"new")]);
        let git_dir = fixture.git_dir();
        assert_eq!(list_packs(&pack_dir(&git_dir)).unwrap().len(), 3);

        let interrupt = AtomicBool::new(false);
        consolidate_packs(&git_dir, 3, &interrupt).unwrap();
        assert_eq!(list_packs(&pack_dir(&git_dir)).unwrap().len(), 3);
        consolidate_packs(&git_dir, 2, &interrupt).unwrap();

        let packs = list_packs(&pack_dir(&git_dir)).unwrap();
        assert_eq!(packs.len(), 1);
        assert_eq!(
            std::fs::read_dir(pack_dir(&git_dir)).unwrap().count(),
            2,
            "only the pack and its index are left"
        );
        // git reads it too.
        fixture.git(&["fsck", "--strict", "--no-dangling"]);
        let count = fixture.git(&["count-objects", "-v"]);
        assert!(count.starts_with("count: 0\n"), "{count}");

        for (i, commit) in commits.iter().enumerate() {
            let blobs = list_blobs(&git_dir, commit).await.unwrap();
            let content = read_blobs(&git_dir, &[blobs[0].oid.clone()]).await.unwrap();
            assert_eq!(
                content[&blobs[0].oid],
                format!("version {i}\n").repeat(50).into_bytes()
            );
        }
        assert_eq!(list_blobs(&git_dir, &last).await.unwrap().len(), 2);
    }
}
