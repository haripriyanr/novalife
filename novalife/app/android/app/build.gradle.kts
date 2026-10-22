plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.syndrix.novalife"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    }

    defaultConfig {
        applicationId = "tech.syndrix.novalife"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            // Signing with debug keys for demo release APK
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // ✅ FIXED: Correct Kotlin DSL syntax for sourceSets
    sourceSets {
        getByName("main") {
            jniLibs.srcDir("src/main/jniLibs")
        }
    }

    // ✅ FIXED: Use 'packaging' instead of 'packagingOptions' + 16KB page size support
    packaging {
        resources {
            excludes += setOf("META-INF/*.kotlin_module")
        }
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so", "**/libc++_static.a", "**/libffi.so")
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}
