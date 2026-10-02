import groovy.json.JsonSlurper
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Keys live in sos_system/secrets.json (git-ignored). See SETUP.md.
val secretsFile = rootProject.file("../secrets.json")
@Suppress("UNCHECKED_CAST")
val secrets: Map<String, Any> =
    if (secretsFile.exists()) JsonSlurper().parse(secretsFile) as Map<String, Any> else emptyMap()
val mapsApiKey: String = (secrets["MAPS_API_KEY"] as String?) ?: ""
if (mapsApiKey.isEmpty()) {
    logger.warn("MAPS_API_KEY missing: create sos_system/secrets.json (see SETUP.md). Maps will not load.")
}

android {
    namespace = "com.kislay.travelguard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }


    defaultConfig {
        applicationId = "com.kislay.travelguard"
        minSdk = 23        // Required for Firebase Auth and Play Services
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // Replace with real signing for production
                isMinifyEnabled = false
                isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase BoM ensures compatible versions of all Firebase libraries
    implementation(platform("com.google.firebase:firebase-bom:34.4.0"))

    // Firebase Analytics (you can add more products here)
    implementation("com.google.firebase:firebase-analytics")
}

flutter {
    source = "../.."
}
