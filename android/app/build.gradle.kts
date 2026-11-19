import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val dahuaSdk = providers.environmentVariable("DAHUA_NETSDK_DIR").orNull?.let { file(it) }

android {
    sourceSets.getByName("main").apply {
        if (dahuaSdk == null) {
            java.srcDir("src/noDahuaNetSdk/java")
        } else {
            java.srcDir("src/dahuaNetSdk/java")
            jniLibs.srcDir(dahuaSdk.resolve("jniLibs"))
        }
    }
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
        applicationId = "net.zvektra.zvektra.whisper"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    testBuildType = "release"

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
    if (dahuaSdk != null) implementation(files(dahuaSdk.resolve("INetSDK.jar")))
    implementation("org.videolan.android:libvlc-all:3.6.3")
    // 1.20.0 keeps the app compatible with its Android 6 minimum.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
    androidTestImplementation("androidx.test:runner:1.2.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

// Bundle pinned weights in the APK so playback detection works offline.
val detectionAssets = layout.buildDirectory.dir("generated/detectionAssets")
val detectionModels = mapOf(
    "people" to (
        "https://huggingface.co/onnxmodelzoo/ssd_mobilenet_v1_12-int8/resolve/929618539097dbeb779c13aed75dfe346d016d48/ssd_mobilenet_v1_12-int8.onnx" to
        "2b79e6a7fb1ec6a33f332b9b10d82d9de4b7b49dcd26b5946921bb356895c954"
    ),
    "plates" to (
        "https://github.com/ankandrew/open-image-models/releases/download/assets/yolo-v9-t-384-license-plates-end2end.onnx" to
        "888397b96d761c89db40bc9c305838e8652660f5e282c2cadebbe8d2951a77a8"
    ),
)
val prepareDetectionModels by tasks.registering {
    inputs.property("models", detectionModels.mapValues { it.value.toList() })
    outputs.dir(detectionAssets)
    doLast {
        val folder = detectionAssets.get().dir("detection").asFile
        folder.mkdirs()
        for ((name, source) in detectionModels) {
            val (url, checksum) = source
            val model = folder.resolve("$name.onnx")
            val staged = folder.resolve("$name.download")
            try {
                val connection = URI.create(url).toURL().openConnection()
                connection.connectTimeout = 30_000
                connection.readTimeout = 60_000
                connection.getInputStream().use { input ->
                    staged.outputStream().use { input.copyTo(it) }
                }
                val actual = MessageDigest.getInstance("SHA-256")
                    .digest(staged.readBytes()).joinToString("") { "%02x".format(it) }
                check(actual == checksum) { "Unexpected checksum for $name detection model" }
                staged.copyTo(model, overwrite = true)
            } finally {
                staged.delete()
            }
        }
    }
}
android.sourceSets.getByName("main").assets.srcDir(detectionAssets)
tasks.named("preBuild").configure { dependsOn(prepareDetectionModels) }
