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

// Some plugins in the pub cache (e.g. objectbox_flutter_libs, pulled in by
// flutter_map_tile_caching) pin an old compileSdk in their own
// android/build.gradle and fail AAR-metadata checks against modern
// androidx dependencies. Force every library subproject to compile
// against the same SDK as the app module instead of patching pub-cache
// files, which pub get would just overwrite again.
subprojects {
    // :app already sets its own compileSdk directly, and by the time this
    // block reaches it, evaluationDependsOn(":app") above has usually
    // already forced it to finish evaluating - calling afterEvaluate on an
    // already-evaluated project throws, so it is skipped here.
    if (name == "app") return@subprojects
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
            android.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
