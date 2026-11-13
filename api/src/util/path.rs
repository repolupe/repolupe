/// Whether the extension of the file at `path` is one of `extensions`, in any case.
pub(crate) fn has_extension(path: &str, extensions: &[&str]) -> bool {
    path.rsplit_once('.')
        .is_some_and(|(_, extension)| extensions.iter().any(|e| e.eq_ignore_ascii_case(extension)))
}
