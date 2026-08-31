import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, when a keystore is configured. `android/key.properties` is
// gitignored and holds storeFile / storePassword / keyAlias / keyPassword.
// Without it, release builds fall back to the debug key so they still install
// locally — and F-Droid's recipe strips signing entirely (see FDROID-STRIP
// below) so it can apply its own.
//
// Once a real key signs published APKs, back it up: losing it means never
// being able to ship an update anyone's existing install will accept.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The F-Droid recipe deletes the marked line so the APK comes out
            // unsigned for F-Droid to sign. Keep it on one line, and keep the
            // marker: the recipe seds on FDROID-STRIP, not on the code.
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug") // FDROID-STRIP
        }
    }
}

// One APK per ABI, with the version-code scheme F-Droid's submission guide
// asks for: `versionCode * 10 + abi`, ordered armeabi-v7a < arm64-v8a <
// x86_64. Flutter's own --split-per-abi scheme (1000/2000/4000 + code) puts
// the ABI in the high digits, which leaves no room to grow and ordered x86_64
// above a later release of arm64.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abi = output.filters.find { it.filterType == "ABI" }?.identifier
        val abiVersionCode = abiCodes[abi]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride =
                variant.versionCode * 10 + abiVersionCode
        }
    }
}

flutter {
    source = "../.."
}
