# Firebase / Google Play Services — gRPC + protobuf reflection üzerinden
# çalışır, R8 varsayılan optimizasyonu bu sınıfları kırabilir.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# flutter_local_notifications — Gson tabanlı seri hale getirme kullanıyor
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
