package com.sokolangu.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.appwidget.AppWidgetManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "soko_lang/video_query"
    private var pendingRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and screen recording app-wide (FLAG_SECURE)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        createNotificationChannels()
        pendingRoute = intent?.getStringExtra("route")
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra("route") ?: return
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, "soko_lang/navigate").invokeMethod("navigate", route)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "queryVideos") {
                result.success(queryVideos())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soko_lang/conversation_notif",
        ).setMethodCallHandler { call, result ->
            if (call.method == "show") {
                val senderName = call.argument<String>("senderName") ?: "Mtumiaji"
                val messageText = call.argument<String>("messageText") ?: ""
                val roomId = call.argument<String>("roomId") ?: ""
                val senderId = call.argument<String>("senderId") ?: ""
                ConversationNotificationHelper.show(this, senderName, messageText, roomId, senderId)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soko_lang/widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val sales = call.argument<String>("sales") ?: "TZS 0"
                    val orders = call.argument<String>("orders") ?: "0"
                    val balance = call.argument<String>("balance") ?: "TZS 0"
                    WidgetDataStore.save(this, sales, orders, balance)
                    val manager = AppWidgetManager.getInstance(this)
                    val ids = manager.getAppWidgetIds(
                        android.content.ComponentName(this, SokoVibeWidgetProvider::class.java)
                    )
                    val data = WidgetDataStore.load(this)
                    ids.forEach { id ->
                        SokoVibeWidgetProvider.updateAppWidget(this, manager, id, data)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        pendingRoute?.let { route ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "soko_lang/navigate",
            ).invokeMethod("navigate", route)
            pendingRoute = null
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Delete old v4/v5 channels (can't modify once created — need new IDs for IMPORTANCE_MAX)
            listOf("onesignal_default_channel","general_notifications_v4","chat_messages_v4","payments_notifications_v4","general_notifications_v5","chat_messages_v5","payments_notifications_v5","system_alerts_v5","ride_notifications_v5").forEach {
                try { manager.deleteNotificationChannel(it) } catch (_: Exception) {}
            }
            // Recreate OneSignal default channel with MAX importance for instant display
            manager.createNotificationChannel(
                NotificationChannel(
                    "onesignal_default_channel",
                    "Notifications",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Soko Vibe notifications — urgent"
                    enableVibration(true)
                    enableLights(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                }
            )
            val channels = listOf(
                NotificationChannel(
                    "general_notifications_v6",
                    "Soko Vibe",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Flash sale, announcements, alerts"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "payments_notifications_v6",
                    "Payments",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Malipo, escrow, payout, refund notifications"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "chat_messages_v6",
                    "Chat Messages",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "New message notifications from chats"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "system_alerts_v6",
                    "System Alerts",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Account security, suspension, verification alerts"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "ride_notifications_v6",
                    "Ride Updates",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Ride requests, cancellations, trip updates"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                }
            )
            channels.forEach { manager.createNotificationChannel(it) }
            // Android 13+ inline replies use the system notification assistant by default
        }
    }

    private fun queryVideos(): List<Map<String, Any?>> {
        val videos = mutableListOf<Map<String, Any?>>()
        try {
            val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DATA,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.DURATION,
                MediaStore.Video.Media.SIZE,
            )
            val cursor = contentResolver.query(uri, projection, null, null, null)
            cursor?.use {
                val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val durCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)

                while (it.moveToNext()) {
                    val videoId = it.getLong(idCol)
                    var dataPath: String? = null
                    try {
                        val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                        dataPath = it.getString(dataCol)
                    } catch (_: Exception) {}
                    videos.add(
                        mapOf<String, Any?>(
                            "displayName" to (it.getString(nameCol) ?: "Unknown"),
                            "id" to videoId,
                            "duration" to it.getLong(durCol),
                            "size" to it.getLong(sizeCol),
                            "data" to (dataPath ?: ""),
                            "contentUri" to ContentUris.withAppendedId(
                                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                videoId,
                            ).toString(),
                        ),
                    )
                }
            }
            Log.d("VideoQuery", "Found ${videos.size} videos")
        } catch (e: Exception) {
            Log.e("VideoQuery", "Error querying videos: ${e.message}", e)
        }
        return videos
    }
}
