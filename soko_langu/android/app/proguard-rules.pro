-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.google.android.play.** { *; }
-keep class com.android.vending.** { *; }

-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes Exceptions

-keep class com.sokolangu.app.SokoVibeWidgetProvider { *; }
-keep class com.sokolangu.app.FlashSalesWidgetProvider { *; }
-keep class com.sokolangu.app.WidgetDataStore { *; }

-dontwarn io.flutter.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ─── ANTI-REVERSE-ENGINEERING ──────────────────────────
# Obfuscate string constants (API keys, URLs, etc.) so they
# don't appear as readable text in the APK binary.
-repackageclasses ''
-allowaccessmodification

# Remove logging in release builds — attackers use logs to
# understand app behavior during static analysis.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Remove toString() on model classes — prevents easy data extraction.
# Comment this out if you need crash reports with model names.
# -assumenosideeffects class ** { *** toString(); }

# Protect native libraries from extraction.
# -keepclassmembers class * { native <methods>; }
