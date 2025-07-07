import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")   // FlutterFire
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 讀取 local.properties 文件中的 API Key
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

// 從 local.properties 或環境變數中讀取 API Key
val googleMapsApiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY") 
    ?: System.getenv("GOOGLE_MAPS_API_KEY") 
    ?: throw GradleException("Google Maps API Key not found! Please add GOOGLE_MAPS_API_KEY to local.properties or environment variables")

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
        versionCode = 2
        versionName = "1.0"
        
        // 將 API Key 作為 BuildConfig 傳入
        buildConfigField("String", "GOOGLE_MAPS_API_KEY", "\"$googleMapsApiKey\"")
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // 設定 signingConfigs - 包含 debug 和 release
    signingConfigs {
        // Debug 簽名配置（使用 Android 默認的 debug keystore）
        getByName("debug") {
            storeFile = file("${System.getProperty("user.home")}/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        
        // Release 簽名配置
        create("release") {
            val keystorePropsFile = rootProject.file("key.properties")
            if (keystorePropsFile.exists()) {
                val keystoreProperties = Properties().apply {
                    load(FileInputStream(keystorePropsFile))
                }
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // 設定 buildTypes
    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
            // 移除 applicationIdSuffix = ".debug" 以避免 Firebase 配置問題
        }
        
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
        }
    }
    
    // 啟用 BuildConfig 生成
    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-auth:20.5.0")
    implementation("com.google.android.gms:play-services-maps:18.2.0")
    implementation("com.google.android.gms:play-services-location:21.0.1")
    // 其他 dependencies…
}