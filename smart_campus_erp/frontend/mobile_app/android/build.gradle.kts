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

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            var originalPackage: String? = null
            try {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText(Charsets.UTF_8)
                    val match = Regex("""package="([^"]*)"""").find(content)
                    if (match != null) {
                        originalPackage = match.groupValues[1]
                    }
                    if (content.contains("package=")) {
                        println("AGP Fix: Removing package attribute from ${manifestFile.absolutePath}")
                        val cleanedContent = content.replace(Regex("""package="[^"]*""""), "")
                        manifestFile.writeText(cleanedContent, Charsets.UTF_8)
                    }
                }
            } catch (e: Exception) {
                println("AGP Fix Warning: Failed to clean package attribute for ${project.name}: ${e.message}")
            }

            if (namespace == null) {
                namespace = if (originalPackage != null) {
                    originalPackage
                } else if (project.name == "flutter_unity_widget") {
                    "com.xraph.plugin.flutter_unity_widget"
                } else {
                    "com.example.${project.name.replace("-", ".")}"
                }
            }
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension> {
            if (namespace == null) {
                namespace = "com.example.${project.name.replace("-", ".")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
