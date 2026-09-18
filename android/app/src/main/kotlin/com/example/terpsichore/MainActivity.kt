package com.example.terpsichore

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "terpsichore/emotion_backmail"
        private const val NOTIFICATION_PERMISSION_REQUEST = 7318
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        EmotionBackmailManager.onHostActivityCreated()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AccuratePosePlugin::class.java)) {
            flutterEngine.plugins.add(AccuratePosePlugin())
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordOpen" -> {
                        val status = EmotionBackmailManager.onAppOpened(this)
                        EmotionBackmailManager.postPendingNotification(this)
                        result.success(status)
                    }
                    "getNotificationSettings" -> {
                        result.success(EmotionBackmailManager.notificationSettings(this))
                    }
                    "openNotificationSettings" -> {
                        val status = EmotionBackmailManager.notificationSettings(this)
                        val intent = if (Build.VERSION.SDK_INT >= 26) {
                            Intent(if (status["notificationsAllowed"] == true && status["channelAllowed"] == false)
                                Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS else Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, "emotion_backmail")
                        } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        if (openSettingsSafely(intent)) result.success(null)
                        else result.error("SETTINGS_UNAVAILABLE", "Cannot open system settings", null)
                    }
                    "testNotification" -> {
                        requestNotificationPermissionIfNeeded()
                        result.success(EmotionBackmailManager.onTestNotificationPressed(this))
                    }
                    "updateNotificationSettings" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val hour = call.argument<Int>("hour") ?: 18
                        val minute = call.argument<Int>("minute") ?: 0
                        val language = call.argument<String>("language") ?: "zh-TW"
                        result.success(
                            EmotionBackmailManager.updateNotificationSettings(
                                this,
                                enabled,
                                hour,
                                minute,
                                language,
                            ),
                        )
                    }
                    "requestExactAlarmPermission" -> {
                        if (requestExactAlarmPermissionIfNeeded()) result.success(null)
                        else result.error("SETTINGS_UNAVAILABLE", "Cannot open system settings", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Drain our native runs before other plugins may tear down shared ORT.
        flutterEngine.plugins.remove(AccuratePosePlugin::class.java)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            EmotionBackmailManager.postPendingNotification(this)
        }
    }

    override fun onDestroy() {
        val canApplyPendingIcon = isFinishing && !isChangingConfigurations
        super.onDestroy()
        EmotionBackmailManager.onHostActivityDestroyed(
            applicationContext,
            canApplyPendingIcon,
        )
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        EmotionBackmailManager.restoreSchedule(this)
        EmotionBackmailManager.postPendingNotification(this)
    }

    private fun openSettingsSafely(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: RuntimeException) {
            try {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                true
            } catch (_: RuntimeException) { false }
        }
    }

    private fun requestExactAlarmPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = getSystemService(AlarmManager::class.java)
        if (alarmManager.canScheduleExactAlarms()) return true
        return openSettingsSafely(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

}
