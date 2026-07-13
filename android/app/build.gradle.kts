plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") version "2.2.20"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.veciata.tsmusic"
    compileSdk = flutter.compileSdkVersion
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

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.whenTaskAdded {
    if (name.startsWith("check") && name.endsWith("AarMetadata")) {
        enabled = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    constraints {
        implementation("androidx.glance:glance-appwidget:1.1.1") {
            because("home_widget's 1.+ resolves to alpha requiring SDK 37")
        }
    }
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
