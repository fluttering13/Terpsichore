-keep class ai.onnxruntime.** { *; }

# Room 2.2.5 creates generated databases by reflection. Its bundled rule keeps
# the class but not its constructor in R8 full mode, crashing WorkManager's
# startup provider before Flutter launches. Keep the no-argument constructor.
-keep class * extends androidx.room.RoomDatabase {
    public <init>();
}
