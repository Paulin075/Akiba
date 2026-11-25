import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de release optionnelle : créez android/key.properties
// (storeFile, storePassword, keyAlias, keyPassword) pour signer avec votre
// propre clé. Sans ce fichier, la build release reste signée en debug afin de
// rester utilisable pour les essais.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.akiba"
    // permission_handler_android 14.1.1 is built against Android API 37.
    // SDK 37 is installed locally; targetSdk remains controlled by Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Exigé par flutter_local_notifications (API de date/heure Java 8+).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.akiba.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Repli explicite : la build release fonctionne, mais doit être
                // signée avec une vraie clé avant toute publication.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Seule copie automatique des identifiants Google OAuth : Android n'a pas de
// dossier `secrets/`, la copie embarquée doit donc être à jour avant que
// Flutter n'assemble les assets. Le script supprime la copie quand la source
// est absente et se tait quand elle est déjà à jour ; un échec (Dart absent du
// PATH, JSON illisible) ne doit jamais bloquer la build : l'application reste
// alors utilisable avec le dossier Drive synchronisé.
val syncOAuthSecrets = tasks.register<Exec>("syncOAuthSecrets") {
    workingDir = rootProject.projectDir.parentFile
    val command = "dart run tool/sync_oauth_secrets.dart"
    if (System.getProperty("os.name").lowercase().contains("win")) {
        commandLine("cmd", "/c", "$command & exit 0")
    } else {
        commandLine("sh", "-c", "$command || true")
    }
    isIgnoreExitValue = true
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(syncOAuthSecrets)
}

flutter {
    source = "../.."
}
