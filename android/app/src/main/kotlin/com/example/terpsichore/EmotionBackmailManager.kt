package com.example.terpsichore

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import androidx.annotation.DrawableRes
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.max
import kotlin.random.Random

object EmotionBackmailManager {
    @Volatile
    private var hostActivityActive = false

    private const val PREFS = "emotion_backmail"
    private const val KEY_LAST_OPEN_MILLIS = "last_open_millis"
    private const val KEY_LAST_OPEN_DAY = "last_open_day"
    private const val KEY_ONLINE_STREAK = "online_streak"
    private const val KEY_OFFLINE_DAYS = "offline_days"
    private const val KEY_CURRENT_ALIAS = "current_alias"
    private const val KEY_PENDING_ALIAS = "pending_alias"
    private const val KEY_CURRENT_MESSAGE = "current_message"
    private const val KEY_PENDING_TITLE = "pending_title"
    private const val KEY_PENDING_BODY = "pending_body"
    private const val KEY_PENDING_ICON = "pending_icon"
    private const val KEY_NOTIFICATIONS_ENABLED = "notifications_enabled"
    private const val KEY_REMINDER_HOUR = "reminder_hour"
    private const val KEY_REMINDER_MINUTE = "reminder_minute"
    private const val KEY_LANGUAGE = "language"
    private const val KEY_LAST_REMINDER_DAY = "last_reminder_day"

    private const val CHANNEL_ID = "emotion_backmail"
    private const val NOTIFICATION_ID = 7319
    private const val ALARM_REQUEST_CODE = 7320
    private const val DAY_MILLIS = 24L * 60L * 60L * 1000L
    private const val DEFAULT_REMINDER_HOUR = 18
    private const val DEFAULT_REMINDER_MINUTE = 0

    private const val FALLBACK_LAUNCHER_ALIAS = "FlutterLauncherIcon"
    private const val META_LAUNCHER_ALIAS =
        "com.example.terpsichore.EMOTION_LAUNCHER_ALIAS"

    private data class EmotionMessage(
        val icon: String,
        val title: String,
        val body: String,
    )

    private val offlineMessages = listOf(
        EmotionMessage("QuestionIcon", "Terpsichore 在等你", "Hermes 都比你勤快。你今天不打算動一下嗎？"),
        EmotionMessage("WaitingIcon", "Terpsichore 在等你", "兩日未曾起舞……你的舞步是被 Hades 帶走了嗎？"),
        EmotionMessage("AngryLeftIcon", "Terpsichore 在等你", "Ares 不會因為手臂酸痛就停止戰鬥。你卻因為痠痛三天不跳？"),
        EmotionMessage("AngryRightIcon", "Terpsichore 在等你", "Athena 若看見你的練習紀錄，大概會重新思考『智慧』的定義。"),
        EmotionMessage("AngryFrontIcon", "Terpsichore 在等你", "Moirai 還在替你編織命運，你卻已經想替自己剪斷絲線？"),
        EmotionMessage("AngryFront2Icon", "Terpsichore 在等你", "如果偷懶也算舞蹈，你現在大概已經成為 Olympus 最偉大的舞者。"),
        EmotionMessage("SadIcon", "Terpsichore 在等你", "Olympus 的樂聲已經沉寂許久……我還在神殿中等你。難道，你真的要讓 Terpsichore 的舞者就此沉睡？"),
        EmotionMessage("Sad2Icon", "Terpsichore 在等你", "連 Hades 的亡魂都會回應命運的召喚，而你卻連 Terpsichore 的召喚都不願回應？"),
        EmotionMessage("Sad3Icon", "Terpsichore 在等你", "神殿的火炬依然燃燒，音樂也從未停止。只是那個我期待的舞者，已經許久沒有出現了。"),
    )

