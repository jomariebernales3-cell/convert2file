package com.convert2file.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class OfflineAiTaskService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    private val manager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    PROGRESS_CHANNEL,
                    "Offline AI progress",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Shows when Offline AI is working." }
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    RESULT_CHANNEL,
                    "Offline AI results",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Alerts when an Offline AI task finishes." }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                taskTitle = intent.getStringExtra(EXTRA_TITLE) ?: "Offline AI is working"
                acquireWakeLock()
                startForeground(PROGRESS_ID, progressNotification("Starting…"))
            }
            ACTION_UPDATE -> {
                val status = intent.getStringExtra(EXTRA_STATUS) ?: "Still working…"
                try {
                    manager.notify(PROGRESS_ID, progressNotification(status))
                } catch (_: SecurityException) {
                }
            }
            ACTION_FINISH -> {
                val success = intent.getBooleanExtra(EXTRA_SUCCESS, true)
                val message = intent.getStringExtra(EXTRA_MESSAGE) ?: "Task finished."
                try {
                    if (canPostNotifications()) {
                        try {
                            manager.notify(RESULT_ID, resultNotification(success, message))
                        } catch (_: SecurityException) {
                        }
                    }
                } finally {
                    releaseWakeLock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf(startId)
                }
            }
            ACTION_CANCEL -> {
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Convert2File:OfflineAi"
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
    private fun progressNotification(status: String): Notification =
        Notification.Builder(this, PROGRESS_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle(taskTitle)
            .setContentText(status)
            .setContentIntent(openAppIntent())
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

    private fun resultNotification(success: Boolean, message: String): Notification =
        Notification.Builder(this, RESULT_CHANNEL)
            .setSmallIcon(
                if (success) android.R.drawable.ic_menu_info_details
                else android.R.drawable.ic_dialog_alert
            )
            .setContentTitle(if (success) "Offline AI finished" else "Offline AI needs attention")
            .setContentText(message)
            .setContentIntent(openAppIntent())
            .setCategory(Notification.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setDefaults(Notification.DEFAULT_ALL)
            .build()

    private fun openAppIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        return PendingIntent.getActivity(
            this,
            RESULT_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    companion object {
        private const val PROGRESS_CHANNEL = "offline_ai_progress"
        private const val RESULT_CHANNEL = "offline_ai_results"
        private const val PROGRESS_ID = 8301
        private const val RESULT_ID = 8302
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_STATUS = "status"
        private const val EXTRA_SUCCESS = "success"
        private const val EXTRA_MESSAGE = "message"
        const val ACTION_START = "com.convert2file.offline_ai.START"
        const val ACTION_UPDATE = "com.convert2file.offline_ai.UPDATE"
        const val ACTION_FINISH = "com.convert2file.offline_ai.FINISH"
        const val ACTION_CANCEL = "com.convert2file.offline_ai.CANCEL"

        @Volatile
        private var taskTitle = "Offline AI is working"

        fun start(context: Context, title: String) {
            val intent = Intent(context, OfflineAiTaskService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TITLE, title)
            context.startForegroundService(intent)
        }

        fun update(context: Context, status: String) {
            context.startService(
                Intent(context, OfflineAiTaskService::class.java)
                    .setAction(ACTION_UPDATE)
                    .putExtra(EXTRA_STATUS, status)
            )
        }

        fun finish(context: Context, success: Boolean, message: String) {
            context.startService(
                Intent(context, OfflineAiTaskService::class.java)
                    .setAction(ACTION_FINISH)
                    .putExtra(EXTRA_SUCCESS, success)
                    .putExtra(EXTRA_MESSAGE, message)
            )
        }

        fun cancel(context: Context) {
            context.startService(
                Intent(context, OfflineAiTaskService::class.java).setAction(ACTION_CANCEL)
            )
        }
    }
}
