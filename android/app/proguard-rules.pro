# Google Mobile Ads / WorkManager / Room release crash fix
-keep class androidx.work.impl.** { *; }
-dontwarn androidx.work.impl.**

-keepclassmembers class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(...); }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.model.** { *; }
