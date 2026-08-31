plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.linguapop.linguapop"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than tracking flutter.ndkVersion: the F-Droid build
    // recipe has to name an NDK the buildserver provides, and it must match
    // whatever the vendored MeCab is compiled against here.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.linguapop.linguapop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Raised from flutter.minSdkVersion (16) to 21 because mecab_dart's
        // bundled native MeCab requires NDK platform 21+.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // No release keystore: local and GitHub-release builds are signed
            // with the debug key so they install without one. The F-Droid
            // recipe deletes the line below and signs with F-Droid's key —
            // keep it on one line and textually distinctive.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
