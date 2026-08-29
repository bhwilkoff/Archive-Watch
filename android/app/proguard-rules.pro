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

# Room instantiates its generated `<DatabaseClass>_Impl` REFLECTIVELY through
# the no-arg constructor, and R8 removed exactly that constructor from
# androidx.work.impl.WorkDatabase_Impl — verified in
# build/outputs/mapping/googleRelease/usage.txt, which lists
# "public void <init>()" among the members it deleted.
#
# WorkManager is here transitively via androidx.glance:glance-appwidget (the
# home-screen widgets), so its database is constructed during
# androidx.startup.InitializationProvider — BEFORE any of our code runs. The
# app therefore died on launch, every launch, and Google Play rejected the
# release for "crashes after opening" (2026-08-29).
#
# Only the RELEASE build minifies, which is why every debug install on every
# device looked perfect. A release build must be run on a device before it is
# submitted; that is the lesson this rule is a monument to.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.room.RoomDatabase$Callback { *; }
-dontwarn androidx.room.paging.**
