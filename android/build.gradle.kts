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
// بعض الإضافات (flutter_ringtone_player) مبنية على compileSdk 33 بينما مكتبات androidx تحتاج 34+.
subprojects {
    if (project.name != "app") {
        project.plugins.withId("com.android.library") {
            project.extensions.getByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>()
                .finalizeDsl { ext -> if ((ext.compileSdk ?: 0) < 36) ext.compileSdk = 36 }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
