package com.mawj.tomatolog

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock

class TimerNotificationService : Service() {
    private var activeTimer: ActiveTimer? = null
    private var completionPosted = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionShow ->
                intent.timerNotification()?.let {
                    startTimer(it, intent.getLongExtra(extraDeadline, 0L))
                }
            actionComplete -> {
                val timer = intent.timerNotification() ?: activeTimer?.notification
                if (timer == null) {
                    stopSelf()
                } else {
                    finishTimer(timer)
                }
            }
            else -> stopSelf()
        }
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        releaseWakeLock()
        activeTimer = null
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    private fun startTimer(timer: TimerNotification, requestedDeadlineWallClock: Long) {
        createChannels()
        completionPosted = false
        val deadlineWallClock =
            requestedDeadlineWallClock.takeIf { it > 0L }
                ?: (System.currentTimeMillis() + timer.remainingSeconds * 1000L)
        val active =
            ActiveTimer(
                notification = timer,
                deadlineElapsedRealtime =
                    SystemClock.elapsedRealtime() +
                        (deadlineWallClock - System.currentTimeMillis()).coerceAtLeast(0L),
                deadlineWallClock = deadlineWallClock,
            )
        activeTimer = active
        acquireWakeLock(active)
        scheduleCompletion(this, active)
        val remainingMillis =
            (active.deadlineElapsedRealtime - SystemClock.elapsedRealtime()).coerceAtLeast(0)
        val displayTimer =
            timer.copy(remainingSeconds = ((remainingMillis + 999) / 1000).toInt())
        val notification = buildTimerNotification(displayTimer, active.deadlineWallClock)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                timerNotificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(timerNotificationId, notification)
        }
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun buildTimerNotification(
        timer: TimerNotification,
        deadlineWallClock: Long,
    ): Notification {
        val contentIntent =
            PendingIntent.getActivity(
                this,
                0,
                packageManager.getLaunchIntentForPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val stopIntent =
            PendingIntent.getActivity(
                this,
                1,
                Intent(this, MainActivity::class.java).apply {
                    action = stopTimerAction
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val builder = notificationBuilder(timerChannelId)
        setTimerIcons(builder, timer)
        builder
            .setContentTitle(timer.displayCategory)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setTimeoutAfter((deadlineWallClock - System.currentTimeMillis()).coerceAtLeast(0L))
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setColor(timer.color)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    "停止",
                    stopIntent,
                ).build(),
            ).extras
            .putBoolean("android.requestPromotedOngoing", true)

        builder
            .setWhen(deadlineWallClock)
            .setUsesChronometer(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setChronometerCountDown(true)
        }
        return builder.build()
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun finishTimer(timer: TimerNotification) {
        if (completionPosted) return
        completionPosted = true
        activeTimer = null
        releaseWakeLock()
        cancelScheduledCompletion(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        notificationManager().cancel(timerNotificationId)
        createChannels()
        val contentIntent =
            PendingIntent.getActivity(
                this,
                2,
                packageManager.getLaunchIntentForPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val builder = notificationBuilder(completionChannelId)
        setTimerIcons(builder, timer)
        builder
            .setContentTitle("专注完成")
            .setContentText("${timer.category} · ${formatTime(timer.totalSeconds)}")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder
                .setSound(completionSoundUri(this))
                .setVibrate(completionVibrationPattern)
        }
        notificationManager().notify(completionNotificationId, builder.build())
        stopSelf()
    }

    private fun setTimerIcons(builder: Notification.Builder, timer: TimerNotification) {
        val bitmap = timer.icon?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && bitmap != null) {
            builder
                .setSmallIcon(Icon.createWithBitmap(bitmap))
                .setLargeIcon(Icon.createWithBitmap(bitmap).setTint(timer.color))
        } else {
            builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
        }
    }

    private fun notificationBuilder(channelId: String) =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }

    private fun createChannels() = ensureChannels(this)

    private fun notificationManager() =
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock(active: ActiveTimer) {
        val lock =
            wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:focus_timer")
                .also {
                    it.setReferenceCounted(false)
                    wakeLock = it
                }
        if (!lock.isHeld) {
            val timeout =
                (active.deadlineElapsedRealtime - SystemClock.elapsedRealtime())
                    .coerceAtLeast(0L) + 60_000L
            lock.acquire(timeout)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    private fun formatTime(seconds: Int) =
        "%02d:%02d".format(seconds / 60, seconds % 60)

    companion object {
        private const val timerNotificationId = 25
        private const val completionNotificationId = 26
        private const val completionTestNotificationId = 28
        private const val timerChannelId = "focus_timer"
        private const val completionChannelId = "timer_complete_v3"
        private const val actionShow = "com.mawj.tomatolog.SHOW_TIMER"
        private const val actionComplete = "com.mawj.tomatolog.COMPLETE_TIMER"
        private const val stopTimerAction = "com.mawj.tomatolog.STOP_TIMER"
        private const val extraCategory = "category"
        private const val extraRemaining = "remaining"
        private const val extraTotal = "total"
        private const val extraColor = "color"
        private const val extraIcon = "icon"
        private const val extraDeadline = "deadline"
        private const val extraIsInterval = "isInterval"
        private const val extraCurrentCycle = "currentCycle"
        private const val extraCycleCount = "cycleCount"
        private const val extraFocusSeconds = "focusSeconds"
        private const val extraIntervalSeconds = "intervalSeconds"
        private const val completionAlarmRequest = 27
        private val completionVibrationPattern = longArrayOf(0, 300, 180, 500)

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannels(
                listOf(
                    NotificationChannel(
                        timerChannelId,
                        "专注倒计时",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "显示当前专注分类和倒计时"
                    },
                    NotificationChannel(
                        completionChannelId,
                        "计时完成",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "倒计时结束时播放应用内置提示音并震动"
                        enableVibration(true)
                        vibrationPattern = completionVibrationPattern
                        setSound(
                            completionSoundUri(context),
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build(),
                        )
                    },
                ),
            )
        }

        private fun completionSoundUri(context: Context): Uri =
            Uri.parse(
                "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/${R.raw.ding}",
            )

        fun showCompletionTest(context: Context) {
            ensureChannels(context)
            val builder =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, completionChannelId)
                } else {
                    Notification.Builder(context)
                        .setSound(completionSoundUri(context))
                        .setVibrate(completionVibrationPattern)
                }
            builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("声音和震动测试")
                .setContentText("如果听到提示音并感到震动，提醒设置已经生效")
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_HIGH)
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(completionTestNotificationId, builder.build())
        }

        fun show(context: Context, timer: TimerNotification) {
            val deadline = System.currentTimeMillis() + timer.remainingSeconds * 1000L
            val intent =
                Intent(context, TimerNotificationService::class.java).apply {
                    action = actionShow
                    putExtra(extraCategory, timer.category)
                    putExtra(extraRemaining, timer.remainingSeconds)
                    putExtra(extraTotal, timer.totalSeconds)
                    putExtra(extraColor, timer.color)
                    putExtra(extraIcon, timer.icon)
                    putExtra(extraDeadline, deadline)
                    putExtra(extraIsInterval, timer.isInterval)
                    putExtra(extraCurrentCycle, timer.currentCycle)
                    putExtra(extraCycleCount, timer.cycleCount)
                    putExtra(extraFocusSeconds, timer.focusSeconds)
                    putExtra(extraIntervalSeconds, timer.intervalSeconds)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun cancel(context: Context) {
            cancelScheduledCompletion(context)
            context.stopService(Intent(context, TimerNotificationService::class.java))
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(timerNotificationId)
        }

        fun complete(context: Context) {
            context.startService(
                Intent(context, TimerNotificationService::class.java).apply {
                    action = actionComplete
                },
            )
        }

        internal fun completeFromAlarm(context: Context, alarmIntent: Intent) {
            val timer = alarmIntent.timerNotification() ?: return
            val next = timer.nextStage()
            if (next != null) {
                show(context, next)
                return
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureChannels(context)
            val contentIntent =
                PendingIntent.getActivity(
                    context,
                    2,
                    context.packageManager.getLaunchIntentForPackage(context.packageName),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            val builder =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, completionChannelId)
                } else {
                    Notification.Builder(context)
                }
            val bitmap = timer.icon?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && bitmap != null) {
                builder
                    .setSmallIcon(Icon.createWithBitmap(bitmap))
                    .setLargeIcon(Icon.createWithBitmap(bitmap).setTint(timer.color))
            } else {
                builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            }
            builder
                .setContentTitle("专注完成")
                .setContentText(
                    "${timer.category} · %02d:%02d".format(
                        timer.totalSeconds / 60,
                        timer.totalSeconds % 60,
                    ),
                ).setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_HIGH)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                builder
                    .setSound(completionSoundUri(context))
                    .setVibrate(completionVibrationPattern)
            }
            manager.notify(completionNotificationId, builder.build())
            manager.cancel(timerNotificationId)
            cancelScheduledCompletion(context)
            context.stopService(Intent(context, TimerNotificationService::class.java))
        }

        private fun scheduleCompletion(context: Context, active: ActiveTimer) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = completionAlarm(context, active.notification)
            val showIntent =
                PendingIntent.getActivity(
                    context,
                    28,
                    context.packageManager.getLaunchIntentForPackage(context.packageName),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(active.deadlineWallClock, showIntent),
                operation,
            )
        }

        private fun cancelScheduledCompletion(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(completionAlarm(context))
        }

        private fun completionAlarm(
            context: Context,
            timer: TimerNotification? = null,
        ): PendingIntent {
            val intent = Intent(context, TimerAlarmReceiver::class.java)
            if (timer != null) {
                intent.putTimerNotification(
                    timer.copy(remainingSeconds = 0),
                )
            }
            return PendingIntent.getBroadcast(
                context,
                completionAlarmRequest,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun Intent.putTimerNotification(timer: TimerNotification) {
            putExtra(extraCategory, timer.category)
            putExtra(extraRemaining, timer.remainingSeconds)
            putExtra(extraTotal, timer.totalSeconds)
            putExtra(extraColor, timer.color)
            putExtra(extraIcon, timer.icon)
            putExtra(extraIsInterval, timer.isInterval)
            putExtra(extraCurrentCycle, timer.currentCycle)
            putExtra(extraCycleCount, timer.cycleCount)
            putExtra(extraFocusSeconds, timer.focusSeconds)
            putExtra(extraIntervalSeconds, timer.intervalSeconds)
        }

        private fun Intent.timerNotification(): TimerNotification? {
            val category = getStringExtra(extraCategory) ?: return null
            return TimerNotification(
                category = category,
                remainingSeconds = getIntExtra(extraRemaining, 0),
                totalSeconds = getIntExtra(extraTotal, 1),
                color = getIntExtra(extraColor, 0),
                icon = getByteArrayExtra(extraIcon),
                isInterval = getBooleanExtra(extraIsInterval, false),
                currentCycle = getIntExtra(extraCurrentCycle, 1),
                cycleCount = getIntExtra(extraCycleCount, 1),
                focusSeconds = getIntExtra(extraFocusSeconds, 1),
                intervalSeconds = getIntExtra(extraIntervalSeconds, 1),
            )
        }
    }
}

class TimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TimerNotificationService.completeFromAlarm(context, intent)
    }
}

data class TimerNotification(
    val category: String,
    val remainingSeconds: Int,
    val totalSeconds: Int,
    val color: Int,
    val icon: ByteArray?,
    val isInterval: Boolean,
    val currentCycle: Int,
    val cycleCount: Int,
    val focusSeconds: Int,
    val intervalSeconds: Int,
) {
    val displayCategory: String
        get() = if (isInterval) "间隔休息" else category

    fun nextStage(): TimerNotification? =
        if (isInterval) {
            copy(
                remainingSeconds = focusSeconds,
                totalSeconds = focusSeconds,
                isInterval = false,
                currentCycle = currentCycle + 1,
            )
        } else if (currentCycle < cycleCount) {
            copy(
                remainingSeconds = intervalSeconds,
                totalSeconds = intervalSeconds,
                isInterval = true,
            )
        } else {
            null
        }
}

private data class ActiveTimer(
    val notification: TimerNotification,
    val deadlineElapsedRealtime: Long,
    val deadlineWallClock: Long,
)
