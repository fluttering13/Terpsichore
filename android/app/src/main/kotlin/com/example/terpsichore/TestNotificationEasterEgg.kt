package com.example.terpsichore

internal object TestNotificationEasterEgg {
    const val TAP_THRESHOLD = 10
    const val INTERVAL_MILLIS = 2_000L
    val messages = listOf(
        "十次。",
        "你真的按了十次。",
        "Hercules 完成十二試煉都沒你這麼執著。",
        "好了，本女神知道通知能正常運作了。",
        "現在，把手機放下，去跳舞。",
    )

    private val englishMessages = listOf(
        "Ten times.",
        "You really tapped it ten times.",
        "Even Hercules wasn't this persistent through his twelve labors.",
        "All right. Your goddess knows the notifications work now.",
        "Now put your phone down and go dance.",
    )

    fun messagesFor(language: String?): List<String> =
        if (language == "en") englishMessages else messages

    fun nextCount(previous: Int): Int = (previous.coerceIn(0, TAP_THRESHOLD - 1) + 1) % TAP_THRESHOLD
}