    private val onlineMessages = listOf(
        EmotionMessage("DelightfulIcon", "今日的舞步", "不錯。看來你的雙腿終於開始理解本女神的教導了。"),
        EmotionMessage("HappyIcon", "今日的舞步", "今日表現尚可。距離讓本女神驕傲……還差得遠呢。"),
        EmotionMessage("BeginIcon", "今日的舞步", "進步了。別高興得太早，Olympus 的門檻可沒那麼低。"),
        EmotionMessage("Side1Icon", "今日的舞步", "若命運真的為你留下了一支舞，那麼至少，請把它跳完。"),
        EmotionMessage("Side2Icon", "今日的舞步", "繼續起舞吧。Olympus 的星辰會見證你的每一步，而我會記得你曾經付出的每一滴汗水。"),
        EmotionMessage("Jump1Icon", "今日的舞步", "我不要求你今日便成為傳說。神話也是由無數個平凡的日子寫成的。"),
        EmotionMessage("Lay1Icon", "今日的舞步", "我可以替你守護舞台，替你保存音樂。但唯有你自己，能讓這座神殿再次響起腳步聲。"),
        EmotionMessage("Lay2Icon", "今日的舞步", "Nike 不會把桂冠交給最有天賦的人，而會留給那些一次又一次選擇繼續的人。"),
    )

    private val offlineMessagesEn = listOf(
        EmotionMessage("QuestionIcon", "Terpsichore is waiting", "Even Hermes is more diligent than you. Aren't you going to move today?"),
        EmotionMessage("WaitingIcon", "Terpsichore is waiting", "Two days without dancing... Did Hades steal your steps away?"),
        EmotionMessage("AngryLeftIcon", "Terpsichore is waiting", "Ares would not stop fighting over sore arms. Yet soreness has kept you from dancing for three days?"),
        EmotionMessage("AngryRightIcon", "Terpsichore is waiting", "If Athena saw your practice record, she might reconsider the meaning of wisdom."),
        EmotionMessage("AngryFrontIcon", "Terpsichore is waiting", "The Moirai are still weaving your fate, yet you already want to cut the thread yourself?"),
        EmotionMessage("AngryFront2Icon", "Terpsichore is waiting", "If idleness counted as dance, you would already be the greatest dancer on Olympus."),
        EmotionMessage("SadIcon", "Terpsichore is waiting", "The music of Olympus has been silent for so long. I am still waiting in the temple. Will you truly let Terpsichore's dancer fall asleep?"),
        EmotionMessage("Sad2Icon", "Terpsichore is waiting", "Even the souls in Hades answer fate's call, yet you will not answer Terpsichore?"),
        EmotionMessage("Sad3Icon", "Terpsichore is waiting", "The temple torches still burn and the music never stopped. Only the dancer I await has been absent for far too long."),
    )

    private val onlineMessagesEn = listOf(
        EmotionMessage("DelightfulIcon", "Today's dance", "Not bad. It seems your legs are finally beginning to understand this goddess's teaching."),
        EmotionMessage("HappyIcon", "Today's dance", "An acceptable performance today. You are still a long way from making this goddess proud."),
        EmotionMessage("BeginIcon", "Today's dance", "You have improved. Do not celebrate too soon; the threshold of Olympus is not so low."),
        EmotionMessage("Side1Icon", "Today's dance", "If fate has truly left a dance for you, then at least dance it to the end."),
        EmotionMessage("Side2Icon", "Today's dance", "Keep dancing. The stars of Olympus will witness every step, and I will remember every drop of sweat."),
        EmotionMessage("Jump1Icon", "Today's dance", "I do not ask you to become a legend today. Myths are written through countless ordinary days."),
        EmotionMessage("Lay1Icon", "Today's dance", "I can guard the stage and preserve the music, but only you can make footsteps echo through this temple again."),
        EmotionMessage("Lay2Icon", "Today's dance", "Nike does not give the laurel to the most gifted, but to those who choose to continue again and again."),
    )

