//! [`MOVE_FILES`]: proposes a commit that moves or renames files and directories, which the
//! user reviews and pushes like the changes of [`CHANGE_FILE`].

use super::support::commit::{Identity, check_outside_git, moved_files, parse_commit_message};
use super::support::{
    missing_path, normalize_path, parent_dirs, parse_args, plural, writable_repository_schema,
};
use super::{CHANGE_FILE, Call, Invocation, LIST_FILES, MOVE_FILES, RepositoryTools, ToolError};
use crate::model::tool_call::{ChangedPaths, FileMove, ProposedChange};
use crate::service::llm::ToolDefinition;
use crate::service::mirror::{PathEntry, Signature};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};
use std::fmt::Write;

/// The most moves in one call, since the user reviews each.
const MAX_MOVES: usize = 100;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: MOVE_FILES.to_string(),
        description: format!(
            "Propose a commit that moves or renames files and folders. Nothing is committed \
            yet: the proposal appears below your answer, and the user decides whether to commit \
            it. Each call starts from the repository as you read it, and the other tools don't \
            see the change, so make all moves in one call; calling it again for the same \
            repository replaces the earlier proposal. Don't also change a file you move with \
            {CHANGE_FILE}, the two proposals would conflict. Unless the user named the place, \
            look with {LIST_FILES} where similar files are kept and follow their naming."
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": writable_repository_schema(tools, "The repository to change."),
                "moves": {
                    "type": "array",
                    "minItems": 1,
                    "maxItems": MAX_MOVES,
                    "description": "What to move. All moves start from the repository as you \
                        read it, so their order doesn't matter, and no path may be inside \
                        another move's paths.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "from": {
                                "type": "string",
                                "description": "Path of an existing file or folder, relative \
                                    to the repository root.",
                            },
                            "to": {
                                "type": "string",
                                "description": "Its new path, including its own name, e.g. \
                                    `invoices/2026/acme.pdf`, not just the folder to move it \
                                    into. Must not exist yet.",
                            },
                        },
                        "required": ["from", "to"],
                    },
                },
                "message": {
                    "type": "string",
                    "description": "The commit message: a summary of at most about \
                        70 characters, e.g. `Sort the 2026 invoices by month`.",
                },
            },
            "required": ["repository", "moves", "message"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    moves: Vec<MoveInput>,
    message: String,
}

#[derive(Deserialize)]
struct MoveInput {
    from: String,
    to: String,
}

pub(super) struct Args {
    /// None inside another's paths.
    moves: Vec<FileMove>,
    message: String,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(MOVE_FILES, input)?;
    if input.moves.is_empty() {
        return Err("`moves` must not be empty.".to_string());
    }
    if input.moves.len() > MAX_MOVES {
        return Err(format!(
            "`moves` must have at most {MAX_MOVES} entries. Propose the rest once the user \
            committed these."
        ));
    }
    let mut moves = Vec::new();
    for MoveInput { from, to } in input.moves {
        let from = parse_move_path("from", &from)?;
        let to = parse_move_path("to", &to)?;
        if from == to {
            return Err(format!("`{from}` would stay where it is."));
        }
        if is_within(&to, &from) {
            return Err(format!("`{from}` can't be moved into itself."));
        }
        moves.push(FileMove { from, to });
    }
    check_overlaps(&moves)?;
    let args = Args {
        moves,
        message: parse_commit_message(&input.message)?,
    };
    Ok((input.repository, Call::MoveFiles(args)))
}

fn parse_move_path(field: &str, path: &str) -> Result<String, String> {
    let path = normalize_path(path)?;
    if path.is_empty() {
        return Err(format!("`{field}` must not be the repository root."));
    }
    check_outside_git(&path)?;
    Ok(path)
}

/// Whether `path` is `dir` or inside it.
fn is_within(path: &str, dir: &str) -> bool {
    path.strip_prefix(dir)
        .is_some_and(|rest| rest.is_empty() || rest.starts_with('/'))
}

/// Fails if a path of one move is inside a path of another, so the moves can be made, and
/// checked, one by one against the repository as the model read it.
fn check_overlaps(moves: &[FileMove]) -> Result<(), String> {
    let paths: Vec<&str> = moves
        .iter()
        .flat_map(|m| [m.from.as_str(), m.to.as_str()])
        .collect();
    for (i, a) in paths.iter().enumerate() {
        for (j, b) in paths.iter().enumerate() {
            if i / 2 == j / 2 || !is_within(a, b) {
                continue;
            }
            return Err(if a == b {
                format!("`{a}` is in more than one move.")
            } else {
                format!(
                    "`{a}` is inside `{b}`, which another move moves or creates. Moves must not \
                    overlap: move the folder as a whole, or the files in it one by one."
                )
            });
        }
    }
    Ok(())
}

