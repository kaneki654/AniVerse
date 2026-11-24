#[cfg(not(target_os = "android"))]
fn main() {
    if let Err(error) = aniverse_rust::app::run_desktop() {
        eprintln!("AniVerse failed: {error:#}");
        std::process::exit(1);
    }
}
#[cfg(target_os = "android")]
fn main() {}
