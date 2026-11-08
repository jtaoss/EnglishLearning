import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Flutter forwards --dart-define to Gradle; it does not reliably forward
    // arbitrary ORG_GRADLE_PROJECT variables through its build subprocess.
    val acceptanceBuild = providers.gradleProperty("dart-defines").orNull
        ?.split(",")?.any {
            String(Base64.getDecoder().decode(it)) == "ANDROID_ACCEPTANCE=true"
        } == true
    namespace = "dev.personal.englishlearning"
    compileSdk = flutter.compileSdkVersion
    // Follow flutter.ndkVersion from the Flutter SDK. This release resolves
    // that value to 28.2.13676358, which is also what the engine and the
    // Android plugins expect. Do not replace it with a machine-local NDK.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.personal.englishlearning"
        if (acceptanceBuild) applicationIdSuffix = ".acceptance"
        manifestPlaceholders["learningAppLabel"] = if (acceptanceBuild) "英语学习·隔离验收" else "英语学习"
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

    buildTypes {
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
