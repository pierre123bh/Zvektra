plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "net.zvektra.zvektra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "net.zvektra.zvektra"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=c++_static", "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    androidResources {
        noCompress += "bin"
    }

    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/whisperAssets"))

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            proguardFiles("proguard-rules.pro")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Keep the newer native VLC runtime while using the bridge compatible with
// the published Flutter platform interface.
dependencies {
    implementation("org.videolan.android:libvlc-all:3.6.3")
}

val whisperAssets = layout.buildDirectory.dir("generated/whisperAssets/whisper")
val prepareWhisperModel by tasks.registering(Exec::class) {
    val script = rootProject.file("../tools/prepare-whisper-model.sh")
    inputs.file(script)
    outputs.file(whisperAssets.map { it.file("ggml-tiny-q5_1.bin") })
    commandLine("bash", script.absolutePath, whisperAssets.get().asFile.absolutePath)
}
tasks.named("preBuild") {
    dependsOn(prepareWhisperModel)
}
