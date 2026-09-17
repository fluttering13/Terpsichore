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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordOpen" -> {
                        requestNotificationPermissionIfNeeded()
                        val status = EmotionBackmailManager.onAppOpened(this)
                        EmotionBackmailManager.postPendingNotification(this)
                        result.success(status)
                    }
                    "getNotificationSettings" -> {
                        result.success(EmotionBackmailManager.notificationSettings(this))
                    }
                    "updateNotificationSettings" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val hour = call.argument<Int>("hour") ?: 18
                        val minute = call.argument<Int>("minute") ?: 0
                        val language = call.argument<String>("language") ?: "zh-TW"
                        requestNotificationPermissionIfNeeded()
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
                        requestExactAlarmPermissionIfNeeded()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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

    private fun requestExactAlarmPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val alarmManager = getSystemService(AlarmManager::class.java)
        if (alarmManager.canScheduleExactAlarms()) return
        startActivity(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

}
