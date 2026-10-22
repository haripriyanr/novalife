# R8 / ProGuard rules for the NovaLife app.
#
# The Flutter Gradle Plugin (dev.flutter.flutter-gradle-plugin) already enables
# minification for the release build type and wires
# `proguard-android-optimize.txt` + `flutter_proguard_rules.pro` +
# this file (FlutterPlugin.kt:224-226) into it, so nothing here needs a
# buildTypes { release { proguardFiles(...) } } entry in build.gradle.kts.
#
# Do not disable minification: shrink the release build and fix the rules.

# ---------------------------------------------------------------------------
# Google ML Kit text recognition (google_mlkit_text_recognition).
#
# ML Kit's classes are looked up and built reflectively (factories, recognizer
# options builders, model keys), and the OCR banner models are loaded from
# resources by name, so R8 must not rename or drop them.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text** { *; }
-keep class com.google.android.apps.common.proguard.** { *; }

# The plugin's own consumer rules keep native method names; repeat it here so
# the release build cannot break with an UnsatisfiedLinkError.
-keepclasseswithmembernames class * {
    native <methods>;
}

# The Latin-only recognizer references the Chinese / Devanagari / Japanese /
# Korean option classes that live in optional artifacts we do not depend on.
# They are legitimately absent at runtime: silence the missing-class warnings
# instead of failing R8 (see build/app/outputs/mapping/release/missing_rules.txt).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.**
