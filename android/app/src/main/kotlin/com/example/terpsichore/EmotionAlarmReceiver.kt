package com.example.terpsichore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class EmotionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EmotionBackmailManager.onInactivityAlarm(context)
    }
}
