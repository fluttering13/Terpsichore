package com.example.terpsichore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class EmotionBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            EmotionBackmailManager.onPackageReplaced(context.applicationContext)
        }
        EmotionBackmailManager.restoreSchedule(context)
    }
}
