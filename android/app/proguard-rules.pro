# Keep custom Android entrypoints and JobService
-keep class com.homespace.homespace.MainActivity { *; }
-keep class com.homespace.homespace.AutoBackupJobService { *; }
-keep class com.homespace.homespace.AutoBackupBootReceiver { *; }

# Keep Flutter embedding & plugins safe under R8
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn java.lang.invoke.*
