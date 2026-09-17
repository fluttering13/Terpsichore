package com.example.terpsichore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DebugLauncherReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.example.terpsichore.ENABLE_DEBUG_LAUNCHER") {
            EmotionBackmailManager.enableDebugLauncher(context.applicationContext)
        }
    }
}