    private val continuingBodies = listOf(
        "Olympus 的試煉從來不會因為英雄疲憊就消失。你既然選擇了這條路，就別指望本女神准你半途而廢。",
        "連 Moirai 都還沒有替你的故事寫下結局，你倒是急著替自己畫上句號？",
        "你已經讓 Terpsichore 親眼看見你的進步。現在若停下，本女神可不接受這種拙劣的結局。",
        "我看見你從笨拙走向熟練，從猶豫走向自信。別告訴我，故事就要停在這裡。",
        "Apollo 的樂聲不會因你已經進步便停止。既然你已經聽見下一個樂章，就繼續跳。",
        "你已經走過的路，Olympus 都替你記著。現在，再替自己多走一步。",
        "Hercules 完成十二試煉都沒喊停，別輕易向命運投降。",
        "Orpheus 敢走進 Hades 尋回 Eurydice。別差最後幾步，卻開始考慮回頭。",
        "Icarus 至少真的飛向了太陽。你連飛都還沒飛夠，別害怕墜落了。",
        "Achilles 尚且踏上戰場，即使知道自己的弱點，你已經知道自己的弱點了嗎？",
        "Olympus 的門已經為你敞開。你若停在門前，可別怪眾神沒有給你機會。",
        "我不需要你成為神。只要你別背叛那個曾經想成為更好的自己的凡人。",
        "你已經讓我期待你的下一支舞了。現在，可別讓本女神等到失去期待。",
    )

    private val welcomeBodies = listOf(
        "很好，你回來了。Olympus 的樂聲，果然沒有白等。",
        "我就知道你會回來。現在，讓我們看看你的舞步能走到哪裡。",
        "歡迎回來，我的舞者。今天的你，比昨天更接近自己想成為的樣子。",
        "很好。你又踏上舞台了。記住，真正的舞者從不害怕重新開始。",
        "看見你再次起舞，我很欣慰。繼續吧，別讓今天的努力只停留在今天。",
        "你回來了。很好。現在，把昨日未完成的舞步，跳完。",
        "你不是走不到終點，只是開始忘記自己為什麼出發。幸好，本女神還記得。",
        "本女神會一直看著你。但我希望有一天，當你的名字被寫進屬於你的神話時，我能說——幸好，那時候他沒有停下。",
    )

    private val continuingBodiesEn = listOf(
        "The trials of Olympus do not vanish when heroes grow tired. You chose this path; do not expect this goddess to let you quit halfway.",
        "Even the Moirai have not written the ending of your story, yet you are eager to draw the final line yourself?",
        "You have let Terpsichore witness your progress. If you stop now, this goddess will not accept such a clumsy ending.",
        "I watched you grow from awkward to skilled, from hesitant to confident. Do not tell me the story ends here.",
        "Apollo's music does not stop because you have improved. You have heard the next movement, so keep dancing.",
        "Olympus remembers the road you have traveled. Now take one more step for yourself.",
        "Hercules completed twelve labors without quitting. Do not surrender so easily to fate.",
        "Orpheus dared enter Hades to retrieve Eurydice. Do not turn back with only a few steps left.",
        "Icarus at least truly flew toward the sun. You have not flown enough yet, so do not fear the fall.",
        "Achilles entered battle even knowing his weakness. Have you learned yours yet?",
        "The gates of Olympus are open to you. If you stop at the threshold, do not blame the gods for giving you no chance.",
        "I do not need you to become a god. Just do not betray the mortal who once wanted to become better.",
        "You have made me look forward to your next dance. Do not keep this goddess waiting until that hope fades.",
    )

    private val welcomeBodiesEn = listOf(
        "Good. You are back. The music of Olympus did not wait in vain.",
        "I knew you would return. Now let us see how far your steps can take you.",
        "Welcome back, my dancer. Today, you are closer than yesterday to the person you wish to become.",
        "Good. You have stepped onto the stage again. Remember: a true dancer never fears beginning anew.",
        "I am pleased to see you dance again. Continue, and do not let today's effort end with today.",
        "You are back. Good. Now finish the steps you left incomplete yesterday.",
        "You can reach the end; you had only begun to forget why you started. Fortunately, this goddess remembers.",
        "This goddess will always watch over you. When your name is written into your own myth, I hope I can say: fortunately, they did not stop that day.",
    )

    private val emotionAliases = listOf(
        "QuestionIcon", "WaitingIcon", "AngryLeftIcon", "AngryRightIcon",
        "AngryFrontIcon", "AngryFront2Icon", "SadIcon", "Sad2Icon", "Sad3Icon",
        "DelightfulIcon", "HappyIcon", "BeginIcon", "Side1Icon", "Side2Icon",
        "Jump1Icon", "Lay1Icon", "Lay2Icon", "Front2Icon",
    )

