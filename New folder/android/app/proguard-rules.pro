-keep class com.example.soko_langu.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.agora.** { *; }
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

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.internal.ads.** { *; }
-keep class com.google.android.libraries.ads.** { *; }
-keep public class com.google.android.ads.** { *; }

# Zego Cloud
-keep class im.zego.** { *; }
-keep class com.zego.** { *; }
-keep class org.webrtc.** { *; }

# Flutter CallKit Incoming
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class androidx.core.app.NotificationCompat { *; }

# Cloudinary
-keep class com.cloudinary.** { *; }
-keep class com.cloudinary.android.** { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Image Picker
-keep class com.fluttercandies.image_picker.** { *; }

# Audio Service
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.session.** { *; }

# Shared Preferences
-keep class androidx.preference.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# OkHttp / Retrofit
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class retrofit2.** { *; }

-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes Exceptions

-dontwarn io.flutter.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn org.webrtc.**
-dontwarn im.zego.**
