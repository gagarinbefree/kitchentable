package com.example.kitchentable

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val prefs by lazy { getSharedPreferences("unread_messages", MODE_PRIVATE) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerUpdates(this, flutterEngine.dartExecutor.binaryMessenger)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "Личные сообщения", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(true) }
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kitchentable/unread")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> {
                        updateBadge(prefs.getInt("count", 0))
                        result.success(prefs.getString("snapshot", null))
                    }
                    "save" -> {
                        val count = call.argument<Int>("count")!!
                        val previous = prefs.getInt("count", 0)
                        prefs.edit().putString("snapshot", call.argument<String>("snapshot"))
                            .putInt("count", count).apply()
                        if (previous != count) updateBadge(count)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPostResume() {
        super.onPostResume()
        if (Build.VERSION.SDK_INT >= 33 && !prefs.getBoolean("asked", false) &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            prefs.edit().putBoolean("asked", true).apply()
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
        val enabled = notifications.areNotificationsEnabled()
        if (enabled && !prefs.getBoolean("wasEnabled", false)) updateBadge(prefs.getInt("count", 0))
        prefs.edit().putBoolean("wasEnabled", enabled).apply()
    }

    private fun updateBadge(count: Int) {
        if (count == 0) {
            notifications.cancel(NOTIFICATION_ID)
            return
        }
        if (!notifications.areNotificationsEnabled()) return
        val openApp = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val intent = PendingIntent.getActivity(this, 0, openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val item = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_message_notification)
            .setContentTitle("KitchenTable")
            .setContentText("Непрочитанных сообщений: $count")
            .setContentIntent(intent)
            .setOnlyAlertOnce(true)
            .setNumber(count)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()
        notifications.notify(NOTIFICATION_ID, item)
    }

    companion object {
        private const val CHANNEL = "direct_messages"
        private const val NOTIFICATION_ID = 1
        private const val REQUEST_NOTIFICATIONS = 1001
    }
}
