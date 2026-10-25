import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Preview builds keep their existing certificate so local updates retain data.
// Production is explicit and never falls back to the development key.
val productionSetting = providers.environmentVariable("HOMESPACE_PRODUCTION")
    .orElse(providers.gradleProperty("homespace.production"))
    .getOrElse("false")
val productionBuild = productionSetting.toBooleanStrictOrNull()
    ?: throw GradleException("HOMESPACE_PRODUCTION must be true or false.")
val uploadSigning = Properties()
if (productionBuild) {
    val signingFile = rootProject.file("key.properties")
    if (!signingFile.isFile) {
        throw GradleException("Production signing requires android/key.properties. See docs/android-release.md.")
    }
    signingFile.inputStream().use { uploadSigning.load(it) }
    for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if (uploadSigning.getProperty(name).isNullOrBlank()) {
            throw GradleException("Production signing is incomplete: missing $name.")
        }
    }
    if (!rootProject.file(uploadSigning.getProperty("storeFile")).isFile) {
        throw GradleException("The configured production keystore is unavailable.")
    }
}

android {
    namespace = "com.homespace.homespace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this ID stable for updates to the existing HomeSpace installation.
        applicationId = "com.homespace.homespace"
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
        if (productionBuild) {
            create("homespaceUpload") {
                storeFile = rootProject.file(uploadSigning.getProperty("storeFile"))
                storePassword = uploadSigning.getProperty("storePassword")
                keyAlias = uploadSigning.getProperty("keyAlias")
                keyPassword = uploadSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (productionBuild) "homespaceUpload" else "debug"
            )
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
