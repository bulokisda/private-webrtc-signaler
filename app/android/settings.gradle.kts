import java.io.File

pluginManagement {
    val flutterSdkPath = providers.gradleProperty("flutter.sdk")
        .orElse(
            providers.provider {
                val properties = java.util.Properties()
                val localPropertiesFile = settingsDir.resolve("local.properties")
                if (localPropertiesFile.exists()) {
                    localPropertiesFile.inputStream().use { properties.load(it) }
                }
                properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
            }
        ).get()

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")

// Parse the JSON string manually to find and include your background service, local notifications, and WebRTC plugins
val pluginsJsonFile = rootDir.parentFile.resolve(".flutter-plugins-dependencies")
if (pluginsJsonFile.exists()) {
    val text = pluginsJsonFile.readText()
    val regex = """"name"\s*:\s*"([^"]+)"\s*,\s*"path"\s*:\s*"([^"]+)"""".toRegex()
    regex.findAll(text).forEach { match ->
        val name = match.groupValues[1]
        val path = match.groupValues[2]
        // Only include actual Android native module folders
        val androidFolder = File(path, "android")
        if (androidFolder.exists() && name != "path_provider_android") {
            include(":$name")
            project(":$name").projectDir = androidFolder
        }
    }
}
