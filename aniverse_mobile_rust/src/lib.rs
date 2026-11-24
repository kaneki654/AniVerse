pub mod achievements;
pub mod api;
pub mod app;
pub mod downloads;
pub mod models;
pub mod player;
pub mod settings;
pub mod storage;
pub mod textures;
pub mod theme;

/// NativeActivity supplies the Android event loop on its own native thread.
/// Calling a desktop loop from Activity.onCreate would block Android's UI thread.
#[cfg(target_os = "android")]
#[no_mangle]
fn android_main(app: slint::android::AndroidApp) {
    if let Some(directory) = app.internal_data_path() {
        std::env::set_var("ANIVERSE_DATA_DIR", directory);
    }
    if let Err(error) = player::init_android(&app) {
        eprintln!("AniVerse player initialization failed: {error:#}");
    }
    if let Err(error) = slint::android::init(app) {
        eprintln!("AniVerse Android initialization failed: {error}");
        return;
    }
    if let Err(error) = app::run_android() {
        eprintln!("AniVerse failed: {error:#}");
    }
}
