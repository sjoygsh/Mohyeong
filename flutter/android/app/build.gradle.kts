plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.mohyeong"
    // Pinned to 36 (latest stable) because flutter_plugin_android_lifecycle and
    // file_picker transitively require compileSdk >= 36. Flutter 3.44's default
    // (flutter.compileSdkVersion = 34) is too low.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications: it uses java.time APIs that
        // need core library desugaring to run on older Android API levels.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.mohyeong"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Install debug test builds under app.mohyeong.dev so they sit
            // alongside the user's existing release install (app.mohyeong)
            // instead of failing with a signing-key mismatch. The shipping
            // Flutter build still uses the real app.mohyeong id for the
            // eventual in-place update; only debug gets the suffix.
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // Backports java.time (and friends) used by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
