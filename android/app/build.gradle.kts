import com.android.build.api.dsl.ApplicationExtension

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")

extensions.configure<ApplicationExtension> {
    namespace = "com.mawj.tomatolog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        releaseKeystorePath?.let { path ->
            create("release") {
                storeFile = file(path)
                storePassword = requireNotNull(System.getenv("ANDROID_STORE_PASSWORD"))
                keyAlias = requireNotNull(System.getenv("ANDROID_KEY_ALIAS"))
                keyPassword = requireNotNull(System.getenv("ANDROID_KEY_PASSWORD"))
            }
        }
    }

    defaultConfig {
        applicationId = "com.mawj.tomatolog"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (releaseKeystorePath == null) "debug" else "release",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
