package com.example.terpsichore

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.assertEquals
import java.time.LocalDate
import java.time.ZoneId

/** Runs against the real PackageManager; isolated preferences preserve user streaks. */
@Suppress("DEPRECATION")
class LauncherRegressionTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private lateinit var isolated: Context
    private lateinit var originalAlias: String

    private fun launchers(): List<String> = isolated.packageManager.queryIntentActivities(
        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            .setPackage(isolated.packageName), 0,
    ).map { it.activityInfo.name.substringAfterLast('.') }

    @Before fun setUp() {
        val base = instrumentation.targetContext
        isolated = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int) =
                base.getSharedPreferences("launcher_regression_$name", mode)
        }
        originalAlias = launchers().single()
        isolated.getSharedPreferences("emotion_backmail", 0).edit().clear()
            .putBoolean("notifications_enabled", false).commit()
        EmotionBackmailManager.onHostActivityDestroyed(isolated, false)
    }

    @After fun tearDown() {
        if (!::originalAlias.isInitialized) return
        try {
            EmotionBackmailManager.onHostActivityDestroyed(isolated, false)
            EmotionBackmailManager.testLauncherIcon(isolated, originalAlias)
        } finally {
            isolated.getSharedPreferences("emotion_backmail", 0).edit().clear().commit()
            // Test opens cancel the shared alarm: restore the user's schedule.
            EmotionBackmailManager.restoreSchedule(instrumentation.targetContext)
        }
    }

    @Test fun testConsecutiveDaysDeferUntilActivityFinishesAndKeepOneIcon() {
        val expected = listOf("DelightfulIcon", "HappyIcon", "BeginIcon", "Side1Icon",
            "Side2Icon", "Jump1Icon", "Lay1Icon", "Lay2Icon")
        val day = LocalDate.now()
        for ((index, alias) in expected.withIndex()) {
            val before = launchers()
            EmotionBackmailManager.onHostActivityCreated()
            val now = day.plusDays(index.toLong()).atTime(12, 0)
                .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val result = EmotionBackmailManager.onAppOpened(isolated, now)
            assertEquals(index + 1, result["onlineStreak"])
            assertEquals("Do not change aliases while picker/activity is alive", before, launchers())
            EmotionBackmailManager.onHostActivityDestroyed(isolated, true)
            assertEquals(listOf(alias), launchers())
            // Same-day opens must not advance the streak or add launcher entries.
            assertEquals(index + 1, EmotionBackmailManager.onAppOpened(isolated, now)["onlineStreak"])
            EmotionBackmailManager.onHostActivityDestroyed(isolated, true)
            assertEquals(listOf(alias), launchers())
        }
    }

    @Test fun testReplacementPreservesSelectedIconAndIsIdempotent() {
        for (alias in listOf("HappyIcon", "BeginIcon", "Sad3Icon")) {
            EmotionBackmailManager.testLauncherIcon(isolated, alias)
            repeat(3) {
                EmotionBackmailManager.onPackageReplaced(isolated)
                assertEquals(listOf(alias), launchers())
            }
        }
    }

    @Test fun testRepairsDuplicateEnabledAliases() {
        EmotionBackmailManager.testLauncherIcon(isolated, "HappyIcon")
        isolated.packageManager.setComponentEnabledSetting(
            android.content.ComponentName(isolated.packageName, "${isolated.packageName}.BeginIcon"),
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            android.content.pm.PackageManager.DONT_KILL_APP,
        )
        assertEquals(2, launchers().size)
        EmotionBackmailManager.onPackageReplaced(isolated)
        assertEquals(listOf("HappyIcon"), launchers())
    }
}
