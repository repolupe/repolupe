//! Passes the xberg version pinned in `Cargo.toml` to the crate as `XBERG_VERSION`, which
//! identifies the stored extractions (`EXTRACTOR` in `service/extraction.rs`).

fn main() {
    println!("cargo:rerun-if-changed=Cargo.toml");
    let manifest = std::fs::read_to_string("Cargo.toml").expect("Cargo.toml can be read");
    let version = manifest
        .lines()
        .find_map(|line| line.strip_prefix("xberg = "))
        .and_then(|spec| spec.split('"').find_map(|part| part.strip_prefix('=')))
        .expect("xberg is pinned to an exact version (`=x.y.z`) in Cargo.toml");
    println!("cargo:rustc-env=XBERG_VERSION={version}");
}
