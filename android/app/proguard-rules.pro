# R8 is always on for release. Most modern libs ship their own
# consumer rules — Kotlin Serialization, Room, Hilt, Coil, Compose,
# OkHttp/Ktor are all covered. Add per-app keeps below as you find
# accidental strippage in `app/build/outputs/mapping/release/usage.txt`.

# kotlinx.serialization — usually auto-handled, but data classes with
# @Serializable that are referenced reflectively need an explicit keep.
# Pattern:
# -keep,includedescriptorclasses class com.example.appname.**$$serializer { *; }
# -keepclassmembers class com.example.appname.** { *** Companion; }
# -keepclasseswithmembers class com.example.appname.** { kotlinx.serialization.KSerializer serializer(...); }

# OkHttp / Conscrypt — these warnings are noise; safe to suppress.
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Crash on R8 errors (don't silently strip) — easier debugging.
-printusage build/outputs/mapping/release/usage.txt
-printseeds build/outputs/mapping/release/seeds.txt
