-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.gms.**

-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Firebase — keep only what's needed for reflection
-keep class com.google.firebase.FirebaseException { *; }
-keep class com.google.firebase.auth.FirebaseAuth { *; }
-keep class com.google.firebase.auth.PhoneAuthCredential { *; }
-keep class com.google.firebase.messaging.FirebaseMessagingService { *; }

# Flutter plugins that use reflection
-keep class io.flutter.plugins.** { *; }
-keep class com.dexterous.** { *; }

# App widgets — required for RemoteViews
-keep class com.sokolangu.app.SokoVibeWidgetProvider { *; }
-keep class com.sokolangu.app.FlashSalesWidgetProvider { *; }
-keep class com.sokolangu.app.WidgetDataStore { *; }

# Mobile scanner — uses ZXing reflection
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }

# OneSignal
-keep class com.onesignal.** { *; }

# Repackage class names to obscure structure
-repackageclasses ''
-allowaccessmodification

# Strip logging
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
