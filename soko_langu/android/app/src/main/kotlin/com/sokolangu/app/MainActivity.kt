package com.sokolangu.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "soko_lang/video_query"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
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
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Upgrade OneSignal default channel to high importance for heads-up popups
            try { manager.deleteNotificationChannel("onesignal_default_channel") } catch (_: Exception) {}
            manager.createNotificationChannel(
                NotificationChannel(
                    "onesignal_default_channel",
                    "Notifications",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Soko Vibe notifications"
                    enableVibration(true)
                    enableLights(true)
                }
            )
            val channels = listOf(
                NotificationChannel(
                    "general_notifications_v4",
                    "Soko Vibe",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Flash sale na notifications nyingine"
                    enableVibration(true)
                    enableLights(true)
                },
                NotificationChannel(
                    "chat_messages_v4",
                    "Chat Messages",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "New message notifications from chats"
                    enableVibration(true)
                    enableLights(true)
                },
                NotificationChannel(
                    "payments_notifications_v4",
                    "Payments",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for payment transactions"
                    enableVibration(true)
                    enableLights(true)
                }
            )
            channels.forEach { manager.createNotificationChannel(it) }
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
