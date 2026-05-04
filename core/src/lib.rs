uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn ping() -> String {
    "pong from Rust".to_string()
}

#[uniffi::export]
pub fn system_info() -> String {
    format!("tap-talk-core v{}, aarch64-apple-darwin", env!("CARGO_PKG_VERSION"))
}
