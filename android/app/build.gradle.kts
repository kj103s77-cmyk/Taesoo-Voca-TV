// android/app 폴더 내부의 build.gradle.kts (Kotlin DSL 버전)
// 음성 인식 패키지 호환성 및 빌드 에러 해결 설정이 포함되어 있습니다.

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.taesoo_voca"
    compileSdk = 34 // 최신 안드로이드 SDK 버전 사용

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.taesoo_voca"
        // 음성 인식 패키지(speech_to_text) 사용을 위해 반드시 21 이상으로 설정해야 합니다.
        minSdk = 21 
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // 에러 해결: 리소스 제거 시 코드 압축 충돌 문제를 방지하기 위해 모두 false로 설정합니다.
            isMinifyEnabled = false
            isShrinkResources = false 
            
            // 깃허브 액션 빌드를 위해 기본 디버그 서명을 사용합니다.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Kotlin 라이브러리와의 호환성을 높이기 위해 추가합니다.
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.10")
}