import java.util.Properties

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.compose.compiler)
  alias(libs.plugins.kotlin.serialization)
}

val signingFile = file(
    providers.environmentVariable("OPENSTRUDEL_ANDROID_SIGNING_PROPERTIES").orNull
        ?: System.getProperty("user.home") + "/.openstrudel/android/signing.properties"
)
val releaseKeys = Properties().apply {
    if (signingFile.isFile) signingFile.inputStream().use { load(it) }
}

android {
    namespace = "app.openstrudel"
    compileSdk = 36
    defaultConfig {
        applicationId = "is.openstrudel.android"
        minSdk = 28
        targetSdk = 36
        versionCode = 2
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (signingFile.isFile) create("distribution") {
            storeFile = file(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
        }
    }
    buildTypes {
        debug { applicationIdSuffix = ".qa"; versionNameSuffix = "-qa" }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("distribution")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
      compose = true
      aidl = false
      buildConfig = true
      shaders = false
    }

    packaging {
      resources {
        excludes += "/META-INF/{AL2.0,LGPL2.1}"
      }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
  val composeBom = platform(libs.androidx.compose.bom)
  implementation(composeBom)
  androidTestImplementation(composeBom)

  // Core Android dependencies
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.activity.compose)

  // Arch Components
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)

  // Compose
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.compose.material3)
  implementation("androidx.compose.material:material-icons-extended:1.7.8")
  implementation("com.squareup.okhttp3:okhttp:4.12.0")
  implementation("io.coil-kt.coil3:coil-compose:3.4.0")
  implementation("io.noties.markwon:core:4.6.2")
  implementation("io.noties.markwon:ext-tables:4.6.2")
  implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
  // Tooling
  debugImplementation(libs.androidx.compose.ui.tooling)
  // Instrumented tests
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  debugImplementation(libs.androidx.compose.ui.test.manifest)

  // Local tests: jUnit, coroutines, Android runner
  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation("org.json:json:20250517")
  testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
  testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")

  // Instrumented tests: jUnit rules and runners
  androidTestImplementation(libs.androidx.test.core)
  androidTestImplementation(libs.androidx.test.ext.junit)
  androidTestImplementation(libs.androidx.test.runner)
  androidTestImplementation(libs.androidx.test.espresso.core)
  androidTestImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
  androidTestImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")

  // Navigation
  implementation(libs.androidx.navigation3.ui)
  implementation(libs.androidx.navigation3.runtime)
  implementation(libs.androidx.lifecycle.viewmodel.navigation3)
}
