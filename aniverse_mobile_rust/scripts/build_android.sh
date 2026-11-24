#!/usr/bin/env bash
# Build Slint's Android library, then package the NativeActivity + Media3 host.
set -euo pipefail
aniverse_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---apk}"
if [[ "$mode" != "--apk" && "$mode" != "--native-only" ]]; then
  echo "Usage: $0 [--apk|--native-only]" >&2
  exit 2
fi
aniverse_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
aniverse_ndk="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
if [[ -z "$aniverse_ndk" && -d "$aniverse_sdk/ndk" ]]; then
  aniverse_ndk="$(find "$aniverse_sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
fi
case "$(uname -s)" in
  Linux) aniverse_host=linux-x86_64 ;;
  Darwin) aniverse_host=darwin-x86_64 ;;
  *) echo "Use Linux/macOS with the Android NDK to run this build script." >&2; exit 1 ;;
esac
aniverse_toolchain="$aniverse_ndk/toolchains/llvm/prebuilt/$aniverse_host/bin"
if [[ ! -x "$aniverse_toolchain/aarch64-linux-android24-clang" ]]; then
  echo "Install Android NDK r28+, then set ANDROID_NDK_ROOT and ANDROID_HOME." >&2
  exit 1
fi
if ! rustup target list --installed | grep -qx aarch64-linux-android; then
  echo "Install the Android Rust target: rustup target add aarch64-linux-android" >&2
  exit 1
fi
export ANDROID_HOME="$aniverse_sdk"
export ANDROID_NDK_ROOT="$aniverse_ndk"
export ANDROID_NDK_HOME="$aniverse_ndk"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$aniverse_toolchain/aarch64-linux-android24-clang"
export CC_aarch64_linux_android="$aniverse_toolchain/aarch64-linux-android24-clang"
export CXX_aarch64_linux_android="$aniverse_toolchain/aarch64-linux-android24-clang++"
export AR_aarch64_linux_android="$aniverse_toolchain/llvm-ar"
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"
# Its own target folder: the Android build (Skia included) is kept apart from the desktop one.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$aniverse_root/target/android-build}"
cd "$aniverse_root"
cargo build --locked --release --lib --target aarch64-linux-android
aniverse_target="$CARGO_TARGET_DIR"
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp "$aniverse_target/aarch64-linux-android/release/libaniverse_rust.so" android/app/src/main/jniLibs/arm64-v8a/
if [[ "$mode" == "--apk" ]]; then
  # Gradle 9.3 runs on JDK 17-25 and needs a full JDK (javac, jlink). Without
  # JAVA_HOME, use the one Gradle provisioned for aniverse_mobile, if it is there.
  if [[ -z "${JAVA_HOME:-}" ]]; then
    for jdk in "$HOME"/.gradle/jdks/*/; do
      if [[ -x "$jdk/bin/javac" ]]; then export JAVA_HOME="${jdk%/}"; break; fi
    done
  fi
  if [[ -n "${JAVA_HOME:-}" ]]; then aniverse_java="$JAVA_HOME/bin/java"; else aniverse_java=java; fi
  aniverse_java_version="$($aniverse_java -version 2>&1 | head -1)"
  if [[ "$aniverse_java_version" =~ \"([0-9]+) ]] && (( BASH_REMATCH[1] < 17 || BASH_REMATCH[1] > 25 )); then
    echo "Set JAVA_HOME to a JDK 17-25 installation before packaging the APK." >&2
    exit 1
  fi
  cd android
  ./gradlew :app:assembleDebug --console=plain
  echo "APK: $aniverse_root/android/app/build/outputs/apk/debug/app-debug.apk"
fi
