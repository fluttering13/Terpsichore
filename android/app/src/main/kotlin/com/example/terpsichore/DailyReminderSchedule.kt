package com.example.terpsichore

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/** Opening the app never moves a future reminder from today to tomorrow. */
internal object DailyReminderSchedule {
    fun next(nowMillis: Long, hour: Int, minute: Int, zone: ZoneId): Long {
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val today = now.toLocalDate().atTime(LocalTime.of(hour, minute)).atZone(zone)
        return (if (today.toInstant().toEpochMilli() > nowMillis) today
            else now.toLocalDate().plusDays(1).atTime(LocalTime.of(hour, minute)).atZone(zone))
            .toInstant().toEpochMilli()
    }
}
