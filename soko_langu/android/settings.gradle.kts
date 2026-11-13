pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

// dynamic_color 1.9.0 declares the Kotlin Gradle plugin on its buildscript
// classpath but never applies it, so its `kotlin { compilerOptions {} }`
// block fails script compilation. Apply our KGP to that module here instead
// of patching the pub cache, which would not survive `flutter pub get`.
gradle.beforeProject {
    if (name == "dynamic_color") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
}

include(":app")
