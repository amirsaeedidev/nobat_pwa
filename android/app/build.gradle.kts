import com.android.build.api.dsl.ApplicationExtension

plugins {
    id("com.android.application")
    // AGP 9 provides Kotlin support natively; do not apply kotlin-android.
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterCompileSdk = flutter.compileSdkVersion
val flutterNdkVersion = flutter.ndkVersion
val flutterMinSdk = flutter.minSdkVersion
val flutterTargetSdk = flutter.targetSdkVersion
val flutterVersionCode = flutter.versionCode
val flutterVersionName = flutter.versionName

extensions.configure<ApplicationExtension> {
    namespace = "com.datetime.datetime"
    compileSdk = flutterCompileSdk
    ndkVersion = flutterNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.datetime.datetime"
        minSdk = flutterMinSdk
        targetSdk = flutterTargetSdk
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        // Enforce ARM64 at the Android packaging layer as well as the Flutter CLI.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        getByName("release") {
            // Debug signing is intentionally retained for downloadable test APKs.
            // A production signing key must be configured before store distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
