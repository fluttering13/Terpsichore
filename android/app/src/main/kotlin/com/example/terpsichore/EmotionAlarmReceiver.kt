package com.example.terpsichore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class EmotionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getBooleanExtra("test_notification", false)) {
            EmotionBackmailManager.deliverTestNotification(context)
        } else EmotionBackmailManager.onInactivityAlarm(context)
    }
}
