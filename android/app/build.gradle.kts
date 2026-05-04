// android/app 폴더 내부의 build.gradle.kts (Kotlin DSL 버전)

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.taesoo_voca"
    compileSdk = 34 // 최신 SDK 사용

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.taesoo_voca"
        // 음성 인식 패키지(speech_to_text)를 위해 반드시 21 이상이어야 함
        minSdk = 21 
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // 배포용 빌드 설정
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.10")
}