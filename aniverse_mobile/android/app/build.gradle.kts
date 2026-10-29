import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Updates must use the key that signed the installed app. Never silently use
// this computer's debug key for releases: it can produce an incompatible APK.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val requiredSigningProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningProperties = requiredSigningProperties.filter {
    keystoreProperties.getProperty(it).isNullOrBlank()
}
val releaseKeystore = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }?.let { file(it) }
val releaseSigningError = when {
    !keystorePropertiesFile.isFile ->
        "Missing android/key.properties."
    missingSigningProperties.isNotEmpty() ->
        "Missing signing properties: ${missingSigningProperties.joinToString()} in android/key.properties."
    releaseKeystore?.isFile != true ->
        "The storeFile in android/key.properties does not point to an existing keystore (relative paths start at android/app/)."
    else -> null
}

// Keep debug builds usable without release credentials, but block both release
// APK and app-bundle builds before they can bypass explicit signing setup.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        check(releaseSigningError == null) {
            "$releaseSigningError Restore the keystore that signed the installed AniVerse APK " +
                "and configure android/key.properties; see SETUP.md, Signing. " +
                "Generating a new key cannot fix updates for existing installations."
        }
    }
}

android {
    namespace = "com.example.aniverse_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.aniverse_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningError == null) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseKeystore
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Chromecast: the Cast framework, with the device picker (androidx.mediarouter).
    implementation("com.google.android.gms:play-services-cast-framework:22.3.1")
    // Its device picker dialogs, used directly (CastBridge.kt), so on the compile path too.
    implementation("androidx.mediarouter:mediarouter:1.8.1")
    implementation("androidx.appcompat:appcompat:1.7.1")
}
