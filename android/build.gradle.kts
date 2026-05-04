// 프로젝트 루트의 build.gradle.kts (Kotlin DSL 버전)

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // 코틀린 및 그레이들 플러그인 버전을 최신으로 고정하여 SpeechToText 에러 방지
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.10")
        classpath("com.android.tools.build:gradle:8.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}