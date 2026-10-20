allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Compatibility workaround for legacy Android plugins from pub cache that
// still define only manifest package but no AGP namespace.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val getNamespace = androidExt.javaClass.methods.firstOrNull {
                it.name == "getNamespace" && it.parameterCount == 0
            } ?: return@afterEvaluate
            val setNamespace = androidExt.javaClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterCount == 1
            } ?: return@afterEvaluate

            val currentNamespace = getNamespace.invoke(androidExt) as? String
            if (!currentNamespace.isNullOrBlank()) return@afterEvaluate

            val manifestFile = file("src/main/AndroidManifest.xml")
            if (!manifestFile.exists()) return@afterEvaluate

            val packageName =
                Regex("package=\"([^\"]+)\"")
                    .find(manifestFile.readText())
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.trim()

            if (!packageName.isNullOrBlank()) {
                setNamespace.invoke(androidExt, packageName)
            }
        } catch (_: Throwable) {
            // Ignore and let the regular AGP error surface if this workaround
            // cannot infer a namespace for a specific plugin.
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
