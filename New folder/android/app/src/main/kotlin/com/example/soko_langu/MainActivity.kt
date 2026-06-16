package com.example.soko_langu

import android.content.ContentUris
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VIDEO_CHANNEL = "soko_lang/video_query"
    private val DEVICE_CHANNEL = "soko_lang/device_info"
    private val MEDIA_SESSION_CHANNEL = "soko_lang/media_session"
    private val MEDIA_EVENTS_CHANNEL = "soko_lang/media_events"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        setupVideoChannel(flutterEngine)
        setupDeviceChannel(flutterEngine)
        setupMediaSessionChannel(flutterEngine)

        ContextCompat.startForegroundService(
            this,
            Intent(this, PlaybackService::class.java)
        )
    }

    private fun setupVideoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VIDEO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "queryVideos") {
                result.success(queryVideos())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setupDeviceChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getSdkVersion") {
                result.success(Build.VERSION.SDK_INT)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setupMediaSessionChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SESSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initPlaylist" -> {
                        val songs = call.argument<List<Map<String, Any?>>>("songs") ?: emptyList()
                        PlaybackService.initPlaylist(songs)
                        result.success(null)
                    }
                    "playAtIndex" -> {
                        val index = call.argument<Int>("index") ?: 0
                        PlaybackService.playAtIndex(index)
                        result.success(null)
                    }
                    "play" -> {
                        PlaybackService.play()
                        result.success(null)
                    }
                    "pause" -> {
                        PlaybackService.pause()
                        result.success(null)
                    }
                    "togglePlayPause" -> {
                        PlaybackService.togglePlayPause()
                        result.success(null)
                    }
                    "seekTo" -> {
                        val positionMs = call.argument<Long>("positionMs") ?: 0L
                        PlaybackService.seekTo(positionMs)
                        result.success(null)
                    }
                    "next" -> {
                        PlaybackService.next()
                        result.success(null)
                    }
                    "previous" -> {
                        PlaybackService.previous()
                        result.success(null)
                    }
                    "setRepeatMode" -> {
                        val mode = call.argument<Int>("mode") ?: 0
                        PlaybackService.setRepeatMode(mode)
                        result.success(null)
                    }
                    "setShuffle" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        PlaybackService.setShuffle(enabled)
                        result.success(null)
                    }
                    "stop" -> {
                        PlaybackService.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", e.message, Log.getStackTraceString(e))
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_EVENTS_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                PlaybackService.eventSink = { state ->
                    mainHandler.post { events.success(state) }
                }
            }

            override fun onCancel(arguments: Any?) {
                PlaybackService.eventSink = null
            }
        })
    }

    private fun queryVideos(): List<Map<String, Any?>> {
        val videos = mutableListOf<Map<String, Any?>>()
        try {
            val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.WIDTH,
                    MediaStore.Video.Media.HEIGHT,
                    MediaStore.Video.Media.RELATIVE_PATH,
                )
            } else {
                arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                )
            }

            val selection = "${MediaStore.Video.Media.DURATION} > 0"
            val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

            val cursor = contentResolver.query(uri, projection, selection, null, sortOrder)
            cursor?.use {
                val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val durCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)

                while (it.moveToNext()) {
                    val videoId = it.getLong(idCol)
                    var dataPath = ""
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        try {
                            val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                            dataPath = it.getString(dataCol) ?: ""
                        } catch (_: Exception) {}
                    }
                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        videoId,
                    ).toString()

                    videos.add(
                        mapOf<String, Any?>(
                            "displayName" to (it.getString(nameCol) ?: "Unknown"),
                            "id" to videoId,
                            "duration" to it.getLong(durCol),
                            "size" to it.getLong(sizeCol),
                            "data" to dataPath,
                            "contentUri" to contentUri,
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
