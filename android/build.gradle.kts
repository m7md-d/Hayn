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

// flutter_avif_android 3.1.0 ships BOTH a Java and a Kotlin `FlutterAvifPlugin`
// (same class), which modern Kotlin/AGP compile together → a "Redeclaration"
// failure that blocks every Android build. The Kotlin file is canonical; drop
// the stale Java twin. Idempotent + portable: self-heals on any machine and
// survives `flutter pub get` / `pub cache repair`, so the build works on Linux
// too with no manual step. (Remove once the plugin ships a fixed release.)
subprojects {
    if (project.name == "flutter_avif_android") {
        val staleJava = file(
            "${project.projectDir}/src/main/java/com/teknorota/flutter_avif/FlutterAvifPlugin.java",
        )
        if (staleJava.exists()) {
            staleJava.delete()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
