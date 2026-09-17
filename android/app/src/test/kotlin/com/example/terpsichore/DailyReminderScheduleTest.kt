package com.example.terpsichore

import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class DailyReminderScheduleTest {
    private fun check(now: String, expected: String) {
        val value = ZonedDateTime.parse(now)
        assertEquals(ZonedDateTime.parse(expected).toInstant().toEpochMilli(),
            DailyReminderSchedule.next(value.toInstant().toEpochMilli(), 18, 0, value.zone))
    }
    @Test fun openingBeforeSixKeepsToday() = check(
        "2026-09-17T17:59:00+08:00[Asia/Taipei]", "2026-09-17T18:00:00+08:00[Asia/Taipei]")
    @Test fun afterSixSchedulesTomorrow() = check(
        "2026-09-17T18:01:00+08:00[Asia/Taipei]", "2026-09-18T18:00:00+08:00[Asia/Taipei]")
    @Test fun exactTriggerDoesNotRescheduleItself() = check(
        "2026-09-17T18:00:00+08:00[Asia/Taipei]", "2026-09-18T18:00:00+08:00[Asia/Taipei]")
    @Test fun dstUsesLocalClockNotTwentyFourHours() = check(
        "2026-03-07T19:00:00-05:00[America/New_York]", "2026-03-08T18:00:00-04:00[America/New_York]")
}
