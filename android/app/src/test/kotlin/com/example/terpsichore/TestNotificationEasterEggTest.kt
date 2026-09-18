package com.example.terpsichore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TestNotificationEasterEggTest {
    @Test fun englishSettingSelectsAllFiveEnglishLines() {
        assertEquals(listOf(
            "Ten times.",
            "You really tapped it ten times.",
            "Even Hercules wasn't this persistent through his twelve labors.",
            "All right. Your goddess knows the notifications work now.",
            "Now put your phone down and go dance.",
        ), TestNotificationEasterEgg.messagesFor("en"))
    }

    @Test fun chineseAndUnknownSettingsUseOriginalLines() {
        for (language in listOf("zh-TW", null, "unknown")) {
            assertEquals(TestNotificationEasterEgg.messages,
                TestNotificationEasterEgg.messagesFor(language))
        }
    }

    @Test fun triggersOnlyOnEveryTenthPress() {
        var count = 0
        val triggers = mutableListOf<Int>()
        for (press in 1..30) {
            count = TestNotificationEasterEgg.nextCount(count)
            if (count == 0) triggers.add(press)
        }
        assertEquals(listOf(10, 20, 30), triggers)
    }

    @Test fun resumesFromSavedCount() {
        assertEquals(9, TestNotificationEasterEgg.nextCount(8))
        assertEquals(0, TestNotificationEasterEgg.nextCount(9))
        assertEquals(1, TestNotificationEasterEgg.nextCount(0))
    }

    @Test fun fiveLinesUseTheRequestedOrderAndTwoSecondSpacing() {
        assertEquals(listOf(
            "十次。",
            "你真的按了十次。",
            "Hercules 完成十二試煉都沒你這麼執著。",
            "好了，本女神知道通知能正常運作了。",
            "現在，把手機放下，去跳舞。",
        ), TestNotificationEasterEgg.messages)
        val times = TestNotificationEasterEgg.messages.indices.map {
            it * TestNotificationEasterEgg.INTERVAL_MILLIS
        }
        assertEquals(listOf(0L, 2000L, 4000L, 6000L, 8000L), times)
        assertTrue(times.zipWithNext().all { (a, b) -> b - a == 2000L })
    }
}
