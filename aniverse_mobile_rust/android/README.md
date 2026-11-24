# Android host

The Rust application runs through Slint's **NativeActivity** backend. Android calls
`android_main` from `libaniverse_rust.so`; it does not run Slint on Android's Java UI
thread. The library name, entry point, manifest metadata and Gradle output agree.

The package ID remains `app.aniverse.rust`. It installs alongside the Flutter
application, so development builds do not replace the existing app or share its
private data. The Flutter update feed must not be used by this package.

## Build

Required: Rust, the `aarch64-linux-android` target, Android SDK platform 35, Android
NDK r28 or newer, and JDK 17 or 21. Gradle 8.11.1 is provided through the wrapper.
The default ARM64 APK supports the Samsung A05 and other ARM64 Android 7+ devices.

```sh
rustup target add aarch64-linux-android
export ANDROID_HOME="$HOME/Android/Sdk"
export JAVA_HOME=/path/to/jdk-17
./scripts/build_android.sh
```

Run from `aniverse_mobile_rust`. The script selects the installed NDK or honors
`ANDROID_NDK_ROOT`. It compiles the release Rust library, copies it into
`android/app/src/main/jniLibs/arm64-v8a`, and builds a debug APK at:

`android/app/build/outputs/apk/debug/app-debug.apk`

Gradle's `preBuild` depends on `buildRust`, so rebuilding through Android Studio
also rebuilds the Rust code. For a native-only build, use
`./scripts/build_android.sh --native-only`. Generated native libraries and build
outputs are ignored by Git. This development APK is not a production release;
release signing and a separate Rust release feed must be configured before
replacing it with distributed builds.

## Playback

`player::play(PlaybackRequest)` invokes `MainActivity.playStream` through JNI.
The Android main thread creates a Media3 overlay with HLS/DASH/file playback,
seek/resume/speed, captions, buffering, retry, intro/outro skip and picture in
picture. Back closes the overlay and returns to the catalog. Progress events
are queued in Rust for the application controller to persist in history.

Caption size, color, background, language and seek step follow the request's
settings. Audio focus is managed by Media3. The catalog data stays in Android's
private files directory, selected before the Rust UI is constructed.

The player currently uses Media3's native control layout rather than Flutter's
custom animated controls. Continuous background playback has no foreground
service yet, and MediaSession/notification controls, casting, watch parties and
Google authentication are not supplied by this Android host.

References: [Slint 1.9.2 Android entry point](https://github.com/slint-ui/slint/blob/v1.9.2/api/rs/slint/android.rs),
[Media3 setup](https://developer.android.com/media/media3/exoplayer/hello-world).