    // Keep these aliases declared, but disabled, for one migration release.
    // Older debug builds generated these names and launcher databases can keep
    // them pinned until PackageManager reports their disabled state.
    private val legacyLauncherAliases = listOf(
        "FlutterDebugLauncher1789585372687",
        "FlutterDebugLauncher1789585493646",
        "FlutterDebugLauncher1789585628466",
        "FlutterDebugLauncher1789586160928",
        "FlutterDebugLauncher1789586289654",
        "FlutterDebugLauncher1789586600846",
    )

    fun onAppOpened(context: Context, now: Long = System.currentTimeMillis()): Map<String, Any> {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val today = java.time.Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault()).toLocalDate().toEpochDay()
        val lastOpenDay = prefs.getLong(KEY_LAST_OPEN_DAY, Long.MIN_VALUE)
        val lastOpenMillis = prefs.getLong(KEY_LAST_OPEN_MILLIS, 0L)
        val firstOpenToday = lastOpenDay != today
        val previousStreak = prefs.getInt(KEY_ONLINE_STREAK, 0)
        val onlineStreak = when {
            !firstOpenToday -> max(1, previousStreak)
            lastOpenDay == today - 1L -> max(1, previousStreak + 1)
            else -> 1
        }

        val storedOfflineDays = prefs.getInt(KEY_OFFLINE_DAYS, 0)
        val elapsedOfflineDays = if (lastOpenMillis > 0L) {
            ((now - lastOpenMillis).coerceAtLeast(0L) / DAY_MILLIS).toInt()
        } else {
            0
        }
        val offlineDaysBeforeReturn = max(storedOfflineDays, elapsedOfflineDays)

        val english = prefs.getString(KEY_LANGUAGE, "zh-TW") == "en"
        val onlineMessage = onlineMessageFor(onlineStreak, today, english)
        var currentMessage = prefs.getString(KEY_CURRENT_MESSAGE, null) ?: onlineMessage.body
        if (firstOpenToday) {
            if (offlineDaysBeforeReturn > 0) {
                val welcomeMessage = EmotionMessage(
                    onlineMessage.icon,
                    "歡迎回來，我的舞者",
                    (if (english) welcomeBodiesEn else welcomeBodies).random(),
                )
                currentMessage = welcomeMessage.body
                postOrQueue(appContext, welcomeMessage)
            } else {
                currentMessage = onlineMessage.body
                postOrQueue(appContext, onlineMessage)
            }
        }

        prefs.edit()
            .putLong(KEY_LAST_OPEN_MILLIS, now)
            .putLong(KEY_LAST_OPEN_DAY, today)
            .putInt(KEY_ONLINE_STREAK, onlineStreak)
            .putInt(KEY_OFFLINE_DAYS, 0)
            .putString(KEY_CURRENT_MESSAGE, currentMessage)
            .putString(
                KEY_PENDING_ALIAS,
                onlineMessage.icon,
            )
            .apply()

