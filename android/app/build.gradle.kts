plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.veciata.tsmusic"
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.veciata.tsmusic"
        minSdk = flutter.minSdkVersion  // Minimum SDK 21 (Android 5.0) for audio_service compatibility
        targetSdk = 34  // Target SDK 34 (Android 14) to avoid obsolete warnings
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystore = System.getenv("KEYSTORE_PATH")
            if (keystore != null) {
                storeFile = file(keystore)
                storePassword = System.getenv("KEY_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release")?.takeIf {
                it.storeFile != null
            } ?: signingConfigs.getByName("debug")
        }
    }
}

// Kotlin is compiled by AGP 9's built-in Kotlin support (see
// android.builtInKotlin=true in gradle.properties), so KGP is not applied here.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// GeneratedPluginRegistrant.java is a generated source file that the Flutter tool
// rewrites per build. Flutter's Gradle plugin excludes dev-dependency plugins
// (integration_test) from release builds, so a registrant left behind by a previous
// debug build makes compileReleaseJavaWithJavac fail with an opaque
// "package dev.flutter.plugins.integration_test does not exist". Catch that here
// with an actionable message rather than a confusing javac error.
val verifyPluginRegistrant = tasks.register("verifyPluginRegistrantForRelease") {
    val registrant = layout.projectDirectory
        .file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    // .flutter-plugins-dependencies is written to the Flutter project root, which
    // is one level above the Gradle root project (android/).
    val pluginsDependencies = rootProject.layout.projectDirectory
        .dir("..").file(".flutter-plugins-dependencies")

    inputs.files(registrant, pluginsDependencies)
        .withPropertyName("pluginMetadata")
        .withPathSensitivity(PathSensitivity.RELATIVE)

    doLast {
        val registrantFile = registrant.asFile
        val pluginsFile = pluginsDependencies.asFile
        if (!registrantFile.isFile) return@doLast
        if (!pluginsFile.isFile) {
            throw GradleException(
                "Cannot verify GeneratedPluginRegistrant.java: ${pluginsFile.absolutePath} not found."
            )
        }

        @Suppress("UNCHECKED_CAST")
        val metadata = groovy.json.JsonSlurper().parse(pluginsFile) as Map<*, *>
        val androidPlugins = (metadata["plugins"] as? Map<*, *>)?.get("android") as? List<*>
            ?: return@doLast

        val devDependencyPlugins = androidPlugins
            .filterIsInstance<Map<*, *>>()
            .filter { it["dev_dependency"] == true }
            .mapNotNull { it["name"] as? String }

        val registrantSource = registrantFile.readText()
        val stale = devDependencyPlugins.filter {
            registrantSource.contains("Error registering plugin $it,")
        }
        if (stale.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine()
                    appendLine("GeneratedPluginRegistrant.java registers dev-dependency plugin(s)")
                    appendLine("  ${stale.joinToString()}")
                    appendLine()
                    appendLine("Flutter excludes these from release builds, so their classes are not on the")
                    appendLine("release compile classpath and this build cannot succeed.")
                    appendLine()
                    appendLine("Cause: the Flutter tool only regenerates this file when it runs 'pub get'.")
                    appendLine("When pub is skipped, the file written by the previous build is reused, so a")
                    appendLine("preceding debug build leaves dev-dependency plugins registered here.")
                    appendLine()
                    appendLine("Fix (regenerates it for a release build):")
                    appendLine("  flutter build apk --release --config-only")
                    appendLine("then re-run your original build command.")
                    appendLine()
                    appendLine("Stale file: $registrantFile")
                    appendLine()
                }
            )
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyPluginRegistrant)
}

flutter {
    source = "../.."
}

dependencies {
    constraints {
        implementation("androidx.glance:glance-appwidget:1.2.0") {
            because("home_widget 0.10.0 requires glance 1.2.0")
        }
    }
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
