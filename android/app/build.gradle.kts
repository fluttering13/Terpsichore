import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadKeyProperties = Properties()
val uploadKeyFile = rootProject.file("key.properties")
if (uploadKeyFile.exists()) {
    uploadKeyFile.inputStream().use { uploadKeyProperties.load(it) }
}

android {
    namespace = "com.fluttering13.terpsichore"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fluttering13.terpsichore"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["emotionLauncherAlias"] = "FlutterLauncherIcon"
    }

    signingConfigs {
        create("release") {
            keyAlias = uploadKeyProperties.getProperty("keyAlias")
            keyPassword = uploadKeyProperties.getProperty("keyPassword")
            storeFile = uploadKeyProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = uploadKeyProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        debug {
            // Keep this component name stable so launcher caches cannot retain
            // a new Terpsichore shortcut after every debug installation.
            manifestPlaceholders["emotionLauncherAlias"] = "FlutterDebugLauncher"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        jniLibs.useLegacyPackaging = true
        // These .so-named files are runtime archives, not ELF libraries.
        jniLibs.keepDebugSymbols += setOf("**/libpython.zip.so", "**/libffmpeg.zip.so")
    }

    androidResources {
        noCompress += listOf("onnx")
        // Local Python regression checks must not add bytecode to the APK.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:.*:!CVS:!thumbs.db:!picasa.ini:!*~:__pycache__:*.pyc"
    }
}

tasks.matching { it.name == "validateSigningRelease" }.configureEach {
    doFirst {
        check(uploadKeyFile.exists()) {
            "Release signing requires android/key.properties and an upload keystore. See docs/internal-testing.md."
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

// Building must never mutate an installed app's launcher state. When a dynamic
// alias is active, launch MainActivity explicitly instead of resetting icons.

dependencies {
    implementation("com.antonkarpenko:ffmpeg-kit-min-gpl:2.2.2")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    // Android pose uses Accurate; ONNX remains required by music stem separation.
    implementation("com.google.mlkit:pose-detection-accurate:18.0.0-beta5")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.23.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("junit:junit:4.13.2")
}
