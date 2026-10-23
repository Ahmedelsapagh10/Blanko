import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release credentials stay in ignored local properties or the CI secret store.
val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}
fun releaseCredential(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStore = releaseCredential("BLANKO_ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = releaseCredential("BLANKO_ANDROID_STORE_PASSWORD", "storePassword")
val releaseAlias = releaseCredential("BLANKO_ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = releaseCredential("BLANKO_ANDROID_KEY_PASSWORD", "keyPassword")
val releaseValues = listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword)
val hasReleaseSigning = releaseValues.all { it != null }
require(releaseValues.all { it == null } || hasReleaseSigning) {
    "Android release signing requires all four keystore settings. No partial signing configuration is allowed."
}

android {
    namespace = "ahmedelsapagh.com.whiteboard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ahmedelsapagh.com.whiteboard"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Debug signing is reserved for the explicitly documented beta preview.
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
