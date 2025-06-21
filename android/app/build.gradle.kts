import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")   // FlutterFire
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.needgo.mvpapp"
    compileSdk = 35

    // 解決 NDK 版本衝突
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.needgo.mvpapp"
        // Firebase Auth 23.x+ 要求 minSdk >= 23
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // 1. 讀取 key.properties
    val keystorePropsFile = rootProject.file("key.properties")
    val keystoreProperties = Properties().apply {
        if (keystorePropsFile.exists()) {
            load(FileInputStream(keystorePropsFile))
        } else {
            // It's good that you have this check, it will catch the missing file
            throw GradleException("Missing key.properties for signingConfig")
        }
    }

    // 2. 設定 signingConfigs
    signingConfigs {
        create("release") {
            // Use the exact keys from your key.properties file
            keyAlias    = keystoreProperties["keyAlias"]    as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile   = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    // 3. 設定 buildTypes 並套用 release signingConfig
    buildTypes {
       getByName("release") {
          signingConfig   = signingConfigs.getByName("release")
          isMinifyEnabled = true       // 關閉程式碼混淆
          isShrinkResources = true     // 關閉資源精簡
          // 若日後想要混淆再加上 proguard 檔即可
       }
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-auth:20.5.0")
    // 其他 dependencies…
}