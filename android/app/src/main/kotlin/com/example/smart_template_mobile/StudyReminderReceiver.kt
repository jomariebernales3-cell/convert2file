package com.convert2file.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class StudyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val preferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (preferences.getBoolean("flutter.settings_study_reminder_enabled", false)) {
                schedule(
                    context,
                    preferences.getInt("flutter.settings_study_reminder_hour", 19),
                    preferences.getInt("flutter.settings_study_reminder_minute", 0)
                )
            }
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                android.app.NotificationChannel(CHANNEL_ID, "Study reminders", android.app.NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Time for a study session")
            .setContentText("Open Convert2File to continue your study work.")
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // The user may revoke notification permission after scheduling.
        }
    }

    companion object {
        const val CHANNEL_ID = "convert2file_study_reminders"
        const val NOTIFICATION_ID = 7401
        const val REQUEST_CODE = 7401

        fun schedule(context: Context, hour: Int, minute: Int) {
            val intent = Intent(context, StudyReminderReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val now = java.util.Calendar.getInstance()
            val next = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                set(java.util.Calendar.MINUTE, minute.coerceIn(0, 59))
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
                if (!after(now)) add(java.util.Calendar.DAY_OF_YEAR, 1)
            }
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                next.timeInMillis,
                AlarmManager.INTERVAL_DAY,
                pending
            )
        }

        fun cancel(context: Context) {
            val intent = Intent(context, StudyReminderReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending)
            pending.cancel()
        }
    }
}