/// Proposes a commit that makes the moves, which must not leave files stored with Git LFS
/// outside of it or the other way around. Returns the output for the model.
pub(super) async fn run(
    invocation: &Invocation<'_>,
    args: &Args,
) -> Result<(String, ProposedChange), ToolError> {
    let repository = invocation.target()?;
    let identities = invocation.identities;
    let snapshot = &repository.snapshot;
    let mut folders = Vec::new();
    for FileMove { from, to } in &args.moves {
        let entry = snapshot.entry(from).await?;
        if let PathEntry::Missing = entry {
            return Err(missing_path(repository, from).await?);
        }
        match snapshot.entry(to).await? {
            PathEntry::Missing => {}
            PathEntry::Tree => {
                let name = from.rsplit('/').next().unwrap_or(from);
                return Err(ToolError::Invalid(format!(
                    "`{to}` is an existing folder. Pass the new path of `{from}` itself, e.g. \
                    `{to}/{name}`."
                )));
            }
            PathEntry::Blob { .. } | PathEntry::Other => {
                return Err(ToolError::Invalid(format!(
                    "`{to}` already exists. Choose another path."
                )));
            }
        }
        for dir in parent_dirs(to) {
            if let PathEntry::Blob { .. } | PathEntry::Other = snapshot.entry(dir).await? {
                return Err(ToolError::Invalid(format!(
                    "`{dir}` is a file, so `{to}` can't be created."
                )));
            }
        }
        folders.push(matches!(entry, PathEntry::Tree));
    }

    let now = Utc::now();
    let signature = |identity: &Identity| Signature {
        name: identity.name.clone(),
        email: identity.email.clone(),
        time: now,
    };
    let pairs: Vec<(String, String)> = args
        .moves
        .iter()
        .map(|m| (m.from.clone(), m.to.clone()))
        .collect();
    let commit = snapshot
        .commit_moves(
            &pairs,
            &args.message,
            &signature(&identities.author),
            &signature(&identities.committer),
        )
        .await?;

    // Pointers are moved as they are, so they must stay where `.gitattributes` assigns files
    // to LFS, as it is after the moves.
    let files = moved_files(snapshot, &args.moves).await?;
    let (sources, destinations): (Vec<String>, Vec<String>) = files.iter().cloned().unzip();
    let before = snapshot.lfs_paths(sources).await?;
    let after = snapshot
        .at_commit(commit.clone())
        .lfs_paths(destinations)
        .await?;
    for ((from, to), (before, after)) in files.iter().zip(before.into_iter().zip(after)) {
        if before != after {
            return Err(ToolError::Invalid(if before {
                format!(
                    "`{from}` is stored with Git LFS, but files at `{to}` are not, so it can't \
                    be moved there."
                )
            } else {
                format!(
                    "Files at `{to}` are stored with Git LFS, but `{from}` is not, so it can't \
                    be moved there."
                )
            }));
        }
    }

    let mut output = "Proposed a commit that moves:\n".to_string();
    for (FileMove { from, to }, folder) in args.moves.iter().zip(folders) {
        let _ = write!(output, "- `{from}` → `{to}`");
        if folder {
            let count = files.iter().filter(|(f, _)| is_within(f, from)).count();
            let _ = write!(output, " (folder with {})", plural(count, "file"));
        }
        output.push('\n');
    }
    let _ = write!(
        output,
        "It is not committed yet: the user sees it below your answer and decides whether to \
        commit it. To revise it, call {MOVE_FILES} for `{}` again with all moves.",
        repository.name
    );
    Ok((
        output,
        ProposedChange {
            changed: ChangedPaths::Moves(args.moves.clone()),
            proposed_commit: commit,
        },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mirror::Snapshot;
    use crate::service::tools::read_proposed_commit_patch;
    use crate::service::tools::support::fixture::{Fixture, LFS_POINTER, docs};

    async fn propose(fixture: &Fixture, input: Value) -> (String, ProposedChange) {
        let output = fixture.run(MOVE_FILES, input).await;
        assert!(!output.is_error, "{}", output.content);
        (output.content, output.change.unwrap())
    }

    #[tokio::test]
    async fn proposes_moves() {
        let fixture = docs();
        let (output, change) = propose(
            &fixture,
            json!({
                "repository": "docs",
                "moves": [
                    {"from": "./docs/", "to": "archive/docs"},
                    {"from": "README.md", "to": "archive/README.md"},
                ],
                "message": "Archive the docs",
            }),
        )
        .await;
        assert_eq!(
            output,
            "Proposed a commit that moves:\n\
            - `docs` → `archive/docs` (folder with 2 files)\n\
            - `README.md` → `archive/README.md`\n\
            It is not committed yet: the user sees it below your answer and decides whether to \
            commit it. To revise it, call move_files for `docs` again with all moves."
        );
        let moves = vec![
            FileMove {
                from: "docs".to_string(),
                to: "archive/docs".to_string(),
            },
            FileMove {
                from: "README.md".to_string(),
                to: "archive/README.md".to_string(),
            },
        ];
        assert_eq!(change.changed, ChangedPaths::Moves(moves));

        // One commit on top of the snapshot that only moves them.
        let base = fixture.git(&["rev-parse", "HEAD"]);
        let parent = fixture.git(&["rev-parse", &format!("{}^", change.proposed_commit)]);
        assert_eq!(parent, base);
        assert_eq!(
            fixture.git(&[
                "diff",
                "--name-status",
                "-M",
                "HEAD",
                &change.proposed_commit
            ]),
            "R100\tREADME.md\tarchive/README.md\n\
            R100\tdocs/faq/limits.md\tarchive/docs/faq/limits.md\n\
            R100\tdocs/guide.md\tarchive/docs/guide.md\n"
        );
        assert_eq!(
            fixture.git(&[
                "log",
                "-1",
                "--format=%an%n%cn%n%B",
                &change.proposed_commit
            ]),
            "Repolupe+model\nAlice\nArchive the docs\n\n"
        );

        // The patch makes the same moves.
        let repository = &fixture.tools.repositories()[0];
        let proposed = Snapshot::at(fixture.dir.join(".git"), change.proposed_commit.clone());
        let patch = read_proposed_commit_patch(repository, &proposed, &change.changed)
            .await
            .unwrap();
        assert!(
            patch.contains(
                "---\ndiff --git a/docs/faq/limits.md b/archive/docs/faq/limits.md\n\
                similarity index 100%\n\
                rename from docs/faq/limits.md\n\
                rename to archive/docs/faq/limits.md\n"
            ),
            "{patch}"
        );
        let patch_file = fixture.dir.join("moves.patch");
        std::fs::write(&patch_file, &patch).unwrap();
        fixture.git(&["apply", "--index", patch_file.to_str().unwrap()]);
        assert_eq!(
            fixture.git(&[
                "diff",
                "--cached",
                "--name-status",
                "-M",
                &change.proposed_commit
            ]),
            ""
        );
    }

    #[tokio::test]
    async fn keeps_git_lfs_files_in_git_lfs() {
        let fixture = Fixture::new(&[
            (
                ".gitattributes",
                b"*.pdf filter=lfs diff=lfs merge=lfs -text\n",
            ),
            ("scans/a.pdf", LFS_POINTER),
            ("notes.txt", b"notes"),
        ]);
        let moves =
            |from: &str, to: &str| json!({"moves": [{"from": from, "to": to}], "message": "Move"});
        let (_, change) = propose(&fixture, moves("scans", "archive/scans")).await;
        assert_eq!(
            fixture.git(&[
                "show",
                &format!("{}:archive/scans/a.pdf", change.proposed_commit)
            ]),
            String::from_utf8(LFS_POINTER.to_vec()).unwrap()
        );
        assert_eq!(
            fixture
                .error(MOVE_FILES, moves("scans/a.pdf", "a.bin"))
                .await,
            "`scans/a.pdf` is stored with Git LFS, but files at `a.bin` are not, so it can't be \
            moved there."
        );
        assert_eq!(
            fixture
                .error(MOVE_FILES, moves("notes.txt", "notes.pdf"))
                .await,
            "Files at `notes.pdf` are stored with Git LFS, but `notes.txt` is not, so it can't \
            be moved there."
        );
    }

    #[tokio::test]
    async fn explains_rejected_moves() {
        let fixture = docs();
        let error =
            |moves: Value| fixture.error(MOVE_FILES, json!({"moves": moves, "message": "Move"}));
        let one = |from: &str, to: &str| json!([{"from": from, "to": to}]);
        assert_eq!(
            error(one("docs/install.md", "install.md")).await,
            "File or directory not found: `docs/install.md`. Use list_files to see the files."
        );
        assert_eq!(
            error(one("logo.png", "README.md")).await,
            "`README.md` already exists. Choose another path."
        );
        assert_eq!(
            error(one("logo.png", "docs")).await,
            "`docs` is an existing folder. Pass the new path of `logo.png` itself, e.g. \
            `docs/logo.png`."
        );
        assert_eq!(
            error(one("logo.png", "README.md/logo.png")).await,
            "`README.md` is a file, so `README.md/logo.png` can't be created."
        );
        assert_eq!(
            error(one("docs", "docs/old")).await,
            "`docs` can't be moved into itself."
        );
        assert_eq!(
            error(one("docs/", "./docs")).await,
            "`docs` would stay where it is."
        );
        assert_eq!(
            error(json!([
                {"from": "docs", "to": "archive/docs"},
                {"from": "docs/guide.md", "to": "guide.md"},
            ]))
            .await,
            "`docs/guide.md` is inside `docs`, which another move moves or creates. Moves must \
            not overlap: move the folder as a whole, or the files in it one by one."
        );
        assert_eq!(
            error(json!([
                {"from": "logo.png", "to": "img/logo.png"},
                {"from": "slides.pdf", "to": "img/logo.png"},
            ]))
            .await,
            "`img/logo.png` is in more than one move."
        );
        assert_eq!(
            error(one("", "x")).await,
            "`from` must not be the repository root."
        );
        assert_eq!(
            error(one("logo.png", ".git/logo.png")).await,
            "Files in `.git` can't be changed."
        );
        assert_eq!(error(json!([])).await, "`moves` must not be empty.");
    }
}
