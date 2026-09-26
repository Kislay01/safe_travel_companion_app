// Top-level build file for common configuration

plugins {
    // Android Gradle Plugin (AGP) — matches Flutter Gradle plugin requirements
    id("com.android.application") version "8.7.0" apply false

    // Kotlin plugin compatible with AGP 8.7
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false

    // Google Services plugin for Firebase
    id("com.google.gms.google-services") version "4.4.4" apply false

    // Flutter Gradle plugin is provided by the Flutter tool; do not declare it here to avoid classpath conflicts.
}

// Repositories
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter-style build directories
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
