

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ↓ 在這裡新增：讓所有 com.android.library 模組都帶上 namespace
subprojects {
    plugins.withId("com.android.library") {
        // 導入 Android Library 擴充
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            // 指定一個不會衝突的唯一 namespace
            namespace = "com.needgo.image_cropper"
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
