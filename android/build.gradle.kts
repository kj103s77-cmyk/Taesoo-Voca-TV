// 프로젝트 루트의 build.gradle.kts (Kotlin DSL 버전)
// speech_to_text 패키지와의 호환성 문제를 해결하기 위해 설정을 고정합니다.

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Kotlin 버전을 1.9.10으로 설정하여 'Registrar' 관련 컴파일 에러를 방지합니다.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.10")
        // Android Gradle Plugin 버전을 최신 안정 버전으로 설정합니다.
        classpath("com.android.tools.build:gradle:8.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 빌드 출력 디렉토리 설정
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

// 빌드 정리(Clean) 태스크 등록
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}