        if (notificationsEnabled(prefs)) {
            restoreSchedule(appContext)
        } else {
            cancelInactivityCheck(appContext)
        }
        return mapOf(
            "onlineStreak" to onlineStreak,
            "offlineDaysBeforeReturn" to offlineDaysBeforeReturn,
            "firstOpenToday" to firstOpenToday,
            "message" to currentMessage,
        )
    }

    fun onHostActivityCreated() {
        hostActivityActive = true
    }

    fun onHostActivityDestroyed(context: Context, canApplyPendingIcon: Boolean) {
        hostActivityActive = false
        if (canApplyPendingIcon) applyPendingLauncherIcon(context.applicationContext)
    }

    private fun applyPendingLauncherIcon(context: Context) {
        if (hostActivityActive) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val pendingAlias = prefs.getString(KEY_PENDING_ALIAS, null) ?: return
        normalizeLauncherAliases(context, pendingAlias)
        prefs.edit().remove(KEY_PENDING_ALIAS).apply()
    }

    fun enableDebugLauncher(context: Context) {
        normalizeLauncherAliases(context.applicationContext, launcherAlias(context))
    }

    fun onPackageReplaced(context: Context) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val defaultAlias = launcherAlias(appContext)
        val savedAlias = prefs.getString(KEY_CURRENT_ALIAS, defaultAlias)
        val desiredAlias = savedAlias?.takeIf { it == defaultAlias || it in emotionAliases } ?: defaultAlias
        normalizeLauncherAliases(appContext, desiredAlias)
    }

    fun onInactivityAlarm(context: Context) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!notificationsEnabled(prefs)) {
            cancelInactivityCheck(appContext)
            return
        }
        val lastOpenMillis = prefs.getLong(KEY_LAST_OPEN_MILLIS, 0L)
        val lastOpenDay = prefs.getLong(KEY_LAST_OPEN_DAY, Long.MIN_VALUE)
        if (lastOpenMillis == 0L || lastOpenDay == Long.MIN_VALUE) return

        val today = LocalDate.now().toEpochDay()
        val offlineDays = (today - lastOpenDay).toInt()
        if (prefs.getLong(KEY_LAST_REMINDER_DAY, Long.MIN_VALUE) == today ||
            System.currentTimeMillis() < reminderAt(prefs, today)) {
            restoreSchedule(appContext)
            return
        }

        val messages = if (prefs.getString(KEY_LANGUAGE, "zh-TW") == "en") {
            offlineMessagesEn
        } else {
            offlineMessages
        }
        val message = if (offlineDays < 1) {
            onlineMessageFor(prefs.getInt(KEY_ONLINE_STREAK, 1).coerceAtLeast(1), today,
                prefs.getString(KEY_LANGUAGE, "zh-TW") == "en")
        } else messages[(offlineDays - 1).coerceAtMost(messages.lastIndex)]
        prefs.edit().putInt(KEY_OFFLINE_DAYS, offlineDays.coerceAtLeast(0))
            .putLong(KEY_LAST_REMINDER_DAY, today).apply()
        if (hostActivityActive) {
            prefs.edit().putString(KEY_PENDING_ALIAS, message.icon).apply()
        } else {
            normalizeLauncherAliases(appContext, message.icon)
        }
        postOrQueue(appContext, message)
        restoreSchedule(appContext)
    }

    fun restoreSchedule(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!notificationsEnabled(prefs)) {
            cancelInactivityCheck(context)
            return
        }
        val lastOpenMillis = prefs.getLong(KEY_LAST_OPEN_MILLIS, 0L)
        val lastOpenDay = prefs.getLong(KEY_LAST_OPEN_DAY, Long.MIN_VALUE)
        if (lastOpenMillis == 0L || lastOpenDay == Long.MIN_VALUE) return
        val next = DailyReminderSchedule.next(System.currentTimeMillis(),
            prefs.getInt(KEY_REMINDER_HOUR, DEFAULT_REMINDER_HOUR),
            prefs.getInt(KEY_REMINDER_MINUTE, DEFAULT_REMINDER_MINUTE), ZoneId.systemDefault())
        scheduleNextInactivityCheck(context, next)
    }

    fun notificationSettings(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        return mapOf(
            "enabled" to notificationsEnabled(prefs),
            "notificationsAllowed" to (context.getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
                (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)),
            "channelAllowed" to (Build.VERSION.SDK_INT < 26 ||
                context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE),
            "hour" to prefs.getInt(KEY_REMINDER_HOUR, DEFAULT_REMINDER_HOUR),
            "minute" to prefs.getInt(KEY_REMINDER_MINUTE, DEFAULT_REMINDER_MINUTE),
            "language" to prefs.getString(KEY_LANGUAGE, "zh-TW").orEmpty(),
            "message" to prefs.getString(KEY_CURRENT_MESSAGE, "").orEmpty(),
            "exactAlarmAllowed" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarmManager.canScheduleExactAlarms()
                ),
        )
    }

    fun updateNotificationSettings(
        context: Context,
        enabled: Boolean,
        hour: Int,
        minute: Int,
        language: String,
    ): Map<String, Any> {
        require(hour in 0..23 && minute in 0..59) { "Invalid reminder time" }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val safeLanguage = if (language == "en") "en" else "zh-TW"
        val streak = prefs.getInt(KEY_ONLINE_STREAK, 1).coerceAtLeast(1)
        val localizedMessage = onlineMessageFor(
            streak,
            LocalDate.now().toEpochDay(),
            safeLanguage == "en",
        ).body
        prefs.edit()
            .putBoolean(KEY_NOTIFICATIONS_ENABLED, enabled)
            .putInt(KEY_REMINDER_HOUR, hour)
            .putInt(KEY_REMINDER_MINUTE, minute)
            .putString(KEY_LANGUAGE, safeLanguage)
            .putString(KEY_CURRENT_MESSAGE, localizedMessage)
            .apply()
        if (enabled) {
            restoreSchedule(context)
        } else {
            cancelInactivityCheck(context)
            context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
            prefs.edit()
                .remove(KEY_PENDING_TITLE)
                .remove(KEY_PENDING_BODY)
                .remove(KEY_PENDING_ICON)
                .apply()
        }
        return notificationSettings(context)
    }

    fun postPendingNotification(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!notificationsEnabled(prefs)) return
        val title = prefs.getString(KEY_PENDING_TITLE, null) ?: return
        val body = prefs.getString(KEY_PENDING_BODY, null) ?: return
        val icon = prefs.getString(KEY_PENDING_ICON, null) ?: "DelightfulIcon"
        if (postNotification(context, EmotionMessage(icon, title, body))) {
            prefs.edit()
                .remove(KEY_PENDING_TITLE)
                .remove(KEY_PENDING_BODY)
                .remove(KEY_PENDING_ICON)
                .apply()
        }
    }

    private fun onlineMessageFor(streak: Int, daySeed: Long, english: Boolean): EmotionMessage {
        val messages = if (english) onlineMessagesEn else onlineMessages
        if (streak <= messages.size) return messages[streak - 1]
        val iconAliases = listOf("Lay2Icon", "Front2Icon", "Jump1Icon", "HappyIcon")
        val random = Random(daySeed)
        return EmotionMessage(
            iconAliases[random.nextInt(iconAliases.size)],
            if (english) "Today's dance" else "今日的舞步",
            (if (english) continuingBodiesEn else continuingBodies).let {
                it[random.nextInt(it.size)]
            },
        )
    }

    private fun postOrQueue(context: Context, message: EmotionMessage) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!notificationsEnabled(prefs)) return
        val editor = prefs.edit()
        if (postNotification(context, message)) {
            editor.remove(KEY_PENDING_TITLE)
                .remove(KEY_PENDING_BODY)
                .remove(KEY_PENDING_ICON)
                .apply()
            return
        }
        editor
            .putString(KEY_PENDING_TITLE, message.title)
            .putString(KEY_PENDING_BODY, message.body)
            .putString(KEY_PENDING_ICON, message.icon)
            .apply()
    }

    private fun postNotification(context: Context, message: EmotionMessage, notificationId: Int = NOTIFICATION_ID): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Terpsichore 女神訊息",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    // Initial default only: Android preserves existing user settings.
                    enableVibration(true)
                    description = "連續練習、久未上線與回歸提醒"
                },
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) return false

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val largeIcon = BitmapFactory.decodeResource(context.resources, drawableForAlias(message.icon))
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }.setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(largeIcon)
            .setContentTitle(message.title)
            .setContentText(message.body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(message.body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            notification.defaults = notification.defaults or android.app.Notification.DEFAULT_VIBRATE
        }
        manager.notify(notificationId, notification)
        return true
    }

    private fun scheduleNextInactivityCheck(context: Context, triggerAtMillis: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, EmotionAlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pendingIntent)
        val earliest = max(triggerAtMillis, System.currentTimeMillis() + 1_000L)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                earliest,
                pendingIntent,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    earliest,
                    pendingIntent,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    earliest,
                    pendingIntent,
                )
            }
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                earliest,
                pendingIntent,
            )
        }
    }

    private fun cancelInactivityCheck(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            Intent(context, EmotionAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pendingIntent)
    }

    private fun notificationsEnabled(prefs: android.content.SharedPreferences): Boolean =
        prefs.getBoolean(KEY_NOTIFICATIONS_ENABLED, true)

    private fun reminderAt(prefs: android.content.SharedPreferences, epochDay: Long): Long =
        LocalDate.ofEpochDay(epochDay)
            .atTime(
                LocalTime.of(
                    prefs.getInt(KEY_REMINDER_HOUR, DEFAULT_REMINDER_HOUR),
                    prefs.getInt(KEY_REMINDER_MINUTE, DEFAULT_REMINDER_MINUTE),
                ),
            )
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()

    @Synchronized
    private fun normalizeLauncherAliases(context: Context, requestedAlias: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val packageManager = context.packageManager
        val packageName = context.packageName
        val defaultAlias = launcherAlias(context)
        val allowedAliases = emotionAliases + defaultAlias
        val desiredAlias = requestedAlias.takeIf { it in allowedAliases } ?: defaultAlias
        val allAliases = (allowedAliases + legacyLauncherAliases).distinct()

        val alreadyNormalized = allAliases.all { alias ->
            val state = packageManager.getComponentEnabledSetting(
                ComponentName(packageName, "$packageName.$alias"),
            )
            val enabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias == defaultAlias
                else -> false
            }
            enabled == (alias == desiredAlias)
        }
        if (alreadyNormalized) {
            prefs.edit().putString(KEY_CURRENT_ALIAS, desiredAlias).apply()
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val settings = allAliases.map { alias ->
                PackageManager.ComponentEnabledSetting(
                    ComponentName(packageName, "$packageName.$alias"),
                    if (alias == desiredAlias) {
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    } else {
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    },
                    PackageManager.DONT_KILL_APP,
                )
            }
            packageManager.setComponentEnabledSettings(settings)
        } else {
            // Older Android versions do not have the atomic batch API. These
            // calls only run after the task has finished or from a receiver;
            // disable old entries first so two launcher icons never overlap.
            allAliases.filterNot { it == desiredAlias }.forEach { alias ->
                packageManager.setComponentEnabledSetting(
                    ComponentName(packageName, "$packageName.$alias"),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            packageManager.setComponentEnabledSetting(
                ComponentName(packageName, "$packageName.$desiredAlias"),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        prefs.edit().putString(KEY_CURRENT_ALIAS, desiredAlias).apply()
    }

    fun scheduleTestNotification(context: Context) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, EmotionAlarmReceiver::class.java).putExtra("test_notification", true)
        val pending = PendingIntent.getBroadcast(context, 7321, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val at = System.currentTimeMillis() + 10_000L
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } else {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    fun deliverTestNotification(context: Context) {
        val posted = postNotification(context, EmotionMessage("HappyIcon", "Terpsichore 測試通知", "通知與背景鬧鐘測試完成。每日提醒時間未變更。"), 7322)
        android.util.Log.i("TerpsichoreReminder", "testNotification posted=$posted")
    }

    fun testLauncherIcon(context: Context, alias: String) {
        if (hostActivityActive) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_PENDING_ALIAS, alias).apply()
        } else normalizeLauncherAliases(context, alias)
    }

    private fun launcherAlias(context: Context): String =
        context.packageManager
            .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
            .metaData
            ?.getString(META_LAUNCHER_ALIAS)
            ?: FALLBACK_LAUNCHER_ALIAS

    @DrawableRes
    private fun drawableForAlias(alias: String): Int = when (alias) {
        "QuestionIcon" -> R.mipmap.emotion_question
        "WaitingIcon" -> R.mipmap.emotion_waiting
        "AngryLeftIcon" -> R.mipmap.emotion_angry_left
        "AngryRightIcon" -> R.mipmap.emotion_angry_right
        "AngryFrontIcon" -> R.mipmap.emotion_angry_front
        "AngryFront2Icon" -> R.mipmap.emotion_angry_front2
        "SadIcon" -> R.mipmap.emotion_sad
        "Sad2Icon" -> R.mipmap.emotion_sad2
        "Sad3Icon" -> R.mipmap.emotion_sad3
        "HappyIcon" -> R.mipmap.emotion_happy
        "BeginIcon" -> R.mipmap.emotion_begin
        "Side1Icon" -> R.mipmap.emotion_side1
        "Side2Icon" -> R.mipmap.emotion_side2
        "Jump1Icon" -> R.mipmap.emotion_jump1
        "Lay1Icon" -> R.mipmap.emotion_lay1
        "Lay2Icon" -> R.mipmap.emotion_lay2
        "Front2Icon" -> R.mipmap.emotion_front2
        else -> R.mipmap.emotion_delightful
    }
}
