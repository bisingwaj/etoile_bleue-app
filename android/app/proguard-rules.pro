# ProGuard / R8 rules for Étoile Bleue
# Required to keep native interop working with minification enabled.

# --- Flutter engine ---
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# --- Agora RTC Engine ---
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# --- Supabase / Realtime (uses Retrofit-style reflection) ---
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# --- Firebase ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- OkHttp (transitive from Supabase / Agora) ---
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# --- Google Maps ---
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**

# --- CallKit ---
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-dontwarn com.hiennv.flutter_callkit_incoming.**

# --- Keep Parcelable / Serializable used by plugins ---
